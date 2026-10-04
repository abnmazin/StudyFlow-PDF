import 'package:flutter/material.dart';

import '../../models/dashboard_quote.dart';
import '../../models/isar_models.dart';
import '../../services/reading_stats_service.dart';
import 'dashboard_palette.dart';
import 'dashboard_quotes_card.dart';

/// "إحصائيات ونشاط القراءة" — the section that makes the reading history
/// visible.
///
/// Every figure is computed from [ReadingDay] rows, which the viewer session in
/// `AppProvider` is the only writer of (see `_noteReadingInteraction`). Nothing
/// here is illustrative: when the rows are empty the cards read zero, not a
/// placeholder, because a fake number on a real dashboard is worse than a blank
/// one.
///
/// Layout: a heading with the period selector, then one row holding the three
/// figure cards and the quote panel.
///
/// The panel is the row's *last* child and therefore on the left: the tree runs
/// right-to-left, so the first child is the rightmost. The figures sit beside it
/// and divide what is left of the row, which is less than they used to have — a
/// quotation is prose and a figure is a label and a digit.
///
/// One row rather than two, at every width. That is why [isWide] no longer
/// changes anything here — it is kept as a parameter because the section above
/// still passes it, and a grid that was two-up on a narrow window cannot hold a
/// panel beside it.
class DashboardReadingStats extends StatefulWidget {
  const DashboardReadingStats({
    super.key,
    required this.isWide,
    this.days,
    this.quotes,
  });

  final bool isWide;

  /// Replaces the Isar query. Present only so the height of these fixed-size
  /// cards can be tested without an open database: the cards overflowed by 6px
  /// in a way no unit test could see, because the number that broke it was
  /// rendered, not returned. Production always leaves this null and reads Isar.
  final List<ReadingDay>? days;

  /// Forwarded to the quote panel, which reads `AppProvider.quotes` when this is
  /// null. Exists so this section can be pumped with no Firebase behind it: the
  /// panel is inside this section, and it would otherwise be the one widget in
  /// the dashboard that cannot be tested at all.
  final List<DashboardQuote>? quotes;

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
              // One row: the three figures, then the quote panel.
              //
              // The panel is the *last* child on purpose. The tree runs
              // right-to-left, so the first child is the rightmost and the last
              // is the leftmost — the panel is wanted on the left, beside the
              // section's own left edge, and putting it first would have put it
              // under the section title where the figures used to start.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The figures take what is left of the row after the panel has
                    // had its share. Stated here rather than through
                    // `statCardWidth`'s `perRow` because the row now has a
                    // non-figure member in it, and a helper dividing the row's
                    // whole width would hand the panel's share to the figures and
                    // overflow the row by exactly that much.
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            if (i > 0) const SizedBox(width: kStatCardGap),
                            Expanded(child: _StatCard(data: cards[i])),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: kStatCardGap),
                    // The panel takes `kQuotesPanelWidthShare` of the row, so a
                    // quotation gets the width prose needs and a figure gets what
                    // a label and a digit need — which is less.
                    SizedBox(
                      width: constraints.maxWidth * kQuotesPanelWidthShare,
                      child: DashboardQuotesCard(quotes: widget.quotes),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
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

/// One figure: label, value, icon. Shared by the three scalar cards.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  /// The figure's style, from the palette rather than written here.
  ///
  /// `height: 1.0` is load-bearing: the app's global theme sets `height: 1.4` on
  /// every `bodyMedium`, and a bare `TextStyle` would inherit it, so a 30px figure
  /// would occupy 42px of the card's 176px instead of 30. A figure is not body
  /// copy and does not need the leading; stating it is what keeps these cards
  /// inside their fixed height.
  static const _figureStyle = TextStyle(
    fontSize: kStatFigureFontSize,
    fontWeight: FontWeight.w800,
    color: DashboardColors.title,
    height: 1.0,
  );

  /// The label's style, for the same reason it is named: the quote panel sets a
  /// second label next to this one, and two inline copies of 13px drift.
  static const _labelStyle = TextStyle(
    fontSize: kStatLabelFontSize + 1,
    color: DashboardColors.subtitle,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kStatCardHeight,
      padding: const EdgeInsets.all(10),
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
                  style: _labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(data.value, style: _figureStyle),
          ),
        ],
      ),
    );
  }
}
