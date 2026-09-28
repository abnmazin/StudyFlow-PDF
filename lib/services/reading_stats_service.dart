import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../models/isar_models.dart';
import 'file_manager_service.dart';

/// Daily reading aggregates, and the rules the dashboard reads them with.
///
/// The app keeps no reading history anywhere else: the viewer stores a position
/// per document (`lastPage`, `lastOpenedAt`) and the cloud library stores the
/// same for a booklet, so "how much did I read today" is not derivable from
/// existing data. [ReadingDay] is that missing aggregate, and this service is
/// the only writer and the only reader of it.
///
/// Deliberately local. A reading total is personal, small, and would be a
/// per-device concept anyway (a day logged on the desktop should not follow the
/// user to their phone), so it stays in Isar instead of Firestore.
class ReadingStatsService {
  static final ReadingStatsService _instance = ReadingStatsService._internal();
  factory ReadingStatsService() => _instance;
  ReadingStatsService._internal();

  /// One focus point per this many focused seconds. Five minutes is short
  /// enough that a single glance does not score, and long enough that a real
  /// sitting reaches a round number.
  static const int secondsPerPoint = 300;

  /// A day only extends the streak past this many focused seconds, so a stray
  /// two-minute glance does not break a run of weeks.
  static const int streakMinimumSeconds = 300;

  /// Points shown as the "focus" goal in the dashboard header.
  static const int dailyGoalPoints = 16;

  int _pendingSeconds = 0;
  int _pendingPages = 0;
  bool _flushing = false;

  /// Focused seconds recorded but not yet written. The reader session uses this
  /// to decide when the buffer is worth a transaction.
  int get pendingSeconds => _pendingSeconds;

  // ─── Key helpers ───────────────────────────────────────────────────────────

  /// Local calendar day as `yyyy-MM-dd`. Local, not UTC: a reading session that
  /// runs past midnight should count for the day the user experienced.
  static String dateKeyOf(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  // ─── Writing (called by the viewer session) ────────────────────────────────

  /// Adds focused reading time for the pending day. Buffered rather than
  /// written per call: the session ticks every 30 seconds and a write per tick
  /// would put needless transactions in the middle of reading.
  void addFocusSeconds(int seconds) {
    if (seconds <= 0) return;
    _pendingSeconds += seconds;
  }

  /// Adds forward page advances. Negative and zero values are ignored, so
  /// scrolling back up never subtracts.
  void addPagesAdvanced(int pages) {
    if (pages <= 0) return;
    _pendingPages += pages;
  }

  /// Writes whatever is buffered. Safe to call often: it is a no-op when
  /// nothing is pending, and overlapping calls are dropped rather than queued
  /// so a burst of flushes cannot double-write.
  Future<void> flush({DateTime? at}) async {
    if (_flushing) return;
    if (_pendingSeconds <= 0 && _pendingPages <= 0) return;

    final seconds = _pendingSeconds;
    final pages = _pendingPages;
    _pendingSeconds = 0;
    _pendingPages = 0;
    _flushing = true;

    try {
      final fileManager = FileManagerService();
      if (!fileManager.isInitialized) await fileManager.init();
      final isar = fileManager.isar;

      final day = await isar.readingDays
          .filter()
          .dateKeyEqualTo(dateKeyOf(at ?? DateTime.now()))
          .findFirst();

      final row =
          day ??
          (ReadingDay()
            ..dateKey = dateKeyOf(at ?? DateTime.now())
            ..focusSeconds = 0
            ..pagesAdvanced = 0);

      row
        ..focusSeconds = row.focusSeconds + seconds
        ..pagesAdvanced = row.pagesAdvanced + pages
        ..updatedAt = DateTime.now();

      await isar.writeTxn(() async {
        await isar.readingDays.put(row);
      });
    } catch (e) {
      // Reading statistics are decorative. A failed write must never interrupt
      // reading, and the buffer is not restored: losing a few seconds is
      // preferable to retrying forever.
      debugPrint('⚠️ [ReadingStats] flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  // ─── Reading (the dashboard) ───────────────────────────────────────────────

  /// Every recorded day, oldest first.
  ///
  /// `async*` so the Isar handle is awaited before it is touched. The dashboard
  /// mounts this on the first frame, and `FileManagerService().isar` is a
  /// `late` field: reading it before `init()` completes throws instead of
  /// returning null, which is the trap that once made the library summary card
  /// throw on a cold start.
  Stream<List<ReadingDay>> watchDays() async* {
    final fileManager = FileManagerService();
    if (!fileManager.isInitialized) await fileManager.init();
    yield* fileManager.isar.readingDays.where().sortByDateKey().watch(
      fireImmediately: true,
    );
  }

  Future<List<ReadingDay>> daysInRange(DateTime from, DateTime to) async {
    final fileManager = FileManagerService();
    if (!fileManager.isInitialized) await fileManager.init();
    return fileManager.isar.readingDays
        .filter()
        .dateKeyGreaterThan(dateKeyOf(from), include: true)
        .dateKeyLessThan(dateKeyOf(to), include: true)
        .sortByDateKey()
        .findAll();
  }

  Future<int> focusSecondsOn(DateTime date) async {
    final fileManager = FileManagerService();
    if (!fileManager.isInitialized) await fileManager.init();
    final day = await fileManager.isar.readingDays
        .filter()
        .dateKeyEqualTo(dateKeyOf(date))
        .findFirst();
    return day?.focusSeconds ?? 0;
  }

  /// Consecutive qualifying days ending today (or yesterday, so a streak is
  /// not shown as broken before the day is over). A day qualifies at
  /// [streakMinimumSeconds] focused seconds.
  Future<int> currentStreak({DateTime? at}) async {
    final today = startOfDay(at ?? DateTime.now());
    final todaySeconds = await focusSecondsOn(today);

    var cursor = todaySeconds >= streakMinimumSeconds
        ? today
        : today.subtract(const Duration(days: 1));
    if (todaySeconds < streakMinimumSeconds &&
        await focusSecondsOn(cursor) < streakMinimumSeconds) {
      return 0;
    }

    var streak = 0;
    // Bounded so a corrupted store cannot spin here forever.
    for (var i = 0; i < 3650; i++) {
      if (await focusSecondsOn(cursor) < streakMinimumSeconds) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ─── Derived figures ───────────────────────────────────────────────────────

  static int pointsForSeconds(int seconds) => seconds ~/ secondsPerPoint;

  /// Focus points over the days that already happened in [period] plus today.
  Future<int> pointsInPeriod(StatsPeriod period, {DateTime? at}) async {
    final days = await daysInRange(
      _rangeStart(period, at ?? DateTime.now()),
      at ?? DateTime.now(),
    );
    final seconds = days.fold<int>(0, (sum, d) => sum + d.focusSeconds);
    return pointsForSeconds(seconds);
  }

  /// Mean focused seconds per day that has any reading, over the period. Days
  /// with no reading are excluded rather than counted as zero: averaging over a
  /// whole week would report a sad number for someone who reads on three days
  /// and simply did not open a file on the other four.
  Future<int> averageSecondsPerActiveDay(
    StatsPeriod period, {
    DateTime? at,
  }) async {
    final days = await daysInRange(
      _rangeStart(period, at ?? DateTime.now()),
      at ?? DateTime.now(),
    );
    final active = days.where((d) => d.focusSeconds > 0).toList();
    if (active.isEmpty) return 0;
    final total = active.fold<int>(0, (sum, d) => sum + d.focusSeconds);
    return total ~/ active.length;
  }

  /// The seven local days ending today, oldest first — the shape the streak
  /// strip needs, with gaps as null days rather than missing entries.
  List<DateTime> lastSevenDays({DateTime? at}) {
    final today = startOfDay(at ?? DateTime.now());
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

  static DateTime _rangeStart(StatsPeriod period, DateTime now) {
    final today = startOfDay(now);
    switch (period) {
      case StatsPeriod.week:
        return today.subtract(const Duration(days: 6));
      case StatsPeriod.month:
        return today.subtract(const Duration(days: 29));
    }
  }
}

/// Which window the reading statistics are shown over.
enum StatsPeriod { week, month }

extension StatsPeriodLabel on StatsPeriod {
  String get label => switch (this) {
    StatsPeriod.week => 'هذا الأسبوع',
    StatsPeriod.month => 'هذا الشهر',
  };
}
