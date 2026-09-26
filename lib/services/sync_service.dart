import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/pdf_mutation_service.dart';

/// Firestore collection: sync_sessions/{code}
///
/// Document fields:
///   createdBy     String          Username of the lecturer
///   isLocked      bool            whether student drawing is locked
///   kicked_usernames List of String usernames that are banned from this session
///   participants  List of Map     [{uid, username}]
///   (Sub-collection) annotations/{pdfHash}  Map {'data': List}
class SyncService {
  final String _deviceSessionId;
  StreamSubscription? _mutationSubscription;
  final Map<String, int> _lastProcessedSeqNum = {};
  final Map<String, Set<String>> _appliedMutationIds = {};
  final Map<String, int> _lastBroadcastTime = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _annotationSubscription;
  String? _activeAnnotationPath;
  final FirebaseFirestore _db;
  /// uid -> username, so library session creation does not re-read the same
  /// uploader profile on every file open.
  final Map<String, String> _usernameCache = {};

  SyncService({FirebaseFirestore? firestore})
    : _deviceSessionId = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}',
      _db = firestore ?? FirebaseFirestore.instance;

  static Future<void> logMutation(String message) async {
    final timestamp = DateTime.now().toLocal().toString().split('.').first;
    final logLine = '[$timestamp] $message';
    print(logLine);

    if (kIsWeb) return;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(docDir.path, 'StudyFlowPdf', 'Logs'));
      if (!await logDir.exists()) await logDir.create(recursive: true);

      final logFile = File(p.join(logDir.path, 'sync_debug.txt'));
      await logFile.writeAsString(
        '$logLine\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('Error writing to log file: $e');
    }
  }

  // 15-second global timeout for Firestore operations to prevent "Zombie" hangs.
  static const Duration _defaultTimeout = Duration(seconds: 15);

  /// Centralized wrapper for Firestore future operations
  Future<T> _withTimeout<T>(Future<T> future, {String? operationName}) async {
    try {
      return await future.timeout(_defaultTimeout);
    } on TimeoutException {
      debugPrint(
        '🚨 [SyncService] Timeout during: ${operationName ?? 'Unknown Operation'}',
      );
      rethrow;
    } catch (e) {
      debugPrint(
        '🚨 [SyncService] Error during ${operationName ?? 'Unknown Operation'}: $e',
      );
      rethrow;
    }
  }
  // ─────────────────────────────────────────────
  // MASTER BUNDLE OPERATIONS (Phase 13)
  // ─────────────────────────────────────────────

  /// Stream of all master sessions for the developer dashboard.
  Stream<List<Map<String, dynamic>>> watchAllMasterBundles() {
    return _db
        .collection('master_sessions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) => doc.data()).toList();
        });
  }

  /// Creates a master session bundle and returns the generated 8-character code.
  Future<String> createMasterBundle(
    String ownerName,
    List<Map<String, dynamic>> bundle, {
    String? displayName,
  }) async {
    final code = _randomCode(8); // Master codes are 8 chars to distinguish
    await _withTimeout(
      _db.collection('master_sessions').doc(code).set({
        'masterCode': code,
        'ownerName': ownerName,
        'displayName': displayName ?? 'حزمة دراسية جديدة',
        'bundle': bundle,
        'isLocked': false,
        'bannedUsernames': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      }),
      operationName: 'createMasterBundle',
    );
    return code;
  }

  /// Retrieves a master bundle by its code.
  Future<Map<String, dynamic>?> getMasterBundle(String code) async {
    try {
      final snap = await _withTimeout(
        _db.collection('master_sessions').doc(code).get(),
        operationName: 'getMasterBundle',
      );
      if (snap.exists) {
        return snap.data();
      }
    } catch (e) {
      debugPrint('Error fetching master bundle: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────
  // LECTURER OPERATIONS
  // ─────────────────────────────────────────────

  /// Checks if a session code is already taken in the 'sync_sessions' collection.
  Future<bool> isSessionCodeUnique(String code) async {
    final snap = await _db.collection('sync_sessions').doc(code).get();
    return !snap.exists;
  }

  /// Searches for an existing active session for a given host and file hash.
  Future<String?> findExistingSession(String username, String fileHash) async {
    try {
      final snap = await _withTimeout(
        _db
            .collection('sync_sessions')
            .where('createdBy', isEqualTo: username) // Use Username
            .where('fileHash', isEqualTo: fileHash)
            .limit(1)
            .get(),
        operationName: 'findExistingSession',
      );

      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    } catch (_) {}
    return null;
  }

  /// Creates the `sync_sessions/{code}` document for a library file on first
  /// open, so every client that opens the same file content lands on one shared
  /// session without anyone typing a code.
  ///
  /// The uploader owns the session: `createdBy` is anchored to the uploader's
  /// username, exactly like [generateSessionCode], so [findExistingSession]
  /// keeps working for them. The document is only written when missing, making
  /// this safe to call on every open and for students and lecturers alike.
  Future<String?> ensureLibrarySession({
    required String code,
    required String fileHash,
    required String fileName,
    required int pageCount,
    required String uploaderUid,
  }) async {
    try {
      final ref = _db.collection('sync_sessions').doc(code);
      final existing = await _withTimeout(
        ref.get(),
        operationName: 'ensureLibrarySession (Lookup)',
      );
      if (existing.exists) return code;

      final uploaderName = await _resolveUsername(uploaderUid);
      await _withTimeout(
        ref.set({
          'createdBy': uploaderName,
          'ownerName': uploaderName,
          'ownerUid': uploaderUid,
          'displayName': fileName,
          'fileHash': fileHash,
          'pdfName': fileName,
          'pageCount': pageCount,
          'isLocked': false,
          'joinLocked': false,
          'kicked_usernames': <String>[],
          'notesPurgeFor': '',
          'notesPurgeRequestId': '',
          'participants': <Map<String, dynamic>>[],
          'isLibraryFile': true,
          'createdAt': FieldValue.serverTimestamp(),
        }),
        operationName: 'ensureLibrarySession (Main Doc)',
      );

      // Initialize the annotations leaf so the document is visible in the
      // Firestore console, matching generateSessionCode.
      await _withTimeout(
        _db
            .collection('sync_sessions')
            .doc(code)
            .collection('annotations')
            .doc(fileHash)
            .set({'data': <dynamic>[]}),
        operationName: 'ensureLibrarySession (Annotations Leaf)',
      );

      debugPrint(
        '📚 [SYNC] Created library session $code for $fileName (owner $uploaderName)',
      );
      return code;
    } catch (e) {
      debugPrint('📚 [SYNC] ensureLibrarySession failed for $code: $e');
      return null;
    }
  }

  /// Resolves a uid to its username, which is the key every sync_sessions
  /// document is anchored to. Falls back to the uid when the profile doc is
  /// missing so session creation is never blocked. Results are cached because
  /// the same uploader resolves on every file open.
  Future<String> _resolveUsername(String uid) async {
    if (_usernameCache[uid] != null) return _usernameCache[uid]!;
    var name = uid;
    try {
      final snap = await _withTimeout(
        _db.collection('users').doc(uid).get(),
        operationName: 'ensureLibrarySession (Uploader Profile)',
      );
      final resolved = snap.data()?['username'];
      if (resolved is String && resolved.trim().isNotEmpty) {
        name = resolved.trim();
      }
    } catch (_) {}
    _usernameCache[uid] = name;
    return name;
  }

  /// Generates a new code (or uses custom), creates the Firestore document, returns code.
  Future<String?> generateSessionCode(
    String fileHash,
    String pdfName,
    int pageCount,
    String hostHardwareId,
    String ownerName,
    String hostUid, {
    String? customCode,
    String? displayName,
  }) async {
    // 1. If no custom code is provided, check for an existing session by this host for this file.
    if (customCode == null) {
      final existingCode = await findExistingSession(ownerName, fileHash);
      if (existingCode != null) {
        return existingCode;
      }
    }

    // 2. Use custom code if provided, otherwise generate a random one.
    final code = customCode?.toUpperCase() ?? _randomCode(6);

    await _withTimeout(
      _db.collection('sync_sessions').doc(code).set({
        'createdBy': ownerName, // Anchor to Username!
        'ownerName': ownerName,
        'displayName': displayName ?? pdfName,
        'fileHash': fileHash,
        'pdfName': pdfName, // Raw filename
        'pageCount': pageCount,
        'isLocked': false,
        'joinLocked': false,
        'kicked_usernames': <String>[],
        'notesPurgeFor': '',
        'notesPurgeRequestId': '',
        'participants':
            <
              Map<String, dynamic>
            >[], // Cleaner: Participants list is for students only
        'createdAt': FieldValue.serverTimestamp(),
      }),
      operationName: 'generateSessionCode (Main Doc)',
    );

    // Initialize annotations branch (sub-collection) so it's visible in Firestore Console
    final annotDoc = _db
        .collection('sync_sessions')
        .doc(code)
        .collection('annotations')
        .doc(fileHash);
    final annotSnap = await _withTimeout(
      annotDoc.get(),
      operationName: 'generateSessionCode (Annot Check)',
    );
    if (!annotSnap.exists) {
      await _withTimeout(
        annotDoc.set({'data': []}),
        operationName: 'generateSessionCode (Annot Init)',
      );
    }

    return code;
  }

  /// Toggles the drawing-lock state for all students.
  Future<void> setLocked(String code, {required bool locked}) async {
    await _withTimeout(
      _db.collection('sync_sessions').doc(code).update({'isLocked': locked}),
      operationName: 'setLocked',
    );
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
        'displayName': data['displayName'], // Lesson name
        'kicked_usernames': List<String>.from(data['kicked_usernames'] ?? []),
        'notesPurgeFor': data['notesPurgeFor'] ?? '',
        'notesPurgeRequestId': data['notesPurgeRequestId'] ?? '',
        'isLocked': data['isLocked'] ?? false,
        'joinLocked': data['joinLocked'] ?? false,
        'participants': List<dynamic>.from(data['participants'] ?? []),
      };
    });
  }

  /// One-off manual check for kick status (Second Line of Defense).
  Future<bool> isUserKicked(String code, String username) async {
    try {
      final snap = await _withTimeout(
        _db.collection('sync_sessions').doc(code).get(),
        operationName: 'isUserKicked',
      );
      if (!snap.exists) return false;
      final kicked = List<String>.from(snap.data()?['kicked_usernames'] ?? []);
      return kicked.contains(username);
    } catch (_) {
      return false;
    }
  }

  Stream<bool> watchUserExists(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists);
  }

  /// Checks if a user document exists in the 'users' collection.
  Future<bool> checkUserExists(String uid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.exists;
    } catch (_) {
      try {
        final cached = await _db
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        return cached.exists;
      } catch (_) {
        return true;
      }
    }
  }

  /// Checks if a hardwareId is in the 'blacklisted_devices' collection.
  Future<bool> isDeviceBlacklisted(String hardwareId) async {
    try {
      final snap = await _db
          .collection('blacklisted_devices')
          .doc(hardwareId)
          .get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// Wipes all student annotations from the session document.
  Future<void> clearAllAnnotations(String code) async {
    final snapshot = await _db
        .collection('sync_sessions')
        .doc(code)
        .collection('annotations')
        .get();
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
      final annotationsSnap = await _withTimeout(
        _db
            .collection('sync_sessions')
            .doc(code)
            .collection('annotations')
            .get(),
        operationName: 'deleteSession (Annots Fetch)',
      );
      for (var doc in annotationsSnap.docs) {
        await _withTimeout(
          doc.reference.delete(),
          operationName: 'deleteSession (Annot Delete)',
        );
      }

      // 2. Delete the main session document
      await _withTimeout(
        _db.collection('sync_sessions').doc(code).delete(),
        operationName: 'deleteSession (Main)',
      );
      debugPrint('DEBUG: Session $code permanently deleted from Firestore.');
    } catch (e) {
      debugPrint('DEBUG: Error deleting session $code: $e');
    }
  }

  /// Wipe All Sessions (Admin Only)
  Future<void> deleteAllSessions() async {
    final snap = await _db.collection('sync_sessions').get();
    for (var doc in snap.docs) {
      await deleteSession(doc.id);
    }
  }

  /// Wipe All Master Bundles (Admin Only)
  Future<void> deleteAllMasterBundles() async {
    final snap = await _withTimeout(
      _db.collection('master_sessions').get(),
      operationName: 'deleteAllMasterBundles',
    );
    for (var doc in snap.docs) {
      await _withTimeout(
        doc.reference.delete(),
        operationName: 'deleteAllMasterBundles (Item)',
      );
    }
  }

  /// Toggle Master Bundle Lock (Prevents new joins/passive syncs)
  Future<void> toggleMasterBundleLock(String bundleId, bool isLocked) async {
    await _withTimeout(
      _db.collection('master_sessions').doc(bundleId).update({
        'isLocked': isLocked,
      }),
      operationName: 'toggleMasterBundleLock',
    );
  }

  /// Global Ban: Bans a Username from ALL sessions in a master bundle
  Future<void> banUserFromMasterBundle(String bundleId, String username) async {
    final bundleDoc = await _db
        .collection('master_sessions')
        .doc(bundleId)
        .get();
    if (!bundleDoc.exists) return;

    final data = bundleDoc.data()!;
    final List bundleItems = data['bundle'] as List? ?? [];

    // 1. Add to bundle's own banned list (Username)
    await _db.collection('master_sessions').doc(bundleId).update({
      'bannedUsernames': FieldValue.arrayUnion([username]),
    });

    // 2. Propagate to all sub-sessions
    for (var item in bundleItems) {
      if (item is Map && item.containsKey('sessionCode')) {
        await kickParticipant(item['sessionCode'], username);
      }
    }
  }

  /// Unban from all files in a bundle
  Future<void> unbanUserFromMasterBundle(
    String bundleId,
    String username,
  ) async {
    final bundleDoc = await _db
        .collection('master_sessions')
        .doc(bundleId)
        .get();
    if (!bundleDoc.exists) return;

    final data = bundleDoc.data()!;
    final List bundleItems = data['bundle'] as List? ?? [];

    // 1. Remove from bundle's own banned list
    await _db.collection('master_sessions').doc(bundleId).update({
      'bannedUsernames': FieldValue.arrayRemove([username]),
    });

    // 2. Propagate to all sub-sessions
    for (var item in bundleItems) {
      if (item is Map && item.containsKey('sessionCode')) {
        await unkickParticipant(item['sessionCode'], username);
      }
    }
  }

  /// Registers a student as having activated this bundle
  Future<void> registerMasterBundleActivation(
    String bundleId,
    String username,
  ) async {
    await _db.collection('master_sessions').doc(bundleId).update({
      'activators': FieldValue.arrayUnion([username]),
    });
  }

  /// Bans a Username AND removes them from the active participants list.
  Future<void> kickParticipant(String code, String username) async {
    assert(username.isNotEmpty, 'Username cannot be empty');
    if (username.isEmpty) return;

    // 1. Add to banned list
    await _db.collection('sync_sessions').doc(code).update({
      'kicked_usernames': FieldValue.arrayUnion([username]),
      // Ensure traditional kick never carries a stale notes-purge instruction.
      'notesPurgeFor': '',
      'notesPurgeRequestId': '',
    });

    // 2. Surgically remove from participants list
    final snap = await _withTimeout(
      _db.collection('sync_sessions').doc(code).get(),
      operationName: 'kickParticipant (Snap)',
    );
    if (snap.exists) {
      final raw = snap.data()?['participants'];
      if (raw is List) {
        final updated = raw.where((p) {
          if (p is Map) {
            final pName = (p['username'] ?? '')?.toString();
            return pName != username;
          }
          return true;
        }).toList();
        await _withTimeout(
          _db.collection('sync_sessions').doc(code).update({
            'participants': updated,
          }),
          operationName: 'kickParticipant (Update)',
        );
      }
    }
  }

  /// Kicks a user and instructs their client to keep only their own notes.
  Future<void> purgeNotesAndKickParticipant(
    String code,
    String username,
  ) async {
    assert(username.isNotEmpty, 'Username cannot be empty');
    if (username.isEmpty) return;

    await _withTimeout(
      _db.collection('sync_sessions').doc(code).update({
        'kicked_usernames': FieldValue.arrayUnion([username]),
        'notesPurgeFor': username,
        'notesPurgeRequestId': DateTime.now().millisecondsSinceEpoch.toString(),
      }),
      operationName: 'purgeNotesAndKickParticipant',
    );

    final snap = await _withTimeout(
      _db.collection('sync_sessions').doc(code).get(),
      operationName: 'purgeNotesAndKickParticipant (Snap)',
    );
    if (snap.exists) {
      final raw = snap.data()?['participants'];
      if (raw is List) {
        final updated = raw.where((p) {
          if (p is Map) {
            final pName = (p['username'] ?? '')?.toString();
            return pName != username;
          }
          return true;
        }).toList();
        await _withTimeout(
          _db.collection('sync_sessions').doc(code).update({
            'participants': updated,
          }),
          operationName: 'purgeNotesAndKickParticipant (Update)',
        );
      }
    }
  }

  /// Removes a Username from the kicked_usernames array, allowing them to rejoin.
  Future<void> unkickParticipant(String code, String username) async {
    await _db.collection('sync_sessions').doc(code).update({
      'kicked_usernames': FieldValue.arrayRemove([username]),
      'notesPurgeFor': '',
      'notesPurgeRequestId': '',
    });
    // Mark as unkicked in the participants list (if they rejoin, they'll be added back anyway)
    final snap = await _db.collection('sync_sessions').doc(code).get();
    if (snap.exists) {
      final raw = snap.data()?['participants'];
      if (raw is List) {
        final updated = raw.map((p) {
          if (p is Map && p['username'] == username) {
            return {...p, 'isKicked': false};
          }
          return p;
        }).toList();
        await _db.collection('sync_sessions').doc(code).update({
          'participants': updated,
        });
      }
    }
  }

  /// Checks if a session document has any annotation data for the current PDF.
  /// Used for "Resumed Session" detection.
  Future<bool> hasAnnotations(String code, String fileHash) async {
    final snap = await _db
        .collection('sync_sessions')
        .doc(code)
        .collection('annotations')
        .doc(fileHash)
        .get();
    if (!snap.exists) return false;
    final List data = snap.data()?['data'] as List? ?? [];
    return data.isNotEmpty;
  }

  /// Fetches the literal truth array of annotations from the server
  Future<({List<dynamic> items, int lastDeletedAt})> getServerAnnotations(
    String code,
    String fileHash,
  ) async {
    final snap = await _withTimeout(
      _db
          .collection('sync_sessions')
          .doc(code)
          .collection('annotations')
          .doc(fileHash)
          .get(),
      operationName: 'getServerAnnotations',
    );
    if (!snap.exists || snap.data() == null)
      return (items: [], lastDeletedAt: 0);

    final items = snap.data()!['data'];
    final lastDeletedAt = (snap.data()!['lastDeletedAt'] as num?)?.toInt() ?? 0;

    if (items is List) return (items: items, lastDeletedAt: lastDeletedAt);
    return (items: [], lastDeletedAt: lastDeletedAt);
  }

  /// Surgically removes a single annotation from the server by its ID.
  /// This prevents "resurrection" by ensuring the server truth is updated immediately.
  Future<void> deleteAnnotation(
    String code,
    String fileHash,
    String annotationId,
  ) async {
    final serverData = await getServerAnnotations(code, fileHash);
    final serverItems = serverData.items;

    final updated = serverItems.where((item) {
      if (item is Map && item['id'] != null) {
        return item['id'].toString() != annotationId;
      }
      return true;
    }).toList();

    await _withTimeout(
      _db
          .collection('sync_sessions')
          .doc(code)
          .collection('annotations')
          .doc(fileHash)
          .set({
            'data': updated,
            'lastDeletedAt': DateTime.now().millisecondsSinceEpoch,
          }),
      operationName: 'deleteAnnotation',
    );
    debugPrint(
      'DEBUG: Deleted annotation $annotationId from server ($fileHash).',
    );
  }

  /// Full Bidirectional Reconciliation – treats Firestore as the source of truth.
  ///
  /// Phase 1  → Fetch server state (IDs + raw payloads)
  /// Phase 2  → Local-to-Server: remove local items missing from server (server-deleted orphans)
  /// Phase 3  → Server-to-Local: collect server items missing from local (to be injected by caller)
  /// Phase 4  → Push new local items that have never reached the server
  Future<
    ({
      int deletedCount,
      int uploadedCount,
      int downloadedCount,
      List<Map<String, dynamic>> toAddHighlights,
      List<Map<String, dynamic>> toAddComments,
      Set<String> serverIds,
      Set<String> orphans,
      int serverLastDeletedAt,
    })
  >
  syncExistingAnnotations({
    required String code,
    required String fileHash,
    required List<Highlight> highlights,
    required List<PdfComment> comments,
    Set<String> locallyDeletedIds = const {},
  }) async {
    // ── Phase 1: Fetch server truth ──────────────────────────────────────
    final serverRes = await getServerAnnotations(code, fileHash);
    final serverItems = serverRes.items;
    final serverLastDeletedAt = serverRes.lastDeletedAt;

    final serverById = <String, Map<String, dynamic>>{
      for (final item in serverItems)
        if (item is Map && item['id'] != null)
          item['id'].toString(): Map<String, dynamic>.from(item),
    };
    final serverIds = serverById.keys.toSet();
    debugPrint(
      'DEBUG: Found ${serverIds.length} items on server. LastDeleted: $serverLastDeletedAt',
    );

    // ── Phase 2: Reconciliation (Conflicts & Orphans) ────────────────────

    // a. Identify orphans to delete locally
    final orphans = <String>{};
    for (final h in highlights) {
      if (h.isSynced && !serverIds.contains(h.id)) {
        // Missing from server. Deleted by someone else?
        if (h.updatedAt < serverLastDeletedAt) {
          orphans.add(h.id);
        }
      }
    }
    for (final c in comments) {
      if (c.isSynced && !serverIds.contains(c.id)) {
        if (c.updatedAt < serverLastDeletedAt) {
          orphans.add(c.id);
        }
      }
    }

    // b. Identify local mods that override server truth (Last-Writer-Wins)
    final localModified = <String>{};
    for (final h in highlights) {
      if (serverIds.contains(h.id)) {
        final sItem = serverById[h.id]!;
        final sUpdatedAt = (sItem['updatedAt'] as num?)?.toInt() ?? 0;
        if (!h.isSynced || h.updatedAt > sUpdatedAt) {
          localModified.add(h.id);
        }
      }
    }
    for (final c in comments) {
      if (serverIds.contains(c.id)) {
        final sItem = serverById[c.id]!;
        final sUpdatedAt = (sItem['updatedAt'] as num?)?.toInt() ?? 0;
        if (!c.isSynced || c.updatedAt > sUpdatedAt) {
          localModified.add(c.id);
        }
      }
    }

    final deletedIds = {...orphans, ...locallyDeletedIds};
    if (deletedIds.isNotEmpty) {
      debugPrint(
        'DEBUG: Purging ${deletedIds.length} items (orphans + local-deleted).',
      );
    }

    // ── Phase 3: Server-to-Local (download missing or newer server items) ─
    final localIds = {
      ...highlights.map((h) => h.id),
      ...comments.map((c) => c.id),
    };

    final toDownload = <Map<String, dynamic>>[];
    for (final sItem in serverItems) {
      if (sItem is! Map) continue;
      final sid = sItem['id']?.toString() ?? '';
      if (deletedIds.contains(sid)) continue;

      if (!localIds.contains(sid)) {
        toDownload.add(Map<String, dynamic>.from(sItem));
      } else {
        // Conflict check: is server newer than local?
        final sUpdatedAt = (sItem['updatedAt'] as num?)?.toInt() ?? 0;
        // Find local item
        final lH = highlights.where((h) => h.id == sid).firstOrNull;
        final lC = comments.where((c) => c.id == sid).firstOrNull;
        final lUpdatedAt = lH?.updatedAt ?? lC?.updatedAt ?? 0;

        if (sUpdatedAt > lUpdatedAt) {
          toDownload.add(Map<String, dynamic>.from(sItem));
        }
      }
    }

    final toAddHighlights = toDownload
        .where((e) => e['kind'] == 'highlight')
        .toList();
    final toAddComments = toDownload
        .where((e) => e['kind'] == 'comment')
        .toList();
    if (toDownload.isNotEmpty) {
      debugPrint('DEBUG: Downloading ${toDownload.length} items.');
    }

    // ── Phase 4: Push new/modified local items ───────────────────────────
    final newHighlights = highlights
        .where(
          (h) =>
              !orphans.contains(h.id) &&
              (!serverIds.contains(h.id) || localModified.contains(h.id)),
        )
        .toList();
    final newComments = comments
        .where(
          (c) =>
              !orphans.contains(c.id) &&
              (!serverIds.contains(c.id) || localModified.contains(c.id)),
        )
        .toList();

    if (newHighlights.isNotEmpty || newComments.isNotEmpty) {
      debugPrint(
        'DEBUG: Uploading ${newHighlights.length + newComments.length} items.',
      );
    }

    final newHJson = newHighlights
        .map(
          (h) => {
            ...h.toJson(isExisting: true),
            'isSynced': true,
            'kind': 'highlight',
          },
        )
        .toList();
    final newCJson = newComments
        .map(
          (c) => {
            ...c.toJson(isExisting: true),
            'isSynced': true,
            'kind': 'comment',
          },
        )
        .toList();

    // ── Write Guard: لا تكتب لو ما في تغيير فعلي ────────────────────────
    final hasChanges =
        newHJson.isNotEmpty || newCJson.isNotEmpty || deletedIds.isNotEmpty;

    if (hasChanges) {
      final annotationRef = _db
          .collection('sync_sessions')
          .doc(code)
          .collection('annotations')
          .doc(fileHash);
      await _withTimeout(
        _db.runTransaction((transaction) async {
          final currentSnapshot = await transaction.get(annotationRef);
          final currentData = currentSnapshot.data() ?? <String, dynamic>{};
          final currentItems = currentData['data'] is List
              ? List<dynamic>.from(currentData['data'] as List)
              : <dynamic>[];
          final currentById = <String, dynamic>{
            for (final item in currentItems)
              if (item is Map && item['id'] != null) item['id'].toString(): item,
          };

          for (final id in deletedIds) {
            currentById.remove(id);
          }
          for (final item in [...newHJson, ...newCJson]) {
            final id = item['id']?.toString();
            if (id != null) currentById[id] = item;
          }

          final transactionPayload = <String, dynamic>{
            'data': currentById.values.toList(),
            'updatedAt': FieldValue.serverTimestamp(),
            'revision': FieldValue.increment(1),
          };
          if (locallyDeletedIds.isNotEmpty) {
            transactionPayload['lastDeletedAt'] =
                DateTime.now().millisecondsSinceEpoch;
          }
          transaction.set(annotationRef, transactionPayload, SetOptions(merge: true));
        }),
        operationName: 'syncExistingAnnotations (Transactional Push)',
      );
      debugPrint(
        'DEBUG: Write executed — ${newHJson.length + newCJson.length} uploaded, ${deletedIds.length} deleted.',
      );
    } else {
      debugPrint('DEBUG: Write skipped — no changes detected.');
    }

    return (
      deletedCount: deletedIds.length,
      uploadedCount: newHJson.length + newCJson.length,
      downloadedCount: toDownload.length,
      toAddHighlights: toAddHighlights,
      toAddComments: toAddComments,
      serverIds: {
        ...serverIds,
        ...newHighlights.map((h) => h.id),
        ...newComments.map((c) => c.id),
      },
      orphans: orphans,
      serverLastDeletedAt: serverLastDeletedAt,
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
    final snap = await _withTimeout(
      _db.collection('sync_sessions').doc(code).get(),
      operationName: 'joinSession (Metadata)',
    );
    if (!snap.exists) return 'الجلسة غير موجودة.';

    final data = snap.data()!;

    // FILE VALIDATION (MANDATORY)
    final sessionFileHash = data['fileHash'];
    final sessionPageCount = data['pageCount'];

    if (sessionFileHash == null || sessionFileHash != studentFileHash) {
      return 'الملف غير مطابق أو لم يتم تعيين بصمة له. تأكد من فتح نفس النسخة التي يستخدمها المحاضر.';
    }
    // If hash matches, allow join even if page counts differ.
    // Local page count can vary due to metadata/cache timing and should not block valid files.
    if (sessionPageCount != null && sessionPageCount != studentPageCount) {
      debugPrint(
        '⚠️ [SyncService] joinSession pageCount mismatch ignored: server=$sessionPageCount local=$studentPageCount',
      );
    }

    final kickedUsernames = List<String>.from(data['kicked_usernames'] ?? []);
    if (kickedUsernames.contains(username)) {
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

  /// Removes a participant from the session participants list when they leave voluntarily.
  Future<void> leaveSession({
    required String code,
    required String uid,
    required String username,
  }) async {
    final ref = _db.collection('sync_sessions').doc(code);
    final snap = await _withTimeout(
      ref.get(),
      operationName: 'leaveSession (Fetch)',
    );
    if (!snap.exists) return;

    final raw = snap.data()?['participants'];
    if (raw is! List) return;

    final updated = raw.where((p) {
      if (p is Map) {
        final pUid = (p['uid'] ?? p['id'] ?? '').toString();
        final pUsername = (p['username'] ?? '').toString();
        final uidMatch = uid.isNotEmpty && pUid == uid;
        final usernameMatch = username.isNotEmpty && pUsername == username;
        return !(uidMatch || usernameMatch);
      }
      return true;
    }).toList();

    await _withTimeout(
      ref.update({'participants': updated}),
      operationName: 'leaveSession (Update)',
    );
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
    final hJson = highlights
        .map((h) => {...h.toJson(), 'kind': 'highlight'})
        .toList();
    final cJson = comments
        .map((c) => {...c.toJson(), 'kind': 'comment'})
        .toList();
    final merged = [...hJson, ...cJson];

    await _withTimeout(
      _db
          .collection('sync_sessions')
          .doc(code)
          .collection('annotations')
          .doc(fileHash)
          .set({'data': merged}),
      operationName: 'uploadDelta',
    );
  }

  /// Uploads pre-serialized annotations to Firestore (used by Isolate Sync).
  Future<void> uploadSerializedDelta(
    String code,
    String fileHash,
    List<Map<String, dynamic>> serialized,
  ) async {
    await _withTimeout(
      _db
          .collection('sync_sessions')
          .doc(code)
          .collection('annotations')
          .doc(fileHash)
          .set({'data': serialized}),
      operationName: 'uploadSerializedDelta',
    );
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
    return _db
        .collection('sync_sessions')
        .doc(code)
        .collection('annotations')
        .snapshots();
  }

  /// Watches one PDF annotation document and emits its complete annotation
  /// payload whenever another client changes it.
  Future<void> startRealtimeAnnotations(
    String code,
    String fileHash, {
    required void Function(List<dynamic> items, int lastDeletedAt) onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final path = 'sync_sessions/$code/annotations/$fileHash';
    if (_activeAnnotationPath == path && _annotationSubscription != null) return;

    await stopRealtimeAnnotations();
    _activeAnnotationPath = path;
    _annotationSubscription = _db
        .collection('sync_sessions')
        .doc(code)
        .collection('annotations')
        .doc(fileHash)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) {
            onData(const [], 0);
            return;
          }
          final data = snapshot.data() ?? <String, dynamic>{};
          final rawItems = data['data'];
          final items = rawItems is List ? List<dynamic>.from(rawItems) : const <dynamic>[];
          final lastDeletedAt = (data['lastDeletedAt'] as num?)?.toInt() ?? 0;
          onData(items, lastDeletedAt);
        }, onError: onError);
  }

  Future<void> stopRealtimeAnnotations() async {
    await _annotationSubscription?.cancel();
    _annotationSubscription = null;
    _activeAnnotationPath = null;
  }

  Future<void> dispose() async {
    await stopRealtimeAnnotations();
    await _mutationSubscription?.cancel();
    _mutationSubscription = null;
    _lastProcessedSeqNum.clear();
    _appliedMutationIds.clear();
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  String _randomCode(int length) {
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => _chars[rng.nextInt(_chars.length)],
    ).join();
  }

  /// Watch all master bundles created by a specific owner
  Stream<List<Map<String, dynamic>>> watchMasterBundlesByOwner(
    String username,
  ) {
    return _db
        .collection('master_sessions')
        .where('ownerName', isEqualTo: username)
        .snapshots()
        .map((snap) {
          // Sort in memory to avoid requiring complex Firestore indexes
          final docs = snap.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();
          docs.sort((a, b) {
            final aTime = a['createdAt'] as Timestamp?;
            final bTime = b['createdAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });
          return docs;
        });
  }

  // ─────────────────────────────────────────────
  // ANNOUNCEMENTS
  // ─────────────────────────────────────────────

  /// Real-time stream of announcements, filtered by role and ordered by newest first.
  Stream<List<Map<String, dynamic>>> watchAnnouncements(
    String currentUserRole,
  ) {
    final normalizedRole = currentUserRole == 'member'
        ? 'student'
        : currentUserRole;

    List<String> targets;
    if (normalizedRole == 'developer') {
      // Developers see everything, including the student+developer channel.
      targets = [
        'all',
        'student',
        'lecturer',
        'developer',
        'student_developer',
      ];
    } else if (normalizedRole == 'lecturer') {
      // Lecturers only receive global and lecturer-targeted announcements.
      targets = ['all', 'lecturer'];
    } else {
      // Students (including legacy `member`) receive student-only and student+developer.
      targets = ['all', 'student', 'student_developer'];
    }

    return _db
        .collection('announcements')
        .where('targetAudience', whereIn: targets)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(),
        );
  }

  /// Publishes a new announcement to Firestore.
  Future<void> publishAnnouncement({
    required String title,
    required String body,
    required String type, // 'warning', 'info', 'update'
    required String authorName,
    String targetAudience =
        'all', // 'all', 'student', 'lecturer', 'developer', 'student_developer'
  }) async {
    await _withTimeout(
      _db.collection('announcements').add({
        'title': title,
        'body': body,
        'type': type,
        'authorName': authorName,
        'targetAudience': targetAudience,
        'createdAt': FieldValue.serverTimestamp(),
      }),
      operationName: 'publishAnnouncement',
    );
  }

  /// Deletes an announcement from Firestore permanently.
  Future<void> deleteAnnouncement(String docId) async {
    try {
      await _db.collection('announcements').doc(docId).delete();
      debugPrint('🗑️ تم حذف الإشعار من السيرفر: $docId');
    } catch (e) {
      debugPrint('❌ خطأ في حذف الإشعار: $e');
    }
  }

  // ─────────────────────────────────────────────
  // GLOBAL TRASH SYNC (Collaborative Trash)
  // ─────────────────────────────────────────────

  /// Syncs deleted annotations (Trash) for a session.
  /// 1. Pushes local unsynced deletions to Firestore.
  /// 2. Fetches new deletions from Firestore.
  /// 3. Returns a list of new deletions to be saved locally.
  Future<List<Map<String, dynamic>>> syncDeletedAnnotations({
    required String sessionCode,
    required List<Map<String, dynamic>> localUnsynced,
  }) async {
    final trashCol = _db
        .collection('sync_sessions')
        .doc(sessionCode)
        .collection('trash');

    // 1. Push local unsynced
    for (final item in localUnsynced) {
      final originalId = item['originalId'] as String;
      await _withTimeout(
        trashCol.doc(originalId).set(item),
        operationName: 'pushDeletedAnnotation',
      );
    }

    // 2. Fetch from Firestore
    final snap = await _withTimeout(
      trashCol.get(),
      operationName: 'fetchDeletedAnnotations',
    );

    return snap.docs.map((doc) => doc.data()).toList();
  }

  /// Removes a record from the remote trash collection when an item is restored.
  Future<void> removeAnnotationFromRemoteTrash(
    String sessionCode,
    String originalId,
  ) async {
    await _withTimeout(
      _db
          .collection('sync_sessions')
          .doc(sessionCode)
          .collection('trash')
          .doc(originalId)
          .delete(),
      operationName: 'removeAnnotationFromRemoteTrash',
    );
  }

  // ─────────────────────────────────────────────
  // PDF DOCUMENT MUTATIONS (Page Shifts / Deletes)
  // ─────────────────────────────────────────────

  /// Broadcasts a PDF structural mutation (e.g., page deletion) to other connected clients.
  Future<void> broadcastMutation(
    String fileHash,
    String action,
    int pageIndex,
  ) async {
    // Debounce: ignore duplicate calls within 500ms for same action+page
    final key = '$fileHash:$action:$pageIndex';
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastBroadcastTime[key] ?? 0;
    if (now - last < 500) {
      debugPrint('⏭️ [BROADCAST] Debounced duplicate: $action pageIndex=$pageIndex');
      return;
    }
    _lastBroadcastTime[key] = now;

    final mutationCol = _db
        .collection('pdfs')
        .doc(fileHash)
        .collection('mutations');

    try {
      final seqNum = now;
      SyncService.logMutation(
        '🚀 [SYNC SENDER] Writing to Firestore: pdfs/$fileHash/mutations',
      );
      await _withTimeout(
        mutationCol.add({
          'action': action,
          'pageIndex': pageIndex,
          'seqNum': seqNum,
          'senderId': _deviceSessionId,
          'timestamp': FieldValue.serverTimestamp(),
        }),
        operationName: 'broadcastMutation',
      );
      SyncService.logMutation('✅ [SYNC SENDER] Broadcast successful!');
    } catch (e) {
      SyncService.logMutation('❌ [SYNC SENDER] Broadcast FAILED: $e');
    }
  }

  void listenToMutations(
    String fileHash,
    String localPdfId,
    AppProvider appProvider,
  ) {
    SyncService.logMutation(
      '📡 [SYNC RECEIVER] Initializing listener for fileHash: $fileHash, localPdfId: $localPdfId',
    );
    _mutationSubscription?.cancel();

    final startSeqNum = DateTime.now().millisecondsSinceEpoch - 2000;
    // Always reset on new subscription — handles re-open after file deletion
    _lastProcessedSeqNum[fileHash] = startSeqNum;

    debugPrint('🎧 [SYNC RECEIVER] Subscribing to mutations for hash: $fileHash, seqNum > ${_lastProcessedSeqNum[fileHash]}');

    _mutationSubscription = _db
        .collection('pdfs')
        .doc(fileHash)
        .collection('mutations')
        .where('seqNum', isGreaterThan: _lastProcessedSeqNum[fileHash])
        .orderBy('seqNum')
        .snapshots()
        .listen((snapshot) async {
          for (var change in snapshot.docChanges) {
            debugPrint('📨 [RECEIVER RAW] docChange type=${change.type.name}, id=${change.doc.id}, data=${change.doc.data()}');
            if (change.type != DocumentChangeType.added) continue;

            final data = change.doc.data();
            if (data == null) continue;

            // ANTI-ECHO: Skip mutations sent by this same device
            final senderId = (data['senderId'] ?? '').toString();
            if (senderId == _deviceSessionId) {
              debugPrint('⏭️ [ANTI-ECHO] Skipping echo mutation from self (senderId=$senderId)');
              continue;
            }

            // Primary dedup: by Firestore document ID (survives listener reattach)
            final docId = change.doc.id;
            _appliedMutationIds.putIfAbsent(fileHash, () => {});
            if (_appliedMutationIds[fileHash]!.contains(docId)) {
              debugPrint('⏭️ [DEDUP] Already applied mutation $docId — skipping');
              continue;
            }

            final seqNum = (data['seqNum'] as num?)?.toInt();
            if (seqNum == null) continue;

            final lastSeen = _lastProcessedSeqNum[fileHash] ?? startSeqNum;
            if (seqNum <= lastSeen) {
              debugPrint('⏭️ [DEDUP] seqNum $seqNum <= lastSeen $lastSeen — skipping');
              continue;
            }

            // Mark BEFORE async work to prevent race condition double-apply
            _appliedMutationIds[fileHash]!.add(docId);
            _lastProcessedSeqNum[fileHash] = seqNum;

            final action = (data['action'] ?? '').toString();
            final pageIndex = (data['pageIndex'] as num?)?.toInt();
            if (pageIndex == null) continue;

            debugPrint(
              '🔥 [SYNC RECEIVER] New mutation detected: action=$action pageIndex=$pageIndex seqNum=$seqNum docId=$docId',
            );

            // Validate page index before applying to prevent corruption
            final currentPdf = appProvider.getPdf(localPdfId);
            final currentPageCount = currentPdf?.pageCount ?? 0;

            if (action == 'delete_page') {
              if (pageIndex < 0 || (currentPageCount > 0 && pageIndex >= currentPageCount)) {
                debugPrint('⚠️ [RECEIVER] delete_page index $pageIndex out of bounds (pages: $currentPageCount) — skipping');
                continue;
              }
              debugPrint('🔥 [RECEIVER] Applying delete_page at index $pageIndex (pages: $currentPageCount)');
              await appProvider.deletePage(localPdfId, pageIndex);
            } else if (action == 'insert_page') {
              if (pageIndex < 0 || pageIndex > currentPageCount) {
                debugPrint('⚠️ [RECEIVER] insert_page index $pageIndex out of bounds (pages: $currentPageCount) — skipping');
                continue;
              }
              debugPrint('🔥 [RECEIVER] Applying insert_page at index $pageIndex (pages: $currentPageCount)');
              await appProvider.addPage(localPdfId, insertAtIndex: pageIndex);
            }
          }
        }, onError: (e) {
          debugPrint('❌ [SYNC RECEIVER] Listener FAILED for $fileHash: $e');
          debugPrint('❌ [SYNC RECEIVER] This is likely a missing Firestore composite index!');
        });
  }
}
