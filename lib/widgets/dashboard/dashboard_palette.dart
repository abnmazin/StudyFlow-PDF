import 'package:flutter/material.dart';

/// The app's dark palette.
///
/// The sidebar's colours are the primary ones: the slate background, the
/// slate-800 panels and the blue accents below are the left sidebar's own
/// colours, promoted here so the dashboard, its panels and the rest of the app
/// are painted from one place instead of each carrying a private copy. The
/// dashboard stays dark-only — it is a dark surface in a window that is
/// otherwise themed by the app, and the reading figures sit better on a single,
/// unchanging background than on one that flips with the app theme.
///
/// Values are the sidebar's: slate-900 page background, slate-800 card surface,
/// slate-700 borders, slate-100 headings, slate-400 secondary text.
class DashboardColors {
  const DashboardColors._();

  /// Page background behind the cards, and the sidebar's own fill, slate-900.
  static const background = Color(0xFF0F172A);

  /// Card and panel surface. Also the sidebar's control and input fill,
  /// slate-800.
  static const surface = Color(0xFF1E293B);

  /// Card and panel outline, slate-700.
  static const border = Color(0xFF334155);

  /// Hairlines and the navbar's bottom rule, slate-800.
  static const divider = Color(0xFF1E293B);

  /// The sidebar's 1px rules: white at 10%.
  static const separator = Color(0x1AFFFFFF);

  /// Hover and pressed fill, blue-900. The sidebar's folder rows use it, and
  /// the dashboard's tiles and rows follow so a hover is one colour app-wide.
  static const hover = Color(0xFF1E3A8A);

  /// The drop-target wash on the sidebar's PDF rows, blue-500 at 13%.
  static const hoverWash = Color(0x223B82F6);

  /// Headings and figures, slate-100.
  static const title = Color(0xFFF1F5F9);

  /// Secondary copy, slate-400.
  static const subtitle = Color(0xFF94A3B8);

  /// The first quick-action tile and the drop-target outline, blue-500.
  static const accent = Color(0xFF3B82F6);

  /// Icons and active labels, blue-400.
  static const accentSoft = Color(0xFF60A5FA);

  /// The label of the entry selected in the sidebar tree, blue-200.
  static const selectedText = Color(0xFFBFDBFE);

  /// The label of the entry open in the second pane, slate-300.
  static const secondaryText = Color(0xFFCBD5E1);

  /// Filled "has reading" marker in the streak strip.
  static const streak = Color(0xFFF59E0B);

  static const success = Color(0xFF22C55E);

  /// Standard card outline used across the dashboard.
  static BoxDecoration card({double radius = 16, Color? fill}) {
    return BoxDecoration(
      color: fill ?? surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
    );
  }

  /// The soft blue lift the dropdowns carry. Blue rather than black because the
  /// panels float over near-black cards: a black shadow at this opacity is
  /// invisible against `#151B2B`, and a visible edge is what tells the reader the
  /// panel is above the page rather than part of it.
  static const panelShadow = <BoxShadow>[
    BoxShadow(color: Color(0x3D3B82F6), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// The brief's vertical rhythm: 32px page padding, 40px between sections.
const double kDashboardPagePadding = 32;
const double kDashboardSectionGap = 40;

/// The reading-stat card height, and the navbar's own height. Stated once each
/// because both are contracts rather than preferences: the four cards must be as
/// tall as the streak card that holds a 130px strip, and the navbar is measured
/// against the height the design calls for.
///
/// The navbar height is read by three bands that share one line in the shell
/// (`main.dart:584` puts the sidebar beside the viewer, and the dashboard replaces
/// the viewer): the dashboard's pinned header, the sidebar's header
/// (`sidebar_w.dart`) and the viewer toolbar (`viewer_toolbar.dart`). They read
/// this constant rather than each carrying a `64`, so they cannot drift apart —
/// which is exactly what happened when the sidebar's literal and the dashboard's
/// differed by 16px.
const double kStatCardHeight = 130;
const double kDashboardNavBarHeight = 64;

/// The gap between two cards of the reading-stat grid. Named rather than written
/// twice because the row that lays the cards out and [statCardWidth], which
/// divides the same content width into columns, must subtract the same number —
/// disagree by one gap and the last card in the row overflows.
const double kStatCardGap = 16;

/// The dashboard section heading: the brief's 18px, and the floor it shrinks to
/// when the card gets too narrow to hold the whole title.
///
/// The floor is a limit on the heading's *identity* rather than on legibility:
/// below it the Noto Naskh face stops carrying the weight that tells a heading
/// apart from the body copy under it, and the section reads as one more line of
/// text. Past the floor the title truncates instead.
const double kSectionTitleFontSize = 18;
const double kSectionTitleMinFontSize = 12;

/// The width of one reading-stat card when [perRow] of them share
/// [contentWidth].
///
/// The row does not divide the width itself: it asks for the same number the
/// cards are built with, so the last card cannot end a gap past the row's edge.
/// Four across on a desktop width, two below it, and never one — a column of
/// four fixed-height cards is half a screen of scrolling for four figures.
double statCardWidth(double contentWidth, {required int perRow}) =>
    (contentWidth - kStatCardGap * (perRow - 1)) / perRow;

/// `2س 45د` / `45د` / `0د`, the format the brief asks for. Read by
/// [formatClock] rather than by hand so the stat cards, the focus badge and the
/// streak all speak the same units.
String formatClock(int seconds) {
  if (seconds < 0) return '0د';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '$minutesد';
  if (minutes == 0) return '$hoursس';
  return '$hoursس $minutesد';
}

/// Arabic short weekday initials, indexed the way [DateTime.weekday] is:
///
/// ```dart
/// const arabicWeekdayInitials = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];
/// arabicWeekdayInitials[date.weekday - 1]
/// ```
const List<String> arabicWeekdayInitials = [
  'ن', // الاثنين
  'ث', // الثلاثاء
  'ر', // الأربعاء
  'خ', // الخميس
  'ج', // الجمعة
  'س', // السبت
  'ح', // الأحد
];

/// Section heading, matching the brief's 18px bold white.
///
/// [trailing] is non-nullable and defaults to an empty box rather than being
/// optional: an optional trailing child needs a null check in the child list,
/// and the language version here predates null-aware elements, so every
/// spelling of that check draws a hint this version cannot satisfy. A
/// zero-width box in a `spaceBetween` row is invisible.
///
/// The heading stays on one line at every width — the card narrows with the
/// window, and a section title is the last thing that should reflow into a
/// second line. The title gives ground instead: it shrinks toward
/// [kSectionTitleMinFontSize] and ellipsizes past that, while the trailing
/// control keeps its own size, because the control is the interactive part and
/// a squashed dropdown is a worse bug than a clipped word.
///
/// The one exception is [shrinkToFit]: a heading that an ancestor
/// `IntrinsicHeight` will measure takes the plain ellipsised path instead,
/// because a heading that measures cannot be measured.
class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle(
    this.text, {
    super.key,
    this.trailing = const SizedBox.shrink(),
    this.shrinkToFit = true,
  });

  final String text;
  final Widget trailing;

  /// Whether the title may measure the room the row gave it and shrink to fit.
  ///
  /// False wherever an ancestor `IntrinsicHeight` asks this heading for its
  /// height without laying it out: `IntrinsicHeight` equalises a row of cards by
  /// measuring the tallest, and a `LayoutBuilder` refuses that question
  /// ("LayoutBuilder does not support returning intrinsic dimensions") — the
  /// pump fails there, and everything below the row fails with it. The two cards
  /// in `DashboardTasksAndSchedule` are that case, and their headings are one
  /// short word each, so the shrink they give up was never reached anyway.
  final bool shrinkToFit;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: kSectionTitleFontSize,
      fontWeight: FontWeight.w700,
      color: DashboardColors.title,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // `Flexible`, not a bare `Text`: a non-flex child of a `Row` is laid
        // out with unbounded width, so the title claims its full intrinsic
        // width and the trailing control ends up outside the card instead of
        // beside the title. `Flexible` hands the title the leftover width and
        // leaves `spaceBetween` to do its job on the wide layouts, where the
        // title is shorter than the space it is given.
        Flexible(
          child: shrinkToFit
              ? _shrinkingTitle(context, style)
              : Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
        ),
        // A fixed gap, because the ellipsis would otherwise end flush against
        // the control, where a clipped word reads as a rendering fault rather
        // than as a truncation.
        const SizedBox(width: 8),
        trailing,
      ],
    );
  }

  /// The title at [kSectionTitleFontSize], scaled down to fit the width the row
  /// gave it and never below [kSectionTitleMinFontSize].
  ///
  /// Measured rather than left to a `FittedBox`: a `FittedBox` scales by whatever
  /// factor is needed, so a long title would shrink past the floor instead of
  /// stopping at it, and it lays its child out unbounded, so `overflow: ellipsis`
  /// would never fire. One `TextPainter` per build, for a heading that builds
  /// when the layout changes, is the cheaper of the two.
  ///
  /// The measurement is what needs a `LayoutBuilder`, and a `LayoutBuilder`
  /// cannot answer an intrinsic-dimension query — which is why this is a method
  /// of its own: [shrinkToFit] lets a caller under an `IntrinsicHeight` take the
  /// plain path and never reach here.
  Widget _shrinkingTitle(BuildContext context, TextStyle style) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        // An unbounded constraint is the answer to "this row is not in a
        // bounded box", not a failure: keep the brief's size rather than
        // divide by infinity.
        final available = constraints.maxWidth;
        final scale = available.isFinite && painter.width > available
            ? (available / painter.width).clamp(
                kSectionTitleMinFontSize / kSectionTitleFontSize,
                1.0,
              )
            : 1.0;
        painter.dispose();

        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: kSectionTitleFontSize * scale),
        );
      },
    );
  }
}
