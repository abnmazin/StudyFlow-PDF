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

/// The quote panel's height, and with it the row's height. 80.
///
/// Sized to the text rather than to a grid: the quotation at [kQuoteFontSize]
/// with a 1.35 leading (≈23px) + a gap (6px) + the author at [kQuoteAuthorFontSize]
/// with a 1.2 leading (≈17px) = 46px of content, and the vertical padding (12 each
/// side) puts it at 70 — so 80 leaves 10px of slack, which is what makes it read
/// as a card with room in it rather than as a box of text.
///
/// The three figure cards derive their height from this one rather than stating
/// a second number: two literals that must agree is how the sidebar header and
/// the dashboard navbar ended up 16px apart.
const double kQuotesPanelHeight = 80;
const double kStatCardHeight = kQuotesPanelHeight;

/// The vertical padding inside the quote panel.
///
/// Half of what the panel had at 190px, because 40px of padding in an 80px card
/// would leave 40 for the text — and a sentence set at [kQuoteFontSize] does not
/// fit in 40 with an author line under it.
const double kQuotesPanelPadding = 12;

/// The quote panel's share of the row's width.
///
/// The three figure cards take what is left. Stated as a share rather than as a
/// pixel width because the panel is the only card here whose content is prose:
/// it needs room to wrap a sentence over two lines, and the figures need a
/// label and a digit. Roughly two fifths for the panel reads as a quote card
/// rather than as a fourth statistic, which is the whole point of the change.
const double kQuotesPanelWidthShare = 0.42;

/// The navbar's own height, in its own constant rather than sharing
/// [kStatCardHeight]'s declaration: the two are unrelated numbers that happen
/// to live near each other, and a reader who sees them declared as one value
/// will eventually change both together.
const double kDashboardNavBarHeight = 64;

/// How long one quotation stays on the panel before the next takes its place,
/// and how long the cross-fade between them runs.
///
/// Long enough to read a two-line quotation at the size it is drawn, and short
/// enough that a reader who looks up again finds a different sentence rather than
/// the same one. The fade is named separately because it is a different job — it
/// is what stops the swap reading as a flicker — but it is a fraction of the hold
/// on purpose: a fade longer than the hold would cut into the next quotation's
/// time and the two would drift into each other.
const Duration kQuoteHold = Duration(seconds: 12);
const Duration kQuoteFadeDuration = Duration(milliseconds: 600);

/// The quotation's size, its author's, and the floor the quotation shrinks to
/// when the card gets too narrow to hold the sentence the admin wrote.
///
/// 14 and 12 rather than 17 and 13: the panel came down from 190 to 80, and at 17
/// a sentence plus its author would need 46px of text inside a card with 24px of
/// content left after the padding — it would have clipped, and the shrink below
/// only measures the sentence, not the author line under it.
///
/// The floor is the same rule as [kSectionTitleFontSize]: a quotation is the
/// one piece of prose on the dashboard, and prose that shrinks past this stops
/// reading as a quotation and starts reading as a caption.
const double kQuoteFontSize = 14;
const double kQuoteMinFontSize = 11;

/// The author line's size, named apart from [kQuoteFontSize] because it is a
/// different job: an attribution is set smaller than what it attributes, and at
/// the same size the two lines read as one block of equal weight.
const double kQuoteAuthorFontSize = 12;

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

/// The figure's size inside a reading-stat card, and its label's.
///
/// 24 rather than 30: the card came down from 190 to 80 with the quote panel, and
/// a 30px digit in an 80px card is nearly half the height of the thing it sits
/// in. At 24 it still reads as the figure — it is the largest type on the card —
/// while leaving room for the label above it.
///
/// Named rather than written inline because the quote panel sets a second pair
/// of sizes at a different scale in the same row, and two sets of literals in
/// one file is how a card's figure ends up larger than the quotation beside it.
const double kStatFigureFontSize = 24;
const double kStatLabelFontSize = 12;

/// The width of one reading-stat card when [perRow] of them share
/// [contentWidth].
///
/// The row does not divide the width itself: it asks for the same number the
/// cards are built with, so the last card in the row cannot end a gap past the
/// row's edge.
///
/// [contentWidth] is the row's whole width *including* the quote panel's share,
/// so this subtracts the panel before dividing — the three figures are what is
/// left of the row, and a fourth of that would be a fourth card nobody drew.
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
