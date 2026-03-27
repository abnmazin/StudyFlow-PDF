import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// Firestore collection: sync_sessions/{code}
///
/// Document fields:
///   createdBy     String          hardwareId of the lecturer
///   isLocked      bool            whether student drawing is locked
///   kicked_uuids  List of String  hardwareIds that are banned from this session
///   participants  List of Map     [{hardwareId, username}]
///   annotations   Map             serialized highlights per pdfId
class SyncService {
  final FirebaseFirestore _db;

  SyncService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // ─────────────────────────────────────────────
  // LECTURER OPERATIONS
  // ─────────────────────────────────────────────

  /// Searches for an existing active session for a given host and file hash.
  Future<String?> findExistingSession(String username, String fileHash) async {
    try {
      final snap = await _db
          .collection('sync_sessions')
          .where('createdBy', isEqualTo: username) // Use Username
          .where('fileHash', isEqualTo: fileHash)
          .limit(1)
          .get();
          
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    } catch (_) {}
    return null;
  }

  /// Generates a new 6-char code with file metadata, creates the Firestore document, returns code.
  Future<String?> generateSessionCode(
    String fileHash,
    int pageCount,
    String hostHardwareId,
    String ownerName,
    String hostUid,
  ) async {
    final existingCode = await findExistingSession(ownerName, fileHash);
    if (existingCode != null) {
      return existingCode;
    }

    final code = _randomCode(6);
    await _db.collection('sync_sessions').doc(code).set({
      'createdBy': ownerName, // Anchor to Username!
      'ownerName': ownerName,
      'fileHash': fileHash,
      'pageCount': pageCount,
      'isLocked': false,
      'joinLocked': false,
      'kicked_uids': <String>[],
      'participants': <Map<String, dynamic>>[], // Cleaner: Participants list is for students only
      'annotations': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  /// Toggles the drawing-lock state for all students.
  Future<void> setLocked(String code, {required bool locked}) async {
    await _db.collection('sync_sessions').doc(code).update({
      'isLocked': locked,
    });
  }

  /// Toggles the join-lock state (prevents new students from joining).
  Future<void> setJoinLocked(String code, {required bool locked}) async {
    await _db.collection('sync_sessions').doc(code).update({
      'joinLocked': locked,
    });
  }

  /// Returns a stream of the session's security state (kicks, locks, etc.)
  Stream<Map<String, dynamic>> watchSessionSecurity(String code) {
    return _db.collection('sync_sessions').doc(code).snapshots().map((snap) {
      if (!snap.exists) return {'exists': false};
      final data = snap.data() ?? {};
      return {
        'exists': true,
        'createdBy': data['createdBy'], // UID
        'ownerName': data['ownerName'] ?? 'محاضر', // Username
        'kicked_uids': List<String>.from(data['kicked_uids'] ?? []),
        'isLocked': data['isLocked'] ?? false,
        'joinLocked': data['joinLocked'] ?? false,
        'participants': List<dynamic>.from(data['participants'] ?? []),
      };
    });
  }

  /// One-off manual check for kick status (Second Line of Defense).
  Future<bool> isUserKicked(String code, String hardwareId) async {
    try {
      final snap = await _db.collection('sync_sessions').doc(code).get();
      if (!snap.exists) return false;
      final kicked = List<String>.from(snap.data()?['kicked_uuids'] ?? []);
      return kicked.contains(hardwareId);
    } catch (_) {
      return false;
    }
  }

  Stream<bool> watchUserExists(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) => snap.exists);
  }

  /// Checks if a user document exists in the 'users' collection.
  Future<bool> checkUserExists(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// Wipes all student annotations from the session document.
  Future<void> clearAllAnnotations(String code) async {
    final snapshot = await _db.collection('sync_sessions').doc(code).collection('annotations').get();
    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// Wipes the server-side annotation document for a single PDF hash inside a session.
  /// Used by Lecturer when they clear all local annotations on an active session.
  Future<void> clearAnnotationsForHash(String code, String fileHash) async {
    await _db
        .collection('sync_sessions')
        .doc(code)
        .collection('annotations')
        .doc(fileHash)
        .set({'data': <dynamic>[]});
  }

  /// Completely deletes the session document and its annotations from Firestore.
  /// Used by Lecturer when they end the class to prevent orphaned data.
  Future<void> deleteSession(String code) async {
    // Note: In Firestore, deleting a document does not automatically delete its subcollections.
    // We must manually delete the annotations first (or run a cloud function, but doing it here is fine for small scale).
    try {
      // 1. Delete all annotation documents in the subcollection
      final annotationsSnap = await _db.collection('sync_sessions').doc(code).collection('annotations').get();
      for (var doc in annotationsSnap.docs) {
        await doc.reference.delete();
      }
      
      // 2. Delete the main session document
      await _db.collection('sync_sessions').doc(code).delete();
      debugPrint('DEBUG: Session $code permanently deleted from Firestore.');
    } catch (e) {
      debugPrint('DEBUG: Error deleting session $code: $e');
    }
  }

  /// Bans a UID AND removes them from the active participants list.
  Future<void> kickParticipant(String code, String uid) async {
    assert(uid.isNotEmpty, 'UID cannot be empty');
    if (uid.isEmpty) return;

    // 1. Add to banned list
    await _db.collection('sync_sessions').doc(code).update({
      'kicked_uids': FieldValue.arrayUnion([uid]),
    });

    // 2. Surgically remove from participants list
    final snap = await _db.collection('sync_sessions').doc(code).get();
    if (snap.exists) {
      final raw = snap.data()?['participants'];
      if (raw is List) {
        final updated = raw.where((p) {
          if (p is Map) {
            final pUid = (p['uid'] ?? p['id'] ?? '')?.toString();
            return pUid != uid;
          }
          return true;
        }).toList();
        await _db.collection('sync_sessions').doc(code).update({'participants': updated});
      }
    }
  }

  /// Removes a UID from the kicked_uids array, allowing them to rejoin.
  Future<void> unkickParticipant(String code, String uid) async {
    await _db.collection('sync_sessions').doc(code).update({
      'kicked_uids': FieldValue.arrayRemove([uid]),
    });
    // Mark as unkicked in the participants list (if they rejoin, they'll be added back anyway, 
    // but this handles the case where they are still in the list but marked isKicked).
    final snap = await _db.collection('sync_sessions').doc(code).get();
    if (snap.exists) {
      final raw = snap.data()?['participants'];
      if (raw is List) {
        final updated = raw.map((p) {
          if (p is Map && (p['uid'] == uid || p['id'] == uid)) {
            return {...p, 'isKicked': false};
          }
          return p;
        }).toList();
        await _db.collection('sync_sessions').doc(code).update({'participants': updated});
      }
    }
  }

  /// Checks if a session document has any annotation data for the current PDF.
  /// Used for "Resumed Session" detection.
  Future<bool> hasAnnotations(String code, String fileHash) async {
    final snap = await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).get();
    return snap.exists;
  }

  /// Fetches the literal truth array of annotations from the server
  Future<List<dynamic>> getServerAnnotations(String code, String fileHash) async {
    final snap = await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).get();
    if (!snap.exists || snap.data() == null) return [];
    final data = snap.data()!['data'];
    if (data is List) return data;
    return [];
  }

  /// Surgically removes a single annotation from the server by its ID.
  /// This prevents "resurrection" by ensuring the server truth is updated immediately.
  Future<void> deleteAnnotation(String code, String fileHash, String annotationId) async {
    final serverItems = await getServerAnnotations(code, fileHash);
    final updated = serverItems.where((item) {
      if (item is Map && item['id'] != null) {
        return item['id'].toString() != annotationId;
      }
      return true;
    }).toList();

    await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).set({
      'data': updated,
    });
    debugPrint('DEBUG: Deleted annotation $annotationId from server ($fileHash).');
  }

  /// Full Bidirectional Reconciliation – treats Firestore as the source of truth.
  ///
  /// Phase 1  → Fetch server state (IDs + raw payloads)
  /// Phase 2  → Local-to-Server: remove local items missing from server (server-deleted orphans)
  /// Phase 3  → Server-to-Local: collect server items missing from local (to be injected by caller)
  /// Phase 4  → Push new local items that have never reached the server
  Future<({
    int deletedCount,
    int uploadedCount,
    int downloadedCount,
    List<Map<String, dynamic>> toAddHighlights,
    List<Map<String, dynamic>> toAddComments,
  })> syncExistingAnnotations({
    required String code,
    required String fileHash,
    required List<Highlight> highlights,
    required List<PdfComment> comments,
  }) async {
    // ── Phase 1: Fetch server truth ──────────────────────────────────────
    final serverItems = await getServerAnnotations(code, fileHash);
    final serverById = <String, Map<String, dynamic>>{
      for (final item in serverItems)
        if (item is Map && item['id'] != null)
          item['id'].toString(): Map<String, dynamic>.from(item)
    };
    final serverIds = serverById.keys.toSet();
    debugPrint('DEBUG: Found ${serverIds.length} items on server.');

    // ── Phase 2: Local-to-Server (purge server-deleted orphans) ──────────
    final deletedHighlightIds = highlights
        .where((h) => h.isSynced && !serverIds.contains(h.id))
        .map((h) => h.id)
        .toSet();
    final deletedCommentIds = comments
        .where((c) => c.isSynced && !serverIds.contains(c.id))
        .map((c) => c.id)
        .toSet();
    final deletedIds = {...deletedHighlightIds, ...deletedCommentIds};
    debugPrint('DEBUG: Removed ${deletedIds.length} items locally (deleted from server).');

    // ── Phase 3: Server-to-Local (items on server but missing locally) ────
    final localIds = {
      ...highlights.map((h) => h.id),
      ...comments.map((c) => c.id),
    };
    final toDownload = serverById.entries
        .where((e) => !localIds.contains(e.key) && !deletedIds.contains(e.key))
        .map((e) => e.value)
        .toList();
    final toAddHighlights = toDownload.where((e) => e['kind'] == 'highlight').toList();
    final toAddComments   = toDownload.where((e) => e['kind'] == 'comment').toList();
    debugPrint('DEBUG: Downloading ${toDownload.length} missing items from server (${toAddHighlights.length} highlights, ${toAddComments.length} comments).');

    // ── Phase 4: Push new local items ────────────────────────────────────
    final newHighlights = highlights.where((h) => !serverIds.contains(h.id) && !h.isSynced).toList();
    final newComments   = comments.where((c) => !serverIds.contains(c.id) && !c.isSynced).toList();
    debugPrint('DEBUG: Uploading ${newHighlights.length + newComments.length} new local items.');

    final newHJson = newHighlights.map((h) => {...h.toJson(isExisting: true), 'kind': 'highlight'}).toList();
    final newCJson = newComments.map((c) => {...c.toJson(isExisting: true), 'kind': 'comment'}).toList();

    // Retain all valid server items (minus deleted orphans) + push new ones
    final retained = serverItems
        .where((item) => item is Map && !deletedIds.contains(item['id']?.toString()))
        .toList();
    final merged = [...retained, ...newHJson, ...newCJson];

    await _db
        .collection('sync_sessions')
        .doc(code)
        .collection('annotations')
        .doc(fileHash)
        .set({'data': merged});

    return (
      deletedCount:     deletedIds.length,
      uploadedCount:    newHJson.length + newCJson.length,
      downloadedCount:  toDownload.length,
      toAddHighlights:  toAddHighlights,
      toAddComments:    toAddComments,
    );
  }

  // ─────────────────────────────────────────────
  // STUDENT OPERATIONS
  // ─────────────────────────────────────────────


  /// Returns [null] on success, or an error message string on failure.
  Future<String?> joinSession({
    required String code,
    required String uid,
    required String username,
    required String studentFileHash,
    required int studentPageCount,
  }) async {
    final snap = await _db.collection('sync_sessions').doc(code).get();
    if (!snap.exists) return 'الجلسة غير موجودة.';

    final data = snap.data()!;
    
    // FILE VALIDATION (MANDATORY)
    final sessionFileHash = data['fileHash'];
    final sessionPageCount = data['pageCount'];

    if (sessionFileHash == null || sessionFileHash != studentFileHash) {
      return 'الملف غير مطابق أو لم يتم تعيين بصمة له. تأكد من فتح نفس النسخة التي يستخدمها المحاضر.';
    }
    if (sessionPageCount == null || sessionPageCount != studentPageCount) {
      return 'عدد الصفحات غير مطابق. تأكد من فتح نفس النسخة.';
    }

    final kickedUids = List<String>.from(data['kicked_uids'] ?? []);
    if (kickedUids.contains(uid)) {
      return 'لقد تم حظرك من هذه الجلسة.';
    }

    // Add participant (idempotent: check first).
    final participants = List<dynamic>.from(data['participants'] ?? []);
    final alreadyIn = participants.any(
      (p) => p is Map && (p['uid'] == uid || p['id'] == uid),
    );

    // JOIN LOCK CHECK: Only block if they are NOT already in the session
    final joinLocked = data['joinLocked'] as bool? ?? false;
    if (joinLocked && !alreadyIn) {
      return 'الجلسة مغلقة حالياً، لا يمكن الانضمام.';
    }

    if (!alreadyIn) {
      await _db.collection('sync_sessions').doc(code).update({
        'participants': FieldValue.arrayUnion([
          {'uid': uid, 'username': username},
        ]),
      });
    }
    return null; // success
  }

  // ─────────────────────────────────────────────
  // DELTA SYNC
  // ─────────────────────────────────────────────

  /// Uploads both highlights and comments for [fileHash] to Firestore.
  /// Used for immediate/buffered sync strategies.
  Future<void> uploadDelta(
    String code,
    String fileHash,
    List<Highlight> highlights,
    List<PdfComment> comments,
  ) async {
    final hJson = highlights.map((h) => {...h.toJson(), 'kind': 'highlight'}).toList();
    final cJson = comments.map((c) => {...c.toJson(), 'kind': 'comment'}).toList();
    final merged = [...hJson, ...cJson];
    
    await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).set({
      'data': merged,
    });
  }

  /// Uploads pre-serialized annotations to Firestore (used by Isolate Sync).
  Future<void> uploadSerializedDelta(
    String code,
    String fileHash,
    List<Map<String, dynamic>> serialized,
  ) async {
    await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).set({
      'data': serialized,
    });
  }

  // ─────────────────────────────────────────────
  // REALTIME STREAM
  // ─────────────────────────────────────────────

  /// Stream of raw document snapshots — used by the student kick-listener.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(String code) {
    return _db.collection('sync_sessions').doc(code).snapshots();
  }

  /// Stream of annotations subcollection for the session.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAnnotations(String code) {
    return _db.collection('sync_sessions').doc(code).collection('annotations').snapshots();
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  String _randomCode(int length) {
    final rng = Random.secure();
    return List.generate(length, (_) => _chars[rng.nextInt(_chars.length)])
        .join();
  }
}
