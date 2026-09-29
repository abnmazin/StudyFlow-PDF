import 'package:flutter/material.dart';

import '../../models/isar_models.dart';
import '../../services/reading_stats_service.dart';
import 'dashboard_palette.dart';

/// "إحصائيات ونشاط القراءة" — the section that makes the reading history
/// visible.
///
/// Every figure is computed from [ReadingDay] rows, which the viewer session in
/// `AppProvider` is the only writer of (see `_noteReadingInteraction`). Nothing
/// here is illustrative: when the rows are empty the cards read zero, not a
/// placeholder, because a fake number on a real dashboard is worse than a blank
/// one.
///
/// Layout: a heading with the period selector, then four equal cards. Side by
/// side when [isWide], stacked two-up below that so a narrow window never
/// squeezes a figure to a column of ellipsis.
class DashboardReadingStats extends StatefulWidget {
  const DashboardReadingStats({super.key, required this.isWide, this.days});

  final bool isWide;

  /// Replaces the Isar query. Present only so the height of these fixed-size
  /// cards can be tested without an open database: the cards overflowed by 6px
  /// in a way no unit test could see, because the number that broke it was
  /// rendered, not returned. Production always leaves this null and reads Isar.
  final List<ReadingDay>? days;

  @override
  State<DashboardReadingStats> createState() => _DashboardReadingStatsState();
}

class _DashboardReadingStatsState extends State<DashboardReadingStats> {
  StatsPeriod _period = StatsPeriod.week;

  // `watchDays` is an `async*` generator, so calling it per build would hand
  // `StreamBuilder` a brand new subscription every time and re-run the query on
  // every frame. One stream for the lifetime of this section.
  late final Stream<List<ReadingDay>> _days = _source();

  Stream<List<ReadingDay>> _source() {
    // Read once into a local so the null check promotes it: `widget.days` is a
    // getter and Dart will not promote a field access across a branch.
    final days = widget.days;
    return days != null
        ? Stream.value(days)
        : ReadingStatsService().watchDays();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => StreamBuilder<List<ReadingDay>>(
        stream: _days,
        builder: (context, snapshot) {
          final cardWidth = statCardWidth(
            constraints.maxWidth,
            isWide: widget.isWide,
          );
          final days = snapshot.data ?? const <ReadingDay>[];
          final inPeriod = _daysInPeriod(days);

          final cards = [
            _StatCardData(
              label: 'قراءة اليوم',
              value: formatClock(_sumSeconds(inPeriod, onlyToday: true)),
              icon: Icons.schedule,
              iconColor: DashboardColors.accent,
            ),
            _StatCardData(
              label: 'المتوسط اليومي',
              value: formatClock(_averageSeconds(inPeriod)),
              icon: Icons.timelapse,
              iconColor: DashboardColors.subtitle,
            ),
            _StatCardData(
              label: 'صفحات قُرئت',
              // Period total, not today's: the selector is meant to change what
              // the row reports, and only "قراءة اليوم" is a today figure.
              value: '${_sumPages(inPeriod)}',
              icon: Icons.menu_book,
              iconColor: DashboardColors.success,
            ),
            _StreakCardData(
              label: 'سلسلة الالتزام',
              streak: _streak(days),
              days: ReadingStatsService().lastSevenDays(),
              secondsByDate: {
                for (final day in days) day.dateKey: day.focusSeconds,
              },
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardSectionTitle(
                'إحصائيات ونشاط القراءة',
                trailing: _PeriodSelector(
                  period: _period,
                  onChanged: (p) => setState(() => _period = p),
                ),
              ),
              const SizedBox(height: 20),
              if (widget.isWide)
                // `SizedBox` with the shared card width rather than `Expanded`:
                // the header's notification and search panels are sized from the
                // same function, and `Expanded` would let the two drift apart
                // whenever the gap or the card count changed.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 16),
                        SizedBox(width: cardWidth, child: _buildCard(cards[i])),
                      ],
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _buildCard(cards[i]),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(Object card) {
    return switch (card) {
      _StatCardData data => _StatCard(data: data),
      _StreakCardData data => _StreakCard(data: data),
      _ => const SizedBox.shrink(),
    };
  }

  // ─── Derivation from the stored days ───────────────────────────────────────
  //
  // All of it is pure arithmetic over the rows already in hand, so the figures
  // update on the same stream frame instead of firing four more Isar queries.

  List<ReadingDay> _daysInPeriod(List<ReadingDay> days) {
    final today = ReadingStatsService.startOfDay(DateTime.now());
    final from = switch (_period) {
      StatsPeriod.week => today.subtract(const Duration(days: 6)),
      StatsPeriod.month => today.subtract(const Duration(days: 29)),
    };
    return days.where((d) {
      final date = DateTime.tryParse(d.dateKey);
      if (date == null) return false;
      return !date.isBefore(from) && !date.isAfter(today);
    }).toList();
  }

  int _sumSeconds(List<ReadingDay> days, {bool onlyToday = false}) {
    final todayKey = ReadingStatsService.dateKeyOf(DateTime.now());
    return days
        .where((d) => !onlyToday || d.dateKey == todayKey)
        .fold(0, (sum, d) => sum + d.focusSeconds);
  }

  int _sumPages(List<ReadingDay> days, {bool onlyToday = false}) {
    final todayKey = ReadingStatsService.dateKeyOf(DateTime.now());
    return days
        .where((d) => !onlyToday || d.dateKey == todayKey)
        .fold(0, (sum, d) => sum + d.pagesAdvanced);
  }

  /// Mean over days that have reading, not over the whole period: a reader who
  /// sits down three days a week should see the average of those three days, not
  /// a number deflated by the days they never opened a file.
  int _averageSeconds(List<ReadingDay> days) {
    final active = days.where((d) => d.focusSeconds > 0).toList();
    if (active.isEmpty) return 0;
    return active.fold(0, (sum, d) => sum + d.focusSeconds) ~/ active.length;
  }

  /// Consecutive qualifying days ending today, or yesterday when today has not
  /// reached the threshold yet — a streak should not read as broken at 9am.
  int _streak(List<ReadingDay> days) {
    final byKey = {for (final d in days) d.dateKey: d.focusSeconds};
    int secondsOn(DateTime date) =>
        byKey[ReadingStatsService.dateKeyOf(date)] ?? 0;

    var cursor = DateTime.now();
    final today = ReadingStatsService.startOfDay(cursor);
    if (secondsOn(today) < ReadingStatsService.streakMinimumSeconds) {
      cursor = today.subtract(const Duration(days: 1));
      if (secondsOn(cursor) < ReadingStatsService.streakMinimumSeconds) {
        return 0;
      }
    } else {
      cursor = today;
    }

    var streak = 0;
    for (var i = 0; i < 3650; i++) {
      if (secondsOn(cursor) < ReadingStatsService.streakMinimumSeconds) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

/// Which window the figures cover.
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});

  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      // The brief's 32px, stated as a height rather than left to the button's own
      // metrics: the selector sits in the section heading, and a control there
      // that is taller than the 18px title beside it shifts the whole row.
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: DashboardColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DashboardColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<StatsPeriod>(
          value: period,
          onChanged: (p) {
            if (p != null) onChanged(p);
          },
          isDense: true,
          dropdownColor: DashboardColors.surface,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(
            Icons.expand_more,
            size: 18,
            color: DashboardColors.subtitle,
          ),
          style: const TextStyle(fontSize: 13, color: DashboardColors.title),
          items: [
            for (final p in StatsPeriod.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
        ),
      ),
    );
  }
}

class _StatCardData {
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
}

class _StreakCardData {
  const _StreakCardData({
    required this.label,
    required this.streak,
    required this.days,
    required this.secondsByDate,
  });

  final String label;
  final int streak;
  final List<DateTime> days;
  final Map<String, int> secondsByDate;
}

/// One figure: label, value, icon. Shared by the three scalar cards.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kStatCardHeight,
      padding: const EdgeInsets.all(20),
      decoration: DashboardColors.card(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 16, color: data.iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DashboardColors.subtitle,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              data.value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: DashboardColors.title,
                // The app's global theme sets `height: 1.4` on every
                // `bodyMedium`, and a bare `TextStyle` here would inherit it, so
                // a 26px figure would occupy 36px of the card's 88px instead of
                // 26. A figure is not body copy and does not need the leading;
                // stating it is what keeps these cards inside their fixed height.
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Streak length plus the seven-day strip. The strip is the honest part: it
/// shows which of the last seven days actually cleared the threshold, so a long
/// streak cannot hide a gap in the middle.
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.data});

  final _StreakCardData data;

  /// The figure's style, shared by the number and its unit so the two are one
  /// line of text rather than two labels side by side.
  ///
  /// `height: 1.0` is doing the same job here as in `_StatCard`: without it both
  /// runs inherit the theme's 1.4 leading, and the three rows of this card stop
  /// fitting inside its fixed height.
  static const _figureStyle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: DashboardColors.title,
    height: 1.0,
  );

  /// The space between the number and its unit.
  static const double _unitGap = 8;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kStatCardHeight,
      padding: const EdgeInsets.all(20),
      decoration: DashboardColors.card(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.local_fire_department,
                size: 16,
                color: DashboardColors.streak,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'سلسلة الالتزام',
                  style: TextStyle(
                    fontSize: 13,
                    color: DashboardColors.subtitle,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              // One baseline for the two runs. The digits and the Arabic word can
              // be drawn by two different fonts, and those two do not share an
              // ascent — centring them instead would leave the number floating.
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${data.streak}',
                  key: const ValueKey('streak-value'),
                  style: _figureStyle,
                ),
                // The gap is a box, not a space written into the string. A space
                // between the two runs is the one character at that seam with no
                // direction of its own, and how wide it reads depends on the font
                // that ends up covering it; eight logical pixels are the same in
                // every font, and are the width the rest of this card already puts
                // between an icon and its label.
                //
                // `Padding` rather than a bare `SizedBox` so the gap is carried by
                // a box that has a child to take a baseline from.
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: _unitGap),
                  child: Text(
                    data.streak == 1 ? 'يوم' : 'أيام',
                    key: const ValueKey('streak-unit'),
                    style: _figureStyle,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // The brief puts the week strip along the bottom of the card, so it
          // sits under the figure rather than beside it.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final day in data.days)
                _StreakDayChip(
                  date: day,
                  seconds:
                      data.secondsByDate[ReadingStatsService.dateKeyOf(day)] ??
                      0,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single day in the streak strip: its Arabic initial over a bar that is
/// filled when the day cleared [ReadingStatsService.streakMinimumSeconds].
class _StreakDayChip extends StatelessWidget {
  const _StreakDayChip({required this.date, required this.seconds});

  final DateTime date;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final qualifies = seconds >= ReadingStatsService.streakMinimumSeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The brief's 20×20 circle, not a 4px bar. A filled disc with a tick for a
        // day that cleared the threshold and an empty ring for one that did not:
        // the strip is read at a glance across seven days, and a hairline under a
        // letter does not survive being that small.
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: qualifies ? DashboardColors.streak : Colors.transparent,
            border: Border.all(
              color: qualifies
                  ? DashboardColors.streak
                  : DashboardColors.border,
              width: 1.5,
            ),
          ),
          child: qualifies
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          arabicWeekdayInitials[date.weekday - 1],
          style: TextStyle(
            fontSize: 10,
            color: qualifies ? DashboardColors.title : DashboardColors.subtitle,
            fontWeight: qualifies ? FontWeight.w700 : FontWeight.w400,
            // One glyph under a 20px circle, so the theme's 1.4 leading is
            // what pushes the strip 4px past the card.
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
