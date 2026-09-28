import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/timetable_entry.dart';

/// Firestore collection: `timetable_entries/{entryId}`
///
///   title        String   course or session name
///   room         String   room or hall
///   weekday      int      1 (Monday) .. 7 (Sunday), matching `DateTime`
///   startMinutes int      minutes from midnight
///   endMinutes   int      minutes from midnight, after startMinutes
///   updatedBy    String   display name of the admin who last wrote it
///   updatedAt    Timestamp  server time, never a client clock
///
/// One shared table for every user. Scoping it per university, college, or stage
/// was considered and rejected for now: `AppUser` carries those fields, but they
/// are filled in inconsistently across the login paths, and a schedule that
/// silently shows nothing because a user's `stage` string does not match what the
/// admin typed is a worse failure than one table everybody reads.
///
/// Not an Isar collection, unlike tasks and reading stats: those are personal
/// and per-device, and a timetable is authored once in one place and read by
/// everyone. Isar's `StudyTask` is the counter-example that proves the split —
/// a shared schedule written by one admin would only exist on the admin's disk.
///
/// Writes are admin-only in two independent places, because the client check is
/// a convenience and the rules are the actual boundary: [_assertAdmin] here
/// turns a mistake into an Arabic error message, and `firestore.rules` turns a
/// forged request into a permission denial.
class TimetableService {
  TimetableService({FirebaseFirestore? firestore, this.currentUser})
    : _db = firestore ?? FirebaseFirestore.instance;

  static const String collectionPath = 'timetable_entries';

  /// 15 seconds, the same budget `SyncService` gives every Firestore call. Long
  /// enough for a slow write, short enough that a hanging one is not mistaken for
  /// a lost network by the caller.
  static const Duration _defaultTimeout = Duration(seconds: 15);

  final FirebaseFirestore _db;

  /// The signed-in user, or null. A public mutable field so `AppProvider` can
  /// hand it over on login without the service reaching back into a provider,
  /// which would close an import cycle through `app_state.dart`.
  AppUser? currentUser;

  Future<T> _withTimeout<T>(Future<T> future, {String? operationName}) async {
    try {
      return await future.timeout(_defaultTimeout);
    } on TimeoutException {
      debugPrint(
        '🚨 [TimetableService] Timeout during: ${operationName ?? 'operation'}',
      );
      rethrow;
    } catch (e) {
      debugPrint(
        '🚨 [TimetableService] Error during ${operationName ?? 'operation'}: $e',
      );
      rethrow;
    }
  }

  /// Throws unless the signed-in user may write the table.
  ///
  /// The same check the Firestore rules make, kept here so a denied write fails
  /// with an Arabic sentence in a snackbar instead of a raw `PERMISSION_DENIED`
  /// dialog. The rules are still the boundary: this one can be bypassed by any
  /// client that does not go through this service.
  void _assertAdmin() {
    final user = currentUser;
    if (user == null) {
      throw UnsupportedError('يجب تسجيل الدخول أولاً');
    }
    if (!user.isAdmin) {
      throw UnsupportedError('هذه العملية متاحة للمدير فقط');
    }
  }

  /// Live table, newest weekday order handled by the caller.
  ///
  /// A stream rather than a one-shot read because the table is shared: an admin
  /// editing it in another window has to appear in an open dashboard without the
  /// reader refreshing. `orderBy` is on a single field with no filter, which
  /// Firestore serves from the default single-collection index — a compound
  /// order would demand a composite index the project has not declared.
  Stream<List<TimetableEntry>> watchEntries() {
    return _db.collection(collectionPath).orderBy('weekday').snapshots().map((
      snapshot,
    ) {
      final entries = <TimetableEntry>[];
      for (final doc in snapshot.docs) {
        final entry = TimetableEntry.fromFirestore(doc.id, doc.data());
        if (entry != null) entries.add(entry);
      }
      // The server ordered by weekday alone, so two lectures on the same day
      // come back in id order. Sorting by start time on top of that is what
      // makes the card read as a day rather than as a set.
      entries.sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        if (byDay != 0) return byDay;
        return a.startMinutes.compareTo(b.startMinutes);
      });
      return entries;
    });
  }

  /// Creates or updates one entry, chosen by whether [entry] already has an id.
  Future<void> saveEntry(TimetableEntry entry) async {
    _assertAdmin();
    final title = entry.title.trim();
    // One rule, one sentence. The check itself lives in the model because the
    // admin's editor shows the same message inline before it lets the save
    // through — repeating the two conditions here would mean two wordings for one
    // rule, and one of them drifting.
    final invalid = TimetableEntry.validationMessage(
      title: title,
      startMinutes: entry.startMinutes,
      endMinutes: entry.endMinutes,
    );
    if (invalid != null) throw ArgumentError(invalid);

    final payload = entry.copyWith(
      title: title,
      room: entry.room.trim(),
      updatedBy: currentUser?.displayName ?? '—',
    );

    await _withTimeout(
      entry.id.isEmpty
          ? _db.collection(collectionPath).add(payload.toFirestore())
          : _db
                .collection(collectionPath)
                .doc(entry.id)
                .set(payload.toFirestore(), SetOptions(merge: true)),
      operationName: 'saveEntry',
    );
  }

  Future<void> deleteEntry(String id) async {
    _assertAdmin();
    if (id.isEmpty) return;
    await _withTimeout(
      _db.collection(collectionPath).doc(id).delete(),
      operationName: 'deleteEntry',
    );
  }
}
