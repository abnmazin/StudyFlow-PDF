import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/folder_announcement.dart';

/// Firestore subcollection:
/// `university_folders/{folderId}/announcements/{announcementId}`
///
/// See `FolderAnnouncement` for the fields.
///
/// Writes are staff-only in two independent places, because the client check is
/// a convenience and the rules are the actual boundary: [_assertCanPublish]
/// turns a mistake into an Arabic error message, and `firestore.rules` turns a
/// forged request into a permission denial.
///
/// Who counts as staff: `AppUser.isLecturer`, which is true for `lecturer` *and*
/// for `admin`/`developer`. The announcement is the professor's note, so a
/// lecturer has to be able to post one; an admin runs the library and has to be
/// able to remove one. `isStudent` cannot reach either method.
class FolderAnnouncementService {
  FolderAnnouncementService({FirebaseFirestore? firestore, this.currentUser})
    : _db = firestore ?? FirebaseFirestore.instance;

  static const String foldersCollection = 'university_folders';
  static const String announcementsCollection = 'announcements';

  /// Newest first, capped. A subject folder accumulates one note per lecture;
  /// a hundred is more than a semester and keeps the listener cheap.
  static const int pageSize = 100;

  /// 15 seconds, the same budget `SyncService` and `TimetableService` give every
  /// Firestore call.
  static const Duration _defaultTimeout = Duration(seconds: 15);

  final FirebaseFirestore _db;

  /// The signed-in user, or null. A public mutable field so `AppProvider` can
  /// hand it over on login without the service reaching back into a provider,
  /// which would close an import cycle through `app_state.dart`.
  AppUser? currentUser;

  /// The path as a string, for logs and for the rules comment.
  static String collectionPath(String folderId) =>
      '$foldersCollection/$folderId/$announcementsCollection';

  CollectionReference<Map<String, dynamic>> _collection(String folderId) => _db
      .collection(foldersCollection)
      .doc(folderId)
      .collection(announcementsCollection);

  Future<T> _withTimeout<T>(Future<T> future, {String? operationName}) async {
    try {
      return await future.timeout(_defaultTimeout);
    } on TimeoutException {
      debugPrint(
        '🚨 [FolderAnnouncementService] Timeout during: ${operationName ?? 'operation'}',
      );
      rethrow;
    } catch (e) {
      debugPrint(
        '🚨 [FolderAnnouncementService] Error during ${operationName ?? 'operation'}: $e',
      );
      rethrow;
    }
  }

  /// Throws unless the signed-in user may post to, or remove from, a folder.
  ///
  /// The same check the Firestore rules make, kept here so a denied write fails
  /// with an Arabic sentence in a snackbar instead of a raw `PERMISSION_DENIED`.
  void _assertCanPublish() {
    final user = currentUser;
    if (user == null) {
      throw UnsupportedError('يجب تسجيل الدخول أولاً');
    }
    if (!user.isLecturer) {
      throw UnsupportedError('نشر الإعلانات متاح للأستاذ والمدير فقط');
    }
  }

  /// The folder's announcements, newest first.
  ///
  /// A stream rather than a one-shot read because the list is shared: a
  /// professor posting from another device has to appear here without the
  /// reader refreshing. `orderBy` on a single field with no filter is served
  /// from the default single-field index, so no composite index is needed.
  ///
  /// The client re-sorts on top of the server's order for the one case the
  /// server cannot order: a write that has not been acknowledged yet carries no
  /// server timestamp, and would otherwise sit at the end of the list for a
  /// frame before jumping to the top.
  Stream<List<FolderAnnouncement>> watchAnnouncements(String folderId) {
    if (folderId.isEmpty) {
      return Stream<List<FolderAnnouncement>>.value(const []);
    }
    return _collection(
      folderId,
    ).orderBy('createdAt', descending: true).limit(pageSize).snapshots().map((
      snapshot,
    ) {
      final items = snapshot.docs
          .map((doc) => FolderAnnouncement.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  /// Posts one note to [folderId] and returns its new document id.
  ///
  /// [imageUrl] is a link to an image that is *already* in Supabase Storage —
  /// the composer uploads it before calling here, because a failed upload has
  /// to be a failed publish and not a note pointing at nothing. Null for a
  /// text-only note, which is still the common case.
  Future<String> publish({
    required String folderId,
    required String title,
    required String body,
    String? imageUrl,
  }) async {
    _assertCanPublish();
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    final cleanImageUrl = (imageUrl ?? '').trim();

    final invalid = FolderAnnouncement.validationMessage(
      title: cleanTitle,
      body: cleanBody,
      imageUrl: cleanImageUrl,
    );
    if (invalid != null) throw ArgumentError(invalid);

    final user = currentUser!;
    final reference = await _withTimeout(
      _collection(folderId).add({
        'title': cleanTitle,
        'body': cleanBody,
        'imageUrl': cleanImageUrl.isEmpty ? null : cleanImageUrl,
        // The display name is snapshotted rather than looked up at read time:
        // the card has to survive a profile rename, and a profile deletion.
        'authorName': user.displayName.trim().isEmpty
            ? user.username
            : user.displayName.trim(),
        'authorUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      }),
      operationName: 'publish',
    );
    return reference.id;
  }

  Future<void> delete({required String folderId, required String id}) async {
    _assertCanPublish();
    if (id.isEmpty) return;
    await _withTimeout(
      _collection(folderId).doc(id).delete(),
      operationName: 'delete',
    );
  }
}
