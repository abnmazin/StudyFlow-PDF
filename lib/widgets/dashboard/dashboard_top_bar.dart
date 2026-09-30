import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/isar_models.dart';
import '../../providers/app_state.dart';
import '../../services/reading_stats_service.dart';
import 'dashboard_notifications.dart';
import 'dashboard_palette.dart';
import 'dashboard_search.dart';

/// The dashboard's navbar: greeting on the reading edge, tools on the far side,
/// 80px tall, pinned.
///
/// Laid out as a sliver rather than a `Column` so it can stay put while the page
/// scrolls. The design calls for a sticky bar with a 1px slate-800 rule under it
/// and the page's own background behind it, which is what `pinned: true` with a
/// fixed `maxExtent`/`minExtent` gives; a `SliverAppBar` would also work but
/// brings toolbar insets and a flexible height this design does not use.
///
/// The three tools keep the order the design lists them in — search, bell, then
/// today's focus — so the row reads the same way the mock does.
class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    required this.isDarkMode,
    required this.isWide,
    required this.contentWidth,
    this.bellKey,
  });

  final bool isDarkMode;
  final bool isWide;

  /// The page's content width after its 32px padding, passed on so the search
  /// and bell panels can size themselves against the window.
  final double contentWidth;

  /// Forwarded to the bell. The page owns it because the page is the only widget
  /// that can see both the bell and the scroll notifications it needs to close on.
  final GlobalKey<NotificationBellState>? bellKey;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final user = app.currentUser;

    // Clipped so the blur cannot bleed past the bar, and translucent rather than
    // opaque: content scrolling underneath stays readable through it instead of
    // being hidden outright. A pinned sliver does let following content pass
    // behind it, which is what makes the blur worth its cost here.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: kDashboardNavBarHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: kDashboardPagePadding,
          ),
          decoration: BoxDecoration(
            color: DashboardColors.background.withValues(alpha: 0.85),
            border: const Border(
              bottom: BorderSide(color: DashboardColors.divider),
            ),
          ),
          child: Row(
            children: [
              // The greeting sits on the reading edge, which in RTL is the start,
              // so it needs no alignment of its own: the row's first child is
              // already the right-hand one.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => _Greeting(
                    user: user,
                    // Narrow windows get the name and drop the academic line
                    // rather than ellipsing both into unreadable stubs.
                    showSubtitle: constraints.maxWidth > 320,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: DashboardSearch(
                        isWide: isWide,
                        contentWidth: contentWidth,
                      ),
                    ),
                    const SizedBox(width: 24),
                    NotificationBell(
                      bellKey: bellKey,
                      isDarkMode: isDarkMode,
                      canPublish:
                          (user?.isLecturer ?? false) ||
                          (user?.isAdmin ?? false),
                      authorName: user?.displayName ?? 'User',
                      userRole: user?.role ?? 'student',
                      contentWidth: contentWidth,
                      isWide: isWide,
                    ),
                    const SizedBox(width: 24),
                    const _TodayFocusChip(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user, required this.showSubtitle});

  final AppUser? user;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _greetingFor(user),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: DashboardColors.title,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (showSubtitle) ...[
          const SizedBox(height: 4),
          Text(
            _academicLineOf(user),
            style: const TextStyle(
              fontSize: 14,
              color: DashboardColors.subtitle,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// Today's minutes, coloured by the streak's own scale so the navbar and the
/// streak card cannot disagree about how strong a day is.
class _TodayFocusChip extends StatefulWidget {
  const _TodayFocusChip();

  @override
  State<_TodayFocusChip> createState() => _TodayFocusChipState();
}

class _TodayFocusChipState extends State<_TodayFocusChip> {
  // Held for the chip's lifetime: `watchDays` is an `async*` generator, so
  // calling it from `build` would resubscribe on every frame.
  late final Stream<List<ReadingDay>> _days = ReadingStatsService().watchDays();

  @override
  Widget build(BuildContext context) {
    return Container(
      // The brief's 36px pill.
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: DashboardColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: DashboardColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.clock,
            size: 16,
            color: DashboardColors.accent,
          ),
          const SizedBox(width: 6),
          StreamBuilder<List<ReadingDay>>(
            stream: _days,
            builder: (context, snapshot) {
              final minutes = _todayMinutes(snapshot.data);
              return Text(
                formatClock(minutes),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _minutesColor(minutes),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static int _todayMinutes(List<ReadingDay>? days) {
    if (days == null) return 0;
    final todayKey = ReadingStatsService.dateKeyOf(DateTime.now());
    for (final day in days) {
      if (day.dateKey == todayKey) return day.focusSeconds ~/ 60;
    }
    return 0;
  }

  static Color _minutesColor(int minutes) {
    if (minutes >= 60) return DashboardColors.success;
    if (minutes >= 15) return DashboardColors.streak;
    return DashboardColors.title;
  }
}

/// Shown when the Firestore document has no enrolment data yet. The app is
/// built for a single college, so these are the real values rather than
/// placeholders; once `college`/`department`/`stage` are written to the user
/// document the per-user values take over.
const _fallbackCollege = 'الكلية التقنية الهندسية';
const _fallbackDepartment = 'تقنيات الهندسة الكهربائية';
const _fallbackStage = 'المرحلة الرابعة';

String _displayNameOf(AppUser? user) {
  final display = user?.displayName.trim() ?? '';
  if (display.isNotEmpty) return display;
  final username = user?.username.trim() ?? '';
  if (username.isNotEmpty) return username;
  return 'زائر';
}

String _greetingFor(AppUser? user) => 'مرحباً بك، ${_displayNameOf(user)} 👋';

/// College · department · stage as one line, used as the greeting's subtitle.
String _academicLineOf(AppUser? user) {
  String pick(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  return [
    pick(user?.college, _fallbackCollege),
    pick(user?.department, _fallbackDepartment),
    pick(user?.stage, _fallbackStage),
  ].join('  ·  ');
}
