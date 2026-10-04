import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/dashboard_quote.dart';

/// Firestore collection: `dashboard_quotes/{quoteId}`
///
///   text        String   the quotation, ≤280 characters
///   author      String   who said it, printed under it, ≤80 characters
///   pinned      bool     the admin's override; one at a time, see below
///   updatedBy   String   display name of the admin who last wrote it
///   createdAt   Timestamp  server time, never a client clock
///   updatedAt   Timestamp  server time
///
/// One shared list for every user, for the same reason the timetable is one
/// shared table: the dashboard's quote panel is authored once in one place and
/// read by everyone, so a personal copy would show each reader a different
/// quotation in a different order, or none at all.
///
/// Not an Isar collection, unlike tasks and reading statistics: those are
/// personal and per-device, and a quotation typed by an admin has to reach
/// every other device.
///
/// Writes are admin-only in two independent places, because the client check is
/// a convenience and the rules are the actual boundary: [_assertAdmin] here
/// turns a mistake into an Arabic error message, and `firestore.rules` section
/// 20 turns a forged request into a permission denial.
class QuoteService {
QuoteService({FirebaseFirestore? firestore, this.currentUser})
    : _db = firestore ?? FirebaseFirestore.instance;

  static const String collectionPath = 'dashboard_quotes';

  /// 15 seconds, the same budget `TimetableService` and
  /// `FolderAnnouncementService` give every Firestore call.
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
        '🚨 [QuoteService] Timeout during: ${operationName ?? 'operation'}',
      );
      rethrow;
    } catch (e) {
      debugPrint(
        '🚨 [QuoteService] Error during ${operationName ?? 'operation'}: $e',
      );
      rethrow;
    }
  }

  /// Throws unless the signed-in user may write the list.
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
      throw UnsupportedError('إدارة الاقتباسات متاحة للمدير فقط');
    }
  }

  /// Every quote, oldest first, which is the order the admin typed them in.
  ///
  /// A stream rather than a one-shot read because the list is shared: an admin
  /// editing it in another window has to appear in an open dashboard without the
  /// reader refreshing. `orderBy` is on a single field with no filter, so
  /// Firestore serves it from the default single-collection index.
  Stream<List<DashboardQuote>> watchQuotes() {
    return _db.collection(collectionPath).orderBy('createdAt').snapshots().map((
      snapshot,
    ) {
      final quotes = <DashboardQuote>[];
      for (final doc in snapshot.docs) {
        final quote = DashboardQuote.fromFirestore(doc.id, doc.data());
        if (quote != null) quotes.add(quote);
      }
      return quotes;
    });
  }

  /// Creates or updates one quote, chosen by whether [quote] already has an id.
  Future<void> saveQuote(DashboardQuote quote) async {
    _assertAdmin();
    final text = quote.text.trim();
    final author = quote.author.trim();

    final invalid = DashboardQuote.validationMessage(
      text: text,
      author: author,
    );
    if (invalid != null) throw ArgumentError(invalid);

    final payload = quote.copyWith(
      text: text,
      author: author,
      updatedBy: currentUser?.displayName ?? '—',
    );

    await _withTimeout(
      quote.id.isEmpty
          ? _db.collection(collectionPath).add(payload.toFirestore())
          : _db
                .collection(collectionPath)
                .doc(quote.id)
                .set(payload.toFirestore(), SetOptions(merge: true)),
      operationName: 'saveQuote',
    );
  }

  Future<void> deleteQuote(String id) async {
    _assertAdmin();
    if (id.isEmpty) return;
    await _withTimeout(
      _db.collection(collectionPath).doc(id).delete(),
      operationName: 'deleteQuote',
    );
  }

  /// Pins [id], or unpins every quote when [id] is null or empty.
  ///
  /// Pinning a field is not a single-document write: "only one quote is pinned"
  /// means every *other* document has to change, and two separate writes that
  /// half-succeeded would leave two pinned quotes and a panel with no rule about
  /// which one wins. Hence one batch — Firestore applies it atomically, so the
  /// list is either entirely before the pin or entirely after it.
  Future<void> setPinned(String? id) async {
    _assertAdmin();

    final collection = _db.collection(collectionPath);
    final snapshot = await _withTimeout(
      collection.get(),
      operationName: 'setPinned:read',
    );
    final target = (id == null || id.isEmpty) ? null : id;

    final batch = _db.batch();
    var touched = false;
    for (final doc in snapshot.docs) {
      final isPinned = doc.data()['pinned'] == true;
      // Skip a document already in the state it is being put into: the batch is
      // sent either way, and carrying every quotation on the dashboard to pin
      // one of them writes to rows nobody meant to touch.
      if (doc.id == target ? isPinned : !isPinned) continue;
      batch.update(doc.reference, {'pinned': doc.id == target});
      touched = true;
    }
    if (!touched) return;

    await _withTimeout(batch.commit(), operationName: 'setPinned:write');
  }
}
