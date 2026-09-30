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
/// against the 80px the design calls for.
const double kStatCardHeight = 130;
const double kDashboardNavBarHeight = 64;

/// The width of one of the four reading-stat cards, which is also the width the
/// notification and search panels use.
///
/// Single source of truth on purpose: the panels are anchored in the header and
/// the streak card sits further down the page, and "the same width as the
/// streak card" is only true for as long as both sides compute it the same way.
/// Four across on a wide layout, full width when the cards stack.
double statCardWidth(double contentWidth, {required bool isWide}) {
  if (!isWide) return contentWidth;
  const gap = 16.0;
  return (contentWidth - gap * 3) / 4;
}

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
class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle(
    this.text, {
    super.key,
    this.trailing = const SizedBox.shrink(),
  });

  final String text;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: DashboardColors.title,
          ),
        ),
        trailing,
      ],
    );
  }
}
