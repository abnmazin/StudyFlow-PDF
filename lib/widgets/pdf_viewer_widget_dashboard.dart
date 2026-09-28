part of 'pdf_viewer_widget_w.dart';

// ─── DASHBOARD COMMAND CENTER ───────────────────────────────────────────────

Widget _buildDashboard(BuildContext context) {
  return Selector<
    AppProvider,
    ({bool isDarkMode, int pdfCount, int highlightCount, AppUser? user})
  >(
    selector: (_, app) => (
      isDarkMode: app.isDarkMode,
      pdfCount: app.totalPdfs,
      highlightCount: app.totalHighlights,
      user: app.currentUser,
    ),
    shouldRebuild: (prev, next) =>
        prev.isDarkMode != next.isDarkMode ||
        prev.pdfCount != next.pdfCount ||
        prev.highlightCount != next.highlightCount ||
        prev.user?.uid != next.user?.uid ||
        prev.user?.role != next.user?.role ||
        prev.user?.universityId != next.user?.universityId,
    builder: (context, data, _) => _DashboardWrapper(
      isDarkMode: data.isDarkMode,
      app: context.read<AppProvider>(),
    ),
  );
}

class _DashboardWrapper extends StatefulWidget {
  final bool isDarkMode;
  final AppProvider app;

  const _DashboardWrapper({required this.isDarkMode, required this.app});

  @override
  State<_DashboardWrapper> createState() => _DashboardWrapperState();
}

class _DashboardWrapperState extends State<_DashboardWrapper> {
  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final app = widget.app;

    final rootBg = isDarkMode
        ? const Color(0xFF020617)
        : const Color(0xFFE2E8F0);
    final canvasBg = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final canvasBorder = isDarkMode
        ? const Color(0xFF1E293B)
        : const Color(0xFFCBD5E1);

    return ColoredBox(
      color: rootBg,
      child: SafeArea(
        left: false,
        right: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final padding = width < 600 ? 12.0 : (width < 900 ? 16.0 : 20.0);
            final isWide = ResponsiveBreakpoints.isDesktop(width);

            return Container(
              margin: EdgeInsets.all(padding),
              // Without explicit dimensions the canvas hugs its child on both
              // axes: a `Column` that stacks with `CrossAxisAlignment.start`
              // shrinks to the narrowest child horizontally, and
              // `SingleChildScrollView` sizes itself to its content
              // (single_child_scroll_view.dart: `constraints.constrain(child.size)`),
              // which leaves the dashboard shorter than the window. The parent
              // `Row` in main.dart then centres it vertically on its default
              // `CrossAxisAlignment.center`, producing an empty band above and
              // below. Filling both axes removes the band entirely.
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: canvasBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: canvasBorder.withValues(alpha: 0.5)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroSection(context, app),
                    const SizedBox(height: 32),
                    _buildWorkspaceSection(context, app, isDarkMode, isWide),
                    const SizedBox(height: 32),
                    _buildLibrarySection(context, app, isDarkMode),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Temporary migration function to set up admin's university account.
Future<void> _migrateAdminAccount(BuildContext context) async {
  final app = context.read<AppProvider>();
  final user = app.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('❌ No user logged in'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final firestore = FirebaseFirestore.instance;
  try {
    // 1. Create university document. `merge: true` matters: the cached
    // `stats` counters live on this same document, and a plain `set()` would
    // wipe them every time this button is pressed.
    await firestore
        .collection('universities')
        .doc('southern_technical_university')
        .set({
          'name': 'Southern Technical University',
          'code': 'STU',
          'adminUids': [user.uid],
          'createdAt': FieldValue.serverTimestamp(),
          'isActive': true,
        }, SetOptions(merge: true));

    // 2. Update current user to be admin of this university
    await firestore.collection('users').doc(user.uid).update({
      'universityId': 'southern_technical_university',
      'role': 'admin',
    });

    // ── Optimistic local state update ─────────────────────────────
    if (!context.mounted) return;

    final updatedUser = user.copyWith(
      role: 'admin',
      universityId: 'southern_technical_university',
    );

    app.setCurrentUser(updatedUser);
    await UniversityService().init(updatedUser);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ University created! Welcome to the Cloud Library Hub.',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Migration failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ─── QUICK ACTIONS ───────────────────────────────────────────────────────────

/// The left-hand column. When [isWide] it carries a faint rule on its right
/// edge to separate it from the tasks/notifications column; once the blocks
/// stack the rule would read as a stray border, so it is dropped.
/// Drawing the divider as a border (rather than a `VerticalDivider`) keeps it
/// the full height of the grid without needing an intrinsic height, which the
/// `shrinkWrap` notifications list cannot provide.
Widget _buildQuickActionsSection(
  BuildContext context,
  bool isDarkMode,
  bool isWide,
) {
  return Container(
    padding: isWide ? const EdgeInsets.only(right: 32) : EdgeInsets.zero,
    decoration: BoxDecoration(
      border: Border(
        right: isWide
            ? BorderSide(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              )
            : BorderSide.none,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('إجراءات سريعة', isDarkMode),
        const SizedBox(height: 12),
        _buildQuickActionChips(context, isDarkMode),
      ],
    ),
  );
}

/// Today's tasks sit above notifications on the right, the 2×2 action grid on
/// the left, separated by a hairline border on the grid column. Under RTL the
/// first child of a `Row` paints on the right, so the order below is what puts
/// the grid on the left. The hairline is a border rather than a real divider
/// widget: the announcements list is a `shrinkWrap` `ListView`, which cannot
/// report an intrinsic height for `IntrinsicHeight` to measure.
Widget _buildWorkspaceSection(
  BuildContext context,
  AppProvider app,
  bool isDarkMode,
  bool isWide,
) {
  final right = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildToDoSection(context, isDarkMode),
      const SizedBox(height: 28),
      _SoftDivider(isDarkMode: isDarkMode),
      const SizedBox(height: 28),
      _AnnouncementsSection(
        isDarkMode: isDarkMode,
        canPublish:
            (app.currentUser?.isLecturer ?? false) ||
            (app.currentUser?.isAdmin ?? false),
        authorName: app.currentUser?.displayName ?? 'User',
        userRole: app.currentUser?.role ?? 'student',
      ),
    ],
  );

  final left = _buildQuickActionsSection(context, isDarkMode, isWide);

  if (!isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [right, const SizedBox(height: 32), left],
    );
  }

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 5, child: right),
      const SizedBox(width: 32),
      Expanded(flex: 2, child: left),
    ],
  );
}

/// A faint full-width rule, used to separate stacked blocks without a box.
class _SoftDivider extends StatelessWidget {
  const _SoftDivider({required this.isDarkMode});

  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: isDarkMode
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06),
    );
  }
}

// ─── LIBRARY (CLOUD / PERSONAL FOLDERS) ──────────────────────────────────────

/// Compact one-row stand-in for the full university library: small icons plus
/// the cached totals. Tapping pushes the real manager as a full-screen route,
/// because this card is the only entry point to it.
///
/// `UniversityService` is a singleton that the rest of the app initialises
/// lazily from whichever library widget mounts first, so this card cannot read
/// it during `build`: on a fresh launch it is still uninitialised and
/// `streamStats()` would throw. It therefore initialises the service itself
/// before subscribing, mirroring `CollegeCollectionWidget`.
class UniversityLibrarySummaryCard extends StatefulWidget {
  const UniversityLibrarySummaryCard({
    super.key,
    required this.isDarkMode,
    required this.user,
  });

  final bool isDarkMode;
  final AppUser user;

  @override
  State<UniversityLibrarySummaryCard> createState() =>
      _UniversityLibrarySummaryCardState();
}

class _UniversityLibrarySummaryCardState
    extends State<UniversityLibrarySummaryCard> {
  final UniversityService _service = UniversityService();
  StreamSubscription<UniversityStats>? _statsSub;
  UniversityStats? _stats;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant UniversityLibrarySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_statsSub?.cancel());
    _statsSub = null;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _service.init(widget.user);
      if (!_service.isReady) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      final sub = _service.streamStats().listen(
        (stats) {
          if (mounted) setState(() => _stats = stats);
        },
        onError: (_) {
          if (mounted) setState(() => _failed = true);
        },
      );
      _statsSub = sub;
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    // A missing `stats` map means the counters were never written for this
    // university; a dash is honest there, a zero would not be.
    final stats = _stats;
    final pending = _failed || stats == null || !stats.isPopulated;
    final files = pending ? '—' : '${stats.fileCount}';
    final videos = pending ? '—' : '${stats.videoCount}';
    final folders = pending ? '—' : '${stats.folderCount}';

    void openLibrary() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: isDarkMode
                ? const Color(0xFF0F172A)
                : Colors.white,
            appBar: AppBar(
              title: const Text('المكتبة الجامعية'),
              backgroundColor: isDarkMode
                  ? const Color(0xFF0F172A)
                  : Colors.white,
            ),
            body: UniversityCloudLibraryWidget(
              isDarkMode: isDarkMode,
              user: widget.user,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('المكتبة الجامعية', isDarkMode),
        const SizedBox(height: 12),
        InkWell(
          onTap: openLibrary,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            child: Row(
              children: [
                const Icon(
                  LucideIcons.graduationCap,
                  size: 18,
                  color: Color(0xFF3B82F6),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تصفّح الملازم ومقاطع الفيديو',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                _StatPill(
                  isDarkMode: isDarkMode,
                  icon: LucideIcons.fileText,
                  value: files,
                  label: 'ملزمة',
                ),
                const SizedBox(width: 8),
                _StatPill(
                  isDarkMode: isDarkMode,
                  icon: LucideIcons.youtube,
                  value: videos,
                  label: 'فيديو',
                ),
                const SizedBox(width: 8),
                _StatPill(
                  isDarkMode: isDarkMode,
                  icon: LucideIcons.folder,
                  value: folders,
                  label: 'مجلد',
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronLeft,
                  size: 18,
                  color: isDarkMode
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
        if (pending)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _failed
                  ? 'تعذّر حساب الأعداد — اضغط للفتح'
                  : 'لم تُحسب الأعداد بعد — اضغط للفتح',
              style: TextStyle(
                fontSize: 11,
                color: isDarkMode
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
      ],
    );
  }
}

/// Icon + count + caption, sized for the compact library row.
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.isDarkMode,
    required this.icon,
    required this.value,
    required this.label,
  });

  final bool isDarkMode;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final muted = isDarkMode
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }
}

Widget _buildLibrarySection(
  BuildContext context,
  AppProvider app,
  bool isDarkMode,
) {
  final user = app.currentUser;
  final hasUniversity = user != null && user.universityId?.isNotEmpty == true;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (hasUniversity)
        UniversityLibrarySummaryCard(isDarkMode: isDarkMode, user: user)
      else ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('مجلداتي', isDarkMode),
            TextButton.icon(
              onPressed: () => _showCreateFolderDialog(context),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('مجلد جديد'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue[600]),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildRealFolderGrid(isDarkMode),
      ],
      if (user != null && user.isAdmin && !hasUniversity) ...[
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _migrateAdminAccount(context),
            icon: const Icon(LucideIcons.graduationCap, size: 18),
            label: const Text('Setup University (Admin Migration)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

Widget _buildToDoSection(BuildContext context, bool isDarkMode) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSectionHeader('مهام اليوم', isDarkMode),
          IconButton(
            onPressed: () => _showAddTaskDialog(context),
            icon: const Icon(LucideIcons.plusCircle, size: 18),
            color: Colors.indigo,
            tooltip: 'إضافة مهمة',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildToDoListMock(isDarkMode),
    ],
  );
}

// ─── ADMIN ANNOUNCEMENT SENDER ──────────────────────────────────────────────

class _AdminAnnouncementSender extends StatefulWidget {
  final bool isDarkMode;
  final String authorName;
  final String userRole;
  const _AdminAnnouncementSender({
    required this.isDarkMode,
    required this.authorName,
    required this.userRole,
  });

  @override
  State<_AdminAnnouncementSender> createState() =>
      _AdminAnnouncementSenderState();
}

class _AdminAnnouncementSenderState extends State<_AdminAnnouncementSender> {
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

Widget _buildAdminAnnouncementSender(
  bool isDarkMode,
  String authorName,
  String userRole,
) {
  return _AdminAnnouncementSender(
    isDarkMode: isDarkMode,
    authorName: authorName,
    userRole: userRole,
  );
}

// REMOVED: Replaced by unified _buildMainContentArea

// ─── HERO SECTION (WELCOME & JOIN) ──────────────────────────────────────────

Widget _buildHeroSection(BuildContext context, AppProvider app) {
  final isDarkMode = app.isDarkMode;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greetingFor(app.currentUser),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _academicLineOf(app.currentUser),
                  style: TextStyle(
                    fontSize: 15,
                    color: isDarkMode
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildQuickStatChip(app),
        ],
      ),
    ],
  );
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

String _greetingFor(AppUser? user) => 'مرحبًا بك، ${_displayNameOf(user)} 👋';

/// College · department · stage as one line, used as the hero subtitle.
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

// ─── ANNOUNCEMENTS SECTION ──────────────────────────────────────────────────

class _AnnouncementsSection extends StatefulWidget {
  final bool isDarkMode;
  final bool canPublish;
  final String authorName;
  final String userRole;

  const _AnnouncementsSection({
    required this.isDarkMode,
    required this.canPublish,
    required this.authorName,
    required this.userRole,
  });

  @override
  State<_AnnouncementsSection> createState() => _AnnouncementsSectionState();
}

class _AnnouncementsSectionState extends State<_AnnouncementsSection> {
  bool _showSender = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.bell,
                  size: 20,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                _buildSectionHeader('الإشعارات', isDarkMode),
              ],
            ),
            if (widget.canPublish)
              TextButton.icon(
                onPressed: () => setState(() => _showSender = !_showSender),
                icon: Icon(
                  _showSender ? LucideIcons.chevronUp : LucideIcons.send,
                  size: 16,
                ),
                label: Text(_showSender ? 'إغلاق' : 'نشر إشعار'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_showSender) ...[
          _buildAdminAnnouncementSender(
            isDarkMode,
            widget.authorName,
            widget.userRole,
          ),
          const SizedBox(height: 16),
        ],
        _buildAnnouncementsList(isDarkMode),
      ],
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

          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 350),
            child: ListView.builder(
              shrinkWrap: true,
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
                      color: isDarkMode
                          ? const Color(0xFF1E293B)
                          : Colors.white,
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
                                        color:
                                            ann['targetAudience'] == 'student'
                                            ? Colors.blue.withValues(alpha: 0.1)
                                            : ann['targetAudience'] ==
                                                  'lecturer'
                                            ? Colors.purple.withValues(
                                                alpha: 0.1,
                                              )
                                            : ann['targetAudience'] ==
                                                  'student_developer'
                                            ? Colors.teal.withValues(alpha: 0.1)
                                            : Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color:
                                              ann['targetAudience'] == 'student'
                                              ? Colors.blue.withValues(
                                                  alpha: 0.3,
                                                )
                                              : ann['targetAudience'] ==
                                                    'lecturer'
                                              ? Colors.purple.withValues(
                                                  alpha: 0.3,
                                                )
                                              : ann['targetAudience'] ==
                                                    'student_developer'
                                              ? Colors.teal.withValues(
                                                  alpha: 0.3,
                                                )
                                              : Colors.red.withValues(
                                                  alpha: 0.3,
                                                ),
                                        ),
                                      ),
                                      child: Text(
                                        ann['targetAudience'] == 'student'
                                            ? 'للطلاب'
                                            : ann['targetAudience'] ==
                                                  'lecturer'
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
            ),
          );
        },
      );
    },
  );
}
// ─── TO-DO LIST MOCK ────────────────────────────────────────────────────────

Widget _buildToDoListMock(bool isDarkMode) {
  return Consumer<AppProvider>(
    builder: (context, app, _) {
      final tasks = app.tasks;

      if (tasks.isEmpty) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.listTodo,
                size: 32,
                color: Color(0x1F000000), // Default black12
              ),
              const SizedBox(height: 12),
              Text(
                'لا توجد مهام حالياً',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        );
      }

      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 100),
        child: Container(
          padding: const EdgeInsets.all(16),
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
          child: Column(
            children: tasks.map((task) {
              final bool isDone = task.isDone;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: isDone,
                        onChanged: (val) {
                          app.toggleTask(task.uuid);
                        },
                        activeColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDone
                              ? (isDarkMode
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8))
                              : (isDarkMode
                                    ? Colors.white
                                    : const Color(0xFF0F172A)),
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 14),
                      onPressed: () => app.deleteTask(task.uuid),
                      color: Colors.red.withValues(alpha: 0.6),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'حذف المهمة',
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      );
    },
  );
}

void _showAddTaskDialog(BuildContext context) {
  final TextEditingController controller = TextEditingController();
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : Colors.white,
      title: const Text('إضافة مهمة جديدة'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'ماذا تريد أن تفعل؟'),
        onSubmitted: (val) {
          if (val.trim().isNotEmpty) {
            context.read<AppProvider>().addTask(val.trim());
            Navigator.pop(context);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              context.read<AppProvider>().addTask(controller.text.trim());
              Navigator.pop(context);
            }
          },
          child: const Text('إضافة'),
        ),
      ],
    ),
  );
}

// ─── UTILITIES & COMPONENTS ─────────────────────────────────────────────────

Widget _buildQuickActionChips(BuildContext context, bool isDarkMode) {
  // One accent, one primary action. The rest fall back to a neutral outline so
  // the eye lands on "upload" first instead of parsing four competing colours.
  const accent = Color(0xFF3B82F6);
  final neutral = isDarkMode
      ? const Color(0xFFCBD5E1)
      : const Color(0xFF334155);
  const actions = <Map<String, Object?>>[
    {
      'icon': LucideIcons.upload,
      'label': 'رفع PDF',
      'primary': true,
      'enabled': true,
    },
    {'icon': LucideIcons.combine, 'label': 'دمج ملفات', 'enabled': true},
    {'icon': LucideIcons.image, 'label': 'صور إلى PDF', 'enabled': true},
    {
      'icon': LucideIcons.languages,
      'label': 'ترجمة الملفات (قريباً)',
      // Nothing opens behind this one, so it must not look clickable.
      'enabled': false,
    },
  ];

  return SizedBox(
    width: double.infinity,
    // A `shrinkWrap` grid sizes itself to its widest child, so it needs an
    // explicit full width or the tiles stay narrow inside a wide column.
    child: GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      // The dashboard already scrolls; the grid must not claim a scroll
      // gesture of its own or it swallows vertical drags.
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: actions.map((a) {
        final label = a['label'] as String;
        final isPrimary = a['primary'] == true;
        final isEnabled = a['enabled'] as bool;

        return InkWell(
          onTap: !isEnabled
              ? null
              : () {
                  final app = context.read<AppProvider>();
                  if (label == 'رفع PDF') {
                    final classId =
                        app.activeClassId ??
                        (app.classes.isNotEmpty ? app.classes.first.id : null);
                    if (classId != null) {
                      app.uploadPdf(classId);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'يرجى إنشاء مجلد أولاً لرفع الملف إليه.',
                          ),
                        ),
                      );
                    }
                  } else if (label == 'دمج ملفات') {
                    showDialog(
                      context: context,
                      builder: (_) => const MergePdfDialog(),
                    );
                  } else if (label == 'صور إلى PDF') {
                    showDialog(
                      context: context,
                      builder: (_) => const ImagesToPdfDialog(),
                    );
                  }
                },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // The primary action is the only filled surface; the disabled chip
              // fades out entirely so it reads as unavailable, not as a third
              // action with a different hue.
              color: !isEnabled
                  ? (isDarkMode
                        ? Colors.white.withValues(alpha: 0.02)
                        : Colors.black.withValues(alpha: 0.02))
                  : isPrimary
                  ? accent
                  : (isDarkMode
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.02)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: !isEnabled
                    ? (isDarkMode
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.05))
                    : isPrimary
                    ? accent
                    : (isDarkMode
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.12)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  a['icon'] as IconData,
                  size: 18,
                  color: !isEnabled
                      ? neutral.withValues(alpha: 0.3)
                      : isPrimary
                      ? Colors.white
                      : neutral,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: !isEnabled
                          ? neutral.withValues(alpha: 0.35)
                          : isPrimary
                          ? Colors.white
                          : neutral,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}

void _showCreateFolderDialog(BuildContext context) {
  final TextEditingController controller = TextEditingController();
  final isDarkMode = context.read<AppProvider>().isDarkMode;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
      title: Text(
        'إنشاء مجلد جديد',
        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: 'اسم المجلد...',
          hintStyle: TextStyle(
            color: isDarkMode ? Colors.white54 : Colors.black54,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              await context.read<AppProvider>().addClass(name);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('إنشاء'),
        ),
      ],
    ),
  );
}

Widget _buildRealFolderGrid(bool isDarkMode) {
  return Consumer<FileManagerService>(
    builder: (context, fileService, _) {
      return FutureBuilder<List<ClassFolder>>(
        future: fileService.getFoldersOrdered(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }

          final folders = snapshot.data ?? [];

          if (folders.isEmpty) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1E293B).withOpacity(0.5)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  style: BorderStyle.none,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    LucideIcons.folderX,
                    size: 48,
                    color: isDarkMode ? Colors.grey[600] : Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'لا توجد مجلدات حالياً',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.3,
            ),
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return InkWell(
                onTap: () {
                  context.read<AppProvider>().setActiveClass(folder.uuid);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
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
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(60),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.folder,
                              color: Colors.blue[400],
                              size: 32,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              folder.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDarkMode
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${folder.pdfIds.length} ملفات',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
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

Widget _buildSectionHeader(String title, bool isDarkMode) {
  return Text(
    title,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
    ),
  );
}

Widget _buildQuickStatChip(AppProvider app) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.flame, color: Colors.orange, size: 14),
        const SizedBox(width: 4),
        Text(
          '${app.totalHighlights} نقاط تركيز',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    ),
  );
}
