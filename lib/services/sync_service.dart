import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Generates a new 6-char code with file metadata, creates the Firestore document, returns code.
  Future<String> generateSessionCode({
    required String hostHardwareId,
    required String fileHash,
    required int pageCount,
  }) async {
    final code = _randomCode(6);
    await _db.collection('sync_sessions').doc(code).set({
      'createdBy': hostHardwareId,
      'fileHash': fileHash,
      'pageCount': pageCount,
      'isLocked': false,
      'kicked_uuids': <String>[],
      'participants': <Map<String, dynamic>>[],
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

  /// Wipes all student annotations from the session document.
  Future<void> clearAllAnnotations(String code) async {
    final snapshot = await _db.collection('sync_sessions').doc(code).collection('annotations').get();
    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// Appends a hardwareId to the kicked_uuids array, effectively banning them.
  Future<void> kickParticipant(String code, String hardwareId) async {
    await _db.collection('sync_sessions').doc(code).update({
      'kicked_uuids': FieldValue.arrayUnion([hardwareId]),
      'participants': FieldValue.arrayRemove(
        // We cannot use arrayRemove with partial match, so just re-fetch
        // and write — see _removeParticipant helper below.
        <Map<String, dynamic>>[],
      ),
    });
    // Clean the participant entry separately.
    await _removeParticipantByHardwareId(code, hardwareId);
  }

  /// Checks if a session document has any annotation data for the current PDF.
  /// Used for "Resumed Session" detection.
  Future<bool> hasAnnotations(String code, String fileHash) async {
    final snap = await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).get();
    return snap.exists;
  }

  /// Performs a bulk upload of highlights and comments. Tags them as isExisting.
  Future<void> syncExistingAnnotations({
    required String code,
    required String fileHash,
    required List<Highlight> highlights,
    required List<PdfComment> comments,
  }) async {
    // For highlights, we map to JSON and tag with isExisting
    final hJson = highlights.map((h) => h.toJson(isExisting: true)).toList();
    // For comments, we map to JSON and tag with isExisting
    final cJson = comments.map((c) => c.toJson(isExisting: true)).toList();

    // Since our DB currently store highlights in a list, we'll keep it as a combined list
    // but with metadata if needed. For now, let's keep it consistent with uploadDelta.
    // If the user wants to sync both, we'll merge them or use a sub-map.
    
    // Structure: sync_sessions/{code}/annotations/{pdfId}: [list of highlights/comments]
    // To distinguish, we'll add 'kind': 'highlight' or 'kind': 'comment' to each item if combined.
    // BUT the current uploadDelta only sends Highlights.
    
    final combined = [
      ...hJson.map((h) => {...h, 'kind': 'highlight'}),
      ...cJson.map((c) => {...c, 'kind': 'comment'}),
    ];

    await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).set({
      'data': combined,
    });
  }

  Future<void> _removeParticipantByHardwareId(
    String code,
    String hardwareId,
  ) async {
    final snap = await _db.collection('sync_sessions').doc(code).get();
    if (!snap.exists) return;
    final raw = snap.data()?['participants'];
    if (raw is! List) return;
    final updated = raw
        .whereType<Map>()
        .where((p) => p['hardwareId'] != hardwareId)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    await _db.collection('sync_sessions').doc(code).update({
      'participants': updated,
    });
  }

  // ─────────────────────────────────────────────
  // STUDENT OPERATIONS
  // ─────────────────────────────────────────────

  /// Returns [null] on success, or an error message string on failure.
  Future<String?> joinSession({
    required String code,
    required String hardwareId,
    required String username,
    required String studentFileHash,
    required int studentPageCount,
  }) async {
    final snap = await _db.collection('sync_sessions').doc(code).get();
    if (!snap.exists) return 'Session not found.';

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

    final kicked = List<String>.from(data['kicked_uuids'] ?? []);
    if (kicked.contains(hardwareId)) {
      return 'You are banned from this session.';
    }

    // Add participant (idempotent: check first).
    final participants = List<dynamic>.from(data['participants'] ?? []);
    final alreadyIn = participants.any(
      (p) => p is Map && p['hardwareId'] == hardwareId,
    );

    if (!alreadyIn) {
      await _db.collection('sync_sessions').doc(code).update({
        'participants': FieldValue.arrayUnion([
          {'hardwareId': hardwareId, 'username': username},
        ]),
      });
    }
    return null; // success
  }

  // ─────────────────────────────────────────────
  // DELTA SYNC
  // ─────────────────────────────────────────────

  /// Uploads the full highlights list for [fileHash] to Firestore.
  /// Called on every `onPanEnd` when a session is active.
  Future<void> uploadDelta(
    String code,
    String fileHash,
    List<Highlight> highlights,
  ) async {
    final serialized =
        highlights.map((h) => {...h.toJson(), 'kind': 'highlight'}).toList();
    await _db.collection('sync_sessions').doc(code).collection('annotations').doc(fileHash).set({
      'data': serialized,
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
