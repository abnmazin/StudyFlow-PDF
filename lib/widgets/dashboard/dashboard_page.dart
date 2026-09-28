import 'package:flutter/material.dart';

import '../../utils/responsive_utils.dart';
import 'dashboard_notifications.dart';
import 'dashboard_palette.dart';
import 'dashboard_quick_actions.dart';
import 'dashboard_reading_stats.dart';
import 'dashboard_tasks_schedule.dart';
import 'dashboard_top_bar.dart';

/// The redesigned dashboard.
///
/// One scroll view, one pinned navbar, then the sections in the order the design
/// lists them: quick actions, reading statistics, and tasks beside the schedule.
/// The library is not here any more — it is reached from the app's own sidebar —
/// and announcements are behind the navbar's bell.
///
/// The page owns its background rather than relying on the app's `scaffold`
/// colour, because the design pins the dashboard to a dark palette and the app
/// also has a light mode.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  /// Held here rather than built inside `build` because a `GlobalKey` is an
  /// identity: a fresh one on every rebuild would remount the bell, which drops
  /// its Firestore subscription and its unread count mid-scroll.
  final GlobalKey<NotificationBellState> _bellKey =
      GlobalKey<NotificationBellState>();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DashboardColors.background,
      // Measured on the space the dashboard actually gets, not on the window:
      // the sidebar takes 288px of it, and on a 1100px screen that is the
      // difference between two columns that fit and two that do not. One
      // `LayoutBuilder` above the scroll view, because both the pinned navbar and
      // the sections need the same answer and the navbar is built by a delegate
      // that cannot see the sliver's constraints.
      child: LayoutBuilder(
        builder: (context, viewport) {
          final width = viewport.maxWidth;
          final isWide = ResponsiveBreakpoints.isDesktop(width);

          return NotificationListener<ScrollNotification>(
            // Not `ScrollUpdateNotification`: that fires on every pixel of
            // wheel movement, and a panel that closes one frame after a
            // deliberate scroll started is fine, while closing mid-flick is not.
            // `ScrollStart` is the gesture, not the position.
            onNotification: (notification) {
              if (notification is ScrollStartNotification) {
                _bellKey.currentState?.close();
              }
              return false;
            },
            child: Scrollbar(
              // A dashboard this long is read by scrolling, and the default
              // scrollbar on a dark page is a grey slab that sits over the cards.
              // `interactive` because this is a desktop target and the wheel is
              // the input.
              interactive: true,
              child: CustomScrollView(
                slivers: [
                  SliverPersistentHeader(
                    // The header's height comes from its delegate's extents; the
                    // widget itself only carries `pinned` and who builds the bar.
                    pinned: true,
                    delegate: _TopBarDelegate(
                      isDarkMode:
                          Theme.of(context).brightness == Brightness.dark,
                      isWide: isWide,
                      contentWidth: width,
                      bellKey: _bellKey,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(kDashboardPagePadding),
                    sliver: SliverList.list(
                      children: [
                        const DashboardQuickActions(),
                        const SizedBox(height: kDashboardSectionGap),
                        DashboardReadingStats(isWide: isWide),
                        const SizedBox(height: kDashboardSectionGap),
                        DashboardTasksAndSchedule(isWide: isWide),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBarDelegate extends SliverPersistentHeaderDelegate {
  const _TopBarDelegate({
    required this.isDarkMode,
    required this.isWide,
    required this.contentWidth,
    required this.bellKey,
  });

  final bool isDarkMode;
  final bool isWide;
  final double contentWidth;
  final GlobalKey<NotificationBellState> bellKey;

  @override
  double get minExtent => kDashboardNavBarHeight;

  @override
  double get maxExtent => kDashboardNavBarHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DashboardTopBar(
      isDarkMode: isDarkMode,
      isWide: isWide,
      contentWidth: contentWidth,
      bellKey: bellKey,
    );
  }

  @override
  bool shouldRebuild(covariant _TopBarDelegate oldDelegate) {
    // The key is compared by identity, and the page reuses one key for the
    // bar's whole lifetime, so this term only fires if the key genuinely
    // changed — which is what should remount the bell.
    return oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.isWide != isWide ||
        oldDelegate.contentWidth != contentWidth ||
        oldDelegate.bellKey != bellKey;
  }
}
