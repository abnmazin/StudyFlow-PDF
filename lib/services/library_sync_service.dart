import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/university_file.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySyncService
//
// Every university library file carries its OWN sync code (stored on
// university_files.syncCode and auto-generated at upload/backfill).
// Session document: library_file_sessions/{syncCode}
//
// Fields:
//   code            String      The file's sync code
//   universityId    String      University the file belongs to
//   fileId          String      university_files doc id
//   fileHash        String      SHA-256 of the booklet
//   fileName        String      Display name of the booklet
//   ownerUid        String      Owner (manager) account UID
//   ownerUsername   String      Owner username ("abnmazin")
//   downloads       List<Map>   [{uid, username, downloadedAt}]
//   lastDownloadAt  Number      Millis of the latest download
//   createdAt       Timestamp   Server timestamp
//
// Auto-connect: opening a booklet from any university account links it to the
// file's sync code with zero user input (no code entry, nothing displayed).
// The owner (username "abnmazin") sees the live downloads feed in the sidebar.
// Management controls (kick/delete) are intentionally left for later work.
// ─────────────────────────────────────────────────────────────────────────────

class LibrarySyncService {
  /// The account that owns/manages the university library.
  static const String ownerUsername = 'abnmazin';

  static const int _maxDownloads = 200;
  static const Duration _dedupeWindow = Duration(minutes: 3);
  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final FirebaseFirestore _db;

  LibrarySyncService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String syncCode) =>
      _db.collection('library_file_sessions').doc(syncCode);

  /// Generates a fresh 6-char sync code (safe charset, no confusing chars).
  static String generateSyncCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => _chars[rng.nextInt(_chars.length)]).join();
  }

  /// Deterministic fallback code derived from a file hash — used when a file
  /// somehow still has no syncCode yet (e.g. opened before the owner's
  /// backfill), so the recording never breaks.
  static String codeFromHash(String fileHash) {
    final clean = fileHash.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (clean.isEmpty) {
      return 'FILE${DateTime.now().millisecondsSinceEpoch % 1000000}';
    }
    final upper = clean.toUpperCase();
    return upper.length >= 6
        ? upper.substring(0, 6)
        : upper.padRight(6, 'K');
  }

  static bool isOwner(AppUser? user) =>
      user != null &&
      user.username.trim().toLowerCase() == ownerUsername.toLowerCase();

  /// Creates the per-file session doc for [file] if it does not exist.
  Future<void> ensureFileSession({
    required AppUser owner,
    required UniversityFile file,
  }) async {
    final code = file.syncCode ?? codeFromHash(file.fileHash);
    final ref = _ref(code);
    try {
      final snap = await ref.get();
      if (snap.exists) return;
      await ref.set({
        'code': code,
        'universityId': file.universityId,
        'fileId': file.id,
        'fileHash': file.fileHash,
        'fileName': file.name,
        'ownerUid': owner.uid,
        'ownerUsername': ownerUsername,
        'downloads': <dynamic>[],
        'lastDownloadAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '📡 [LibrarySync] Created file session for code $code (${file.name})',
      );
    } catch (e) {
      final snap = await ref.get();
      if (!snap.exists) {
        debugPrint('📡 [LibrarySync] ensureFileSession failed: $e');
      }
    }
  }

  /// Live stream of ALL file-sessions belonging to a university — used by the
  /// owner dashboard feed.
  Stream<List<Map<String, dynamic>>> watchLibraryDownloads(
    String universityId,
  ) {
    return _db
        .collection('library_file_sessions')
        .where('universityId', isEqualTo: universityId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList(),
        );
  }

  /// Records that [file] was downloaded/opened by [user], keyed by the file's
  /// sync code. The owner's own opens are never recorded. Re-opens of the same
  /// booklet by the same user within 3 minutes just refresh the timestamp.
  Future<void> recordDownload({
    required AppUser user,
    required UniversityFile file,
  }) async {
    if (isOwner(user)) return;
    final code = file.syncCode ?? codeFromHash(file.fileHash);
    final now = DateTime.now().millisecondsSinceEpoch;

    final ref = _ref(code);
    try {
      // Auto-create the per-file session on first download.
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'code': code,
          'universityId': file.universityId,
          'fileId': file.id,
          'fileHash': file.fileHash,
          'fileName': file.name,
          'ownerUid': '',
          'ownerUsername': ownerUsername,
          'downloads': <dynamic>[],
          'lastDownloadAt': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final fresh = await ref.get();
      final raw = fresh.data()?['downloads'];
      final downloads =
          raw is List
              ? List<Map<String, dynamic>>.from(raw.whereType<Map>())
              : <Map<String, dynamic>>[];

      downloads.removeWhere((d) {
        final sameUser =
            d['uid'] == user.uid || d['username'] == user.username;
        final sameFile = d['fileHash'] == file.fileHash;
        final recent =
            now - ((d['downloadedAt'] as num?)?.toInt() ?? 0) <
            _dedupeWindow.inMilliseconds;
        return sameUser && sameFile && recent;
      });

      downloads.insert(0, {
        'uid': user.uid,
        'username': user.username,
        'downloadedAt': now,
      });
      if (downloads.length > _maxDownloads) {
        downloads.removeRange(_maxDownloads, downloads.length);
      }

      await ref.set({
        'downloads': downloads,
        'lastDownloadAt': now,
        'ownerUsername': ownerUsername,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('📡 [LibrarySync] recordDownload failed: $e');
    }
  }
}