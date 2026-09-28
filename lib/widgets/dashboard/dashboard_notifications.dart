import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/app_state.dart';
import 'dashboard_palette.dart';

/// The header's notification bell.
///
/// The announcements themselves are not on the dashboard any more; this is the
/// single entry point to them, and the red dot is the only part of that content
/// visible on the page. What is behind the bell is unchanged behaviour: the same
/// role-filtered Firestore stream, the same local hide, the same publisher for
/// lecturers and admins.
///
/// "Unread" is defined against a timestamp the user cannot see or edit: the last
/// moment the panel was opened. That is honest about what it is — an
/// announcement is unread because the user has not looked since it arrived —
/// and unlike a per-announcement read flag it needs no schema change to a
/// collection the app does not own the shape of.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.isDarkMode,
    required this.canPublish,
    required this.authorName,
    required this.userRole,
    required this.contentWidth,
    required this.isWide,
    this.bellKey,
  });

  final bool isDarkMode;
  final bool canPublish;
  final String authorName;
  final String userRole;

  /// The dashboard's content width, used to size the panel to the stat cards.
  final double contentWidth;
  final bool isWide;

  /// Held by the page so it can close the panel on scroll. A scroll notification
  /// bubbles up from the scroll view, and the bell is a sibling of that view
  /// rather than an ancestor of it, so the page is the only thing that sees both
  /// and the only place the two can be connected.
  final GlobalKey<NotificationBellState>? bellKey;

  @override
  NotificationBellState createState() => NotificationBellState();
}

/// Public because the page holds a [GlobalKey] to it. The state itself stays
/// internal in every other way: nothing outside the bell constructs one.
class NotificationBellState extends State<NotificationBell> {
  static const String _lastSeenKey = 'dashboard_last_seen_announcement_ms';

  /// Ties the bell and its panel into one tap area.
  static const String _tapGroup = 'dashboard-notifications';

  /// The bell's own box, to find which side of the window it is on.
  final GlobalKey _bellKey = GlobalKey();

  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// The panel, not the bell: the panel is what the page hands to the shared
  /// "close everything" signal, and the bell only closes when the panel is open.
  final GlobalKey _panelKey = GlobalKey();

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  int _unread = 0;
  int? _lastSeenMs;

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
    _listen();
  }

  @override
  void didUpdateWidget(NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The signed-in role decides which announcements are visible, so a role
    // change (or a sign-in that happened after mount) needs a new subscription.
    if (oldWidget.userRole != widget.userRole) {
      _subscription?.cancel();
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _listen() {
    final app = context.read<AppProvider>();
    _subscription = app.syncService
        .watchAnnouncements(app.currentUser?.role ?? 'student')
        .listen(
          _onAnnouncements,
          onError: (Object e) {
            // A failed read leaves the dot empty rather than guessing.
            debugPrint('🔔 [Notifications] read failed: $e');
          },
        );
  }

  void _onAnnouncements(List<Map<String, dynamic>> announcements) {
    final lastSeen = _lastSeenMs;
    final unread = lastSeen == null
        ? 0
        : announcements.where((a) => _publishedMs(a) > lastSeen).length;
    if (!mounted || unread == _unread) return;
    setState(() => _unread = unread);
  }

  int _publishedMs(Map<String, dynamic> announcement) {
    final value = announcement['createdAt'];
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    return 0;
  }

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _lastSeenMs = prefs.getInt(_lastSeenKey));
  }

  /// The panel's own "mark all read", reachable without opening the bell.
  ///
  /// Writes the same timestamp as opening the panel does. The distinction is
  /// worth being honest about: this records that the user has looked, it does
  /// not track per-announcement read state, which the Firestore collection has
  /// no field for.
  Future<void> markAllRead() async {
    await _markSeen();
  }

  Future<void> _markSeen() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!mounted) return;
    setState(() {
      _lastSeenMs = now;
      _unread = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenKey, now);
  }

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _markSeen();
      _portal.show();
    }
  }

  /// The page calls this on scroll, through the panel's key.
  void close() {
    if (_portal.isShowing) _portal.hide();
  }

  /// The brief's panel: 320 wide, never taller than 350.
  static const double panelWidth = 320;
  static const double _maxPanelHeight = 350;

  /// How the panel should be placed, measured from the bell's real box.
  ///
  /// A fixed anchor or a fixed width does not work here: the bell's position
  /// depends on the navbar's content and the sidebar. The panel therefore opens
  /// towards whichever side has more room, and is never wider or taller than
  /// that room, so it cannot run past the window edge.
  ///
  /// Deliberately a pure function of the current frame rather than stored state:
  /// it is read from `build`, and a `setState` from inside a build is an error.
  /// The overlay child closes over the result of the last build, which is the
  /// frame the panel was opened on.
  ({bool toRight, double width, double height}) _geometry() {
    final screen = MediaQuery.sizeOf(context);
    const margin = 12.0;
    const gap = 12.0;

    final box = _bellKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return (
        toRight: true,
        width: panelWidth.clamp(0.0, screen.width - 2 * margin),
        height: (screen.height - 2 * margin).clamp(0.0, _maxPanelHeight),
      );
    }

    final rect = box.localToGlobal(Offset.zero) & box.size;
    final roomToRight = screen.width - margin - rect.left;
    final roomToLeft = rect.right - margin;
    final toRight = roomToRight >= roomToLeft;
    final room = toRight ? roomToRight : roomToLeft;
    // Downward, not centred on the bell: the panel is a tall list that grows
    // from just under the navbar, and only the space below the bell limits it.
    final below = screen.height - margin - rect.bottom - gap;

    return (
      toRight: toRight,
      width: (panelWidth < room ? panelWidth : room).clamp(
        0.0,
        screen.width - 2 * margin,
      ),
      height: below < _maxPanelHeight ? below : _maxPanelHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry();

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        // Matching the same physical edge on both sides keeps the panel inside
        // the window: it grows towards whichever side the bell has room on.
        targetAnchor: geometry.toRight ? Alignment.topLeft : Alignment.topRight,
        followerAnchor: geometry.toRight
            ? Alignment.topLeft
            : Alignment.topRight,
        offset: const Offset(0, 12),
        // The Overlay lays every entry out tight to the whole window
        // (`BoxConstraints.tight(size)`), and a follower hands those tight
        // constraints straight to its child, so a `maxWidth` below could never
        // shrink anything — the panel came out full-screen. `Align` is what
        // loosens them: it fills the window itself, so the anchors above still
        // land the panel on the bell, and its empty half is not hit-tested, so a
        // tap outside the panel still reaches the bell's `TapRegion`.
        child: Align(
          alignment: geometry.toRight ? Alignment.topLeft : Alignment.topRight,
          child: TapRegion(
            // The panel is in the Overlay, not a descendant of the bell's
            // `TapRegion` below, so without a shared group a tap on the composer
            // or a list row counts as "outside" and dismisses the panel on
            // pointer-down — before the control under the finger ever sees it.
            // It wraps the panel only, not the full-window `Align` around it.
            groupId: _tapGroup,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // Never wider or taller than the room measured beside the bell.
                maxWidth: geometry.width,
                maxHeight: geometry.height,
              ),
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: DashboardColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DashboardColors.border),
                    boxShadow: DashboardColors.panelShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: NotificationPanel(
                      key: _panelKey,
                      isDarkMode: widget.isDarkMode,
                      canPublish: widget.canPublish,
                      authorName: widget.authorName,
                      userRole: widget.userRole,
                      onMarkAllRead: markAllRead,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _portal.hide(),
          child: Tooltip(
            message: 'الإشعارات',
            child: InkWell(
              key: _bellKey,
              onTap: _toggle,
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DashboardColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: DashboardColors.border),
                    ),
                    child: const Icon(
                      LucideIcons.bell,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  if (_unread > 0)
                    PositionedDirectional(
                      // The brief's -4/-4 with a 2px ring in the navbar's own
                      // colour, which is what makes the badge look cut out of the
                      // circle instead of stuck on top of it.
                      top: -4,
                      end: -4,
                      child: _UnreadBadge(count: _unread),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bell's unread marker: 18×18, red, white bold 10px, ringed in the navbar
/// background so it reads as a cutout.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        shape: BoxShape.circle,
        border: Border.all(color: DashboardColors.background, width: 2),
      ),
      child: Text(
        // Two digits fit; anything past that is a dot, not a number to read.
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// Heading style used inside the panel, matching the dashboard's other
/// section titles. The dashboard palette has its own `DashboardSectionTitle`,
/// but the panel keeps the viewer's existing light/dark handling rather than
/// hard-wiring the dark-only dashboard palette.
Widget _panelHeading(String title, bool isDarkMode, {double fontSize = 18}) {
  return Text(
    title,
    style: TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Announcement sender and list — moved here verbatim from the dashboard's
// announcements section. Behaviour is untouched; only the entry point moved from
// a panel on the page to the bell's dropdown.
// ─────────────────────────────────────────────────────────────────────────────
class _AnnouncementSender extends StatefulWidget {
  final bool isDarkMode;
  final String authorName;
  final String userRole;

  /// Closes the dialog this form now lives in once the announcement is out.
  final VoidCallback? onPublished;

  const _AnnouncementSender({
    required this.isDarkMode,
    required this.authorName,
    required this.userRole,
    this.onPublished,
  });

  @override
  State<_AnnouncementSender> createState() => _AnnouncementSenderState();
}

class _AnnouncementSenderState extends State<_AnnouncementSender> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  String _selectedType = 'info';
  String _selectedAudience = 'all';
  bool _isSending = false;

  bool get _isDeveloper =>
      widget.userRole == 'developer' || widget.userRole == 'admin';
  bool get _isLecturer => widget.userRole == 'lecturer' || _isDeveloper;

  @override
  void initState() {
    super.initState();
    if (_isLecturer) {
      _selectedAudience = 'student';
    } else if (!_isDeveloper) {
      _selectedAudience = 'student_developer';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _isSending = true);
    try {
      await context.read<AppProvider>().syncService.publishAnnouncement(
        title: title,
        body: body,
        type: _selectedType,
        authorName: widget.authorName,
        targetAudience: _isDeveloper
            ? _selectedAudience
            : (_isLecturer ? 'student' : 'student_developer'),
      );
      _titleCtrl.clear();
      _bodyCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم نشر الإشعار بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onPublished?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final panelColor = isDarkMode
        ? const Color(0xFF312E81).withValues(alpha: 0.2)
        : const Color(0xFFEEF2FF);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              hintText: 'عنوان الإشعار...',
              filled: true,
              fillColor: isDarkMode ? Colors.black26 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'محتوى الإشعار التفصيلي...',
              filled: true,
              fillColor: isDarkMode ? Colors.black26 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            children: [
              ChoiceChip(
                label: const Text('تنبيه 🟡'),
                selected: _selectedType == 'warning',
                onSelected: (_) => setState(() => _selectedType = 'warning'),
              ),
              ChoiceChip(
                label: const Text('معلومة 🔵'),
                selected: _selectedType == 'info',
                onSelected: (_) => setState(() => _selectedType = 'info'),
              ),
              ChoiceChip(
                label: const Text('تحديث 🟢'),
                selected: _selectedType == 'update',
                onSelected: (_) => setState(() => _selectedType = 'update'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isDeveloper)
            Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('الكل 🌍'),
                  selected: _selectedAudience == 'all',
                  onSelected: (_) => setState(() => _selectedAudience = 'all'),
                ),
                ChoiceChip(
                  label: const Text('الطلاب 👨‍🎓'),
                  selected: _selectedAudience == 'student',
                  onSelected: (_) =>
                      setState(() => _selectedAudience = 'student'),
                ),
                ChoiceChip(
                  label: const Text('الأساتذة 👨‍🏫'),
                  selected: _selectedAudience == 'lecturer',
                  onSelected: (_) =>
                      setState(() => _selectedAudience = 'lecturer'),
                ),
                ChoiceChip(
                  label: const Text('المطور 🛠️'),
                  selected: _selectedAudience == 'developer',
                  onSelected: (_) =>
                      setState(() => _selectedAudience = 'developer'),
                ),
              ],
            )
          else if (_isLecturer)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Text(
                'خيارات المحاضر: سيتم إرسال هذا الإشعار للطلاب فقط',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Text(
                'سيتم إرسال هذا الإشعار لقناة: الطلاب + المبرمج',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : _publish,
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 18),
              label: Text(
                _isDeveloper && _selectedAudience == 'all'
                    ? 'نشر الإشعار للجميع'
                    : (_isLecturer
                          ? 'إرسال إشعار للطلاب فقط'
                          : (_isDeveloper
                                ? 'نشر الإشعار للفئة المحددة'
                                : 'إرسال إشعار (طلاب + مبرمج)')),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4338CA),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 320×350 panel body: a header, a scrollable list of tiles, and a sticky
/// "mark all read" footer.
///
/// The publish form is deliberately not in here. It is a full column of fields
/// that needs roughly 400px of height, and this panel is capped at 350: keeping
/// it inline meant the panel either overflowed or grew past the design. It is a
/// dialog now, opened from the header, so the panel holds only what the brief
/// asks it to hold.
class NotificationPanel extends StatelessWidget {
  const NotificationPanel({
    super.key,
    required this.isDarkMode,
    required this.canPublish,
    required this.authorName,
    required this.userRole,
    this.onMarkAllRead,
  });

  final bool isDarkMode;
  final bool canPublish;
  final String authorName;
  final String userRole;

  /// Supplied by the bell. Null in a bare pump, where there is no bell to
  /// re-stamp.
  final Future<void> Function()? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _panelHeader(context),
        // `Flexible`, not `Expanded`: the caller caps the panel at 350, and a
        // tight `Expanded` would make every panel exactly 350 tall whatever it
        // holds. Flexible lets the list take what it needs, and the footer stays
        // pinned below it either way.
        Flexible(child: _buildAnnouncementsList(isDarkMode)),
        _panelFooter(context),
      ],
    );
  }

  Widget _panelHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          const Icon(LucideIcons.bell, size: 18, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(child: _panelHeading('الإشعارات', isDarkMode, fontSize: 15)),
          if (canPublish)
            IconButton(
              onPressed: () => _openPublisher(context),
              icon: const Icon(LucideIcons.send, size: 16),
              color: DashboardColors.accent,
              tooltip: 'نشر إشعار',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _panelFooter(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DashboardColors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: TextButton.icon(
          onPressed: onMarkAllRead == null
              ? null
              : () {
                  onMarkAllRead!();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('تم تعليم كل الإشعارات كمقروءة'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                },
          icon: const Icon(LucideIcons.checkCheck, size: 16),
          label: const Text('تعليم الكل كمقروء'),
          style: TextButton.styleFrom(
            foregroundColor: DashboardColors.subtitle,
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }

  void _openPublisher(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: DashboardColors.surface,
        insetPadding: const EdgeInsets.all(32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          child: _AnnouncementSender(
            isDarkMode: isDarkMode,
            authorName: authorName,
            userRole: userRole,
            onPublished: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }
}

Widget _buildAnnouncementsList(bool isDarkMode) {
  return Consumer<AppProvider>(
    builder: (context, app, _) {
      final currentUserRole = app.currentUser?.role ?? 'student';

      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: app.syncService.watchAnnouncements(currentUserRole),
        builder: (context, snapshot) {
          // 🔥 Smart Filtering: Exclude announcements hidden by the user locally
          final announcements = (snapshot.data ?? []).where((ann) {
            final docId = ann['id']?.toString() ?? ann.hashCode.toString();
            return !app.isAnnouncementHidden(docId);
          }).toList();

          if (snapshot.connectionState == ConnectionState.waiting &&
              announcements.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          if (announcements.isEmpty) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                'لا توجد إشعارات حالياً',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                  fontSize: 13,
                ),
              ),
            );
          }

          return ListView.builder(
            // Shrink-wrapped, not a fixed height: the panel is capped at 350
            // by the caller's `ConstrainedBox` and grows to its content below
            // that, so one announcement does not leave a tall empty box and a
            // long list scrolls inside the panel instead of past its footer.
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final ann = announcements[index];
              final type = ann['type'] as String? ?? 'info';
              final color = type == 'warning'
                  ? Colors.amber
                  : type == 'update'
                  ? Colors.green
                  : Colors.blue;
              final icon = type == 'warning'
                  ? LucideIcons.alertTriangle
                  : type == 'update'
                  ? LucideIcons.refreshCw
                  : LucideIcons.info;

              final docId = ann['id']?.toString() ?? ann.hashCode.toString();
              final authorName = (ann['authorName'] as String? ?? '').trim();

              return Dismissible(
                key: Key(docId),
                direction: DismissDirection.horizontal,
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(
                    LucideIcons.trash2,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                secondaryBackground: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(
                    LucideIcons.trash2,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                onDismissed: (direction) {
                  // 🔥 Smart Logic: Admin deletes globally, Student hides locally
                  if (currentUserRole == 'developer' ||
                      currentUserRole == 'lecturer') {
                    app.syncService.deleteAnnouncement(docId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حذف الإشعار نهائياً من النظام 🗑️'),
                      ),
                    );
                  } else {
                    app.hideAnnouncementLocally(docId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم إخفاء الإشعار من شاشتك 👁️‍🗨️'),
                      ),
                    );
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDarkMode
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 16,
                          color: isDarkMode ? color[400] : color[600],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ann['title'] as String? ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if ((ann['targetAudience'] as String? ??
                                        'all') !=
                                    'all') ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ann['targetAudience'] == 'student'
                                          ? Colors.blue.withValues(alpha: 0.1)
                                          : ann['targetAudience'] == 'lecturer'
                                          ? Colors.purple.withValues(alpha: 0.1)
                                          : ann['targetAudience'] ==
                                                'student_developer'
                                          ? Colors.teal.withValues(alpha: 0.1)
                                          : Colors.red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color:
                                            ann['targetAudience'] == 'student'
                                            ? Colors.blue.withValues(alpha: 0.3)
                                            : ann['targetAudience'] ==
                                                  'lecturer'
                                            ? Colors.purple.withValues(
                                                alpha: 0.3,
                                              )
                                            : ann['targetAudience'] ==
                                                  'student_developer'
                                            ? Colors.teal.withValues(alpha: 0.3)
                                            : Colors.red.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      ann['targetAudience'] == 'student'
                                          ? 'للطلاب'
                                          : ann['targetAudience'] == 'lecturer'
                                          ? 'للأساتذة'
                                          : ann['targetAudience'] ==
                                                'student_developer'
                                          ? 'للطلاب+المبرمج'
                                          : 'للإدارة',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            ann['targetAudience'] == 'student'
                                            ? Colors.blue
                                            : ann['targetAudience'] ==
                                                  'lecturer'
                                            ? Colors.purple
                                            : ann['targetAudience'] ==
                                                  'student_developer'
                                            ? Colors.teal
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if ((ann['body'] as String? ?? '').isNotEmpty)
                              Text(
                                ann['body'] as String,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDarkMode
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (authorName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'المرسل: $authorName',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}
