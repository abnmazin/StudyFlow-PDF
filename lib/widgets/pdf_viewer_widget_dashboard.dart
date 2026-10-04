part of 'pdf_viewer_widget_w.dart';

// ─── DASHBOARD COMMAND CENTER ───────────────────────────────────────────────

/// The dashboard entry point, shown whenever no PDF is open.
///
/// The screens themselves moved to `widgets/dashboard/` when the dashboard was
/// redesigned — header with search, bell and today's focus; the services row;
/// tasks beside the schedule; reading statistics last. The library went back to
/// the app's sidebar and announcements are behind the bell, so none of the
/// previous in-page sections have a home here any more.
Widget _buildDashboard(BuildContext context) => const DashboardPage();
