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
        prev.user?.uid != next.user?.uid,
    builder: (context, data, _) => _DashboardWrapper(
      isDarkMode: data.isDarkMode,
      app: context.read<AppProvider>(),
      isAdmin: data.user?.role == 'developer' || data.user?.role == 'lecturer',
      isDeveloper: data.user?.role == 'developer',
    ),
  );
}

class _DashboardWrapper extends StatefulWidget {
  final bool isDarkMode;
  final AppProvider app;
  final bool isAdmin;
  final bool isDeveloper;

  const _DashboardWrapper({
    required this.isDarkMode,
    required this.app,
    required this.isAdmin,
    required this.isDeveloper,
  });

  @override
  State<_DashboardWrapper> createState() => _DashboardWrapperState();
}

class _DashboardWrapperState extends State<_DashboardWrapper> {
  late Future<List<PdfDocument>> _recentDocsFuture;

  @override
  void initState() {
    super.initState();
    // MEMOIZATION: Future only created once per widget lifecycle
    _recentDocsFuture = context.read<FileManagerService>().getRecentDocuments(
      limit: 6,
    );
  }

  int _estimateReadingTime(List<PdfDocument> allDocs) {
    int totalMinutes = 0;
    for (var doc in allDocs) {
      final lastPage = doc.lastPage;
      if (lastPage > 0) {
        totalMinutes += lastPage * 2;
      }
    }
    return totalMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final app = widget.app;
    final isDeveloper = widget.isDeveloper;

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
            final padding = width < 600
                ? 12.0
                : (width < 900 ? 16.0 : 20.0);
            final isWide = ResponsiveBreakpoints.isDesktop(width);
            final isTablet = ResponsiveBreakpoints.isTablet(width);

            return Container(
              margin: EdgeInsets.all(padding),
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
              child: FutureBuilder<List<PdfDocument>>(
                future: _recentDocsFuture,
                builder: (context, snapshot) {
                  final recentDocs = snapshot.data ?? <PdfDocument>[];
                  final readingTimeEstimate = _estimateReadingTime(
                    recentDocs,
                  ); // Using recentDocs for now or pass allDocs if available

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroSection(context, app),
                        const SizedBox(height: 32),

                        _buildMainContentArea(
                          context,
                          app,
                          isDarkMode,
                          recentDocs,
                          readingTimeEstimate,
                          isWide,
                          isTablet,
                        ),

                        const SizedBox(height: 48),

                        _buildSectionHeader(
                          isDeveloper
                              ? 'لوحة تحكم المطور - نشر الإعلانات'
                              : (app.currentUser?.role == 'lecturer'
                                    ? 'نشر إشعار للطلاب'
                                    : ((app.currentUser?.role == 'student' ||
                                              app.currentUser?.role == 'member')
                                          ? 'نشر إشعار للطلاب والمبرمج'
                                          : 'الكتب الأخيرة')),
                          isDarkMode,
                        ),
                        const SizedBox(height: 20),

                        if (isDeveloper ||
                            app.currentUser?.role == 'lecturer' ||
                            app.currentUser?.role == 'student' ||
                            app.currentUser?.role == 'member')
                          _buildAdminAnnouncementSender(
                            isDarkMode,
                            app.currentUser?.displayName ?? 'User',
                            app.currentUser?.role ?? 'student',
                          )
                        else
                          _buildRecentVerticalList(
                            context,
                            recentDocs,
                            isDarkMode,
                          ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget _buildMainContentArea(
  BuildContext context,
  AppProvider app,
  bool isDarkMode,
  List<PdfDocument> recentDocs,
  int readingTimeEstimate,
  bool isWide,
  bool isTablet,
) {
  final content = [
    // Left/Primary Column Logic
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: 32),
        _buildSectionHeader('إجراءات سريعة', isDarkMode),
        const SizedBox(height: 16),
        _buildQuickActionChips(context, isDarkMode),
      ],
    ),

    if (isWide) const SizedBox(width: 32) else const SizedBox(height: 32),

    // Right/Secondary Column Logic
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.bell, size: 20, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            _buildSectionHeader('إعلانات هامة', isDarkMode),
          ],
        ),
        const SizedBox(height: 16),
        _buildAnnouncementsSection(isDarkMode),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.checkSquare,
                  size: 20,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 8),
                _buildSectionHeader('مهام اليوم', isDarkMode),
              ],
            ),
            TextButton(
              onPressed: () => _showAddTaskDialog(context),
              child: const Text('إضافة مهمة', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildToDoListMock(isDarkMode),
      ],
    ),
  ];

  if (isWide) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: content[0]),
        content[1],
        Expanded(flex: 1, child: content[2]),
      ],
    );
  } else if (isTablet) {
    return Column(
      children: [
        content[0],
        const SizedBox(height: 24),
        content[1],
        const SizedBox(height: 24),
        content[2],
      ],
    );
  } else {
    return Column(children: [content[0], content[1], content[2]]);
  }
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

  bool get _isDeveloper => widget.userRole == 'developer';
  bool get _isLecturer => widget.userRole == 'lecturer';

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
                  'مرحبًا بك مجددًا 👋',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'ماذا تريد أن تتعلم اليوم؟',
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
      const SizedBox(height: 24),
      const JoinSessionBar(),
    ],
  );
}

class JoinSessionBar extends StatefulWidget {
  const JoinSessionBar({super.key});

  @override
  State<JoinSessionBar> createState() => _JoinSessionBarState();
}

class _JoinSessionBarState extends State<JoinSessionBar> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final provider = context.read<AppProvider>();
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى إدخال كود الدرس.')));
      return;
    }

    final error = await provider.joinSession(code);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
    } else {
      _codeController.clear();
      // Success is handled by AppProvider (switching to the PDF)
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isDarkMode = app.isDarkMode;
    final isJoining = app.isJoiningSession;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(
            LucideIcons.radio,
            color: Color(0xFF2563EB), // Default blue-600
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _codeController,
              enabled: !isJoining,
              decoration: InputDecoration(
                hintText: 'أدخل كود الدرس للبدء...',
                hintStyle: TextStyle(
                  color: isDarkMode
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              onSubmitted: (_) => _handleJoin(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: isJoining ? null : _handleJoin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: isJoining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: const RepaintBoundary(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : const Text(
                    'انضمام الآن',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── ANNOUNCEMENTS SECTION ──────────────────────────────────────────────────

Widget _buildAnnouncementsSection(bool isDarkMode) {
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
                'لا توجد إعلانات حالياً',
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
  final actions = [
    {'icon': LucideIcons.upload, 'label': 'رفع PDF', 'color': Colors.blue},
    {'icon': LucideIcons.combine, 'label': 'دمج ملفات', 'color': Colors.purple},
    {'icon': LucideIcons.image, 'label': 'صور إلى PDF', 'color': Colors.teal},
    {
      'icon': LucideIcons.languages,
      'label': 'ترجمة الملفات (قريباً)',
      'color': Colors.indigo,
    },
  ];

  return Wrap(
    spacing: 12,
    runSpacing: 12,
    children: actions.map((a) {
      final color = a['color'] as MaterialColor;
      final label = a['label'] as String;
      return InkWell(
        onTap: () {
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
                  content: Text('يرجى إنشاء مجلد أولاً لرفع الملف إليه.'),
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
          } else if (label == 'ترجمة الملفات (قريباً)') {
            // TODO: Feature under development
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ميزة ترجمة الملفات قيد التطوير حالياً...'),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDarkMode
                ? color.withValues(alpha: 0.1)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                a['icon'] as IconData,
                size: 18,
                color: color[isDarkMode ? 400 : 600],
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  a['label'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isDarkMode ? Colors.white : color[900],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
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

Widget _buildRecentVerticalList(
  BuildContext context,
  List<PdfDocument> docs,
  bool isDarkMode,
) {
  if (docs.isEmpty) return const Text('لا توجد ملفات حديثة');

  return ListView.separated(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: docs.length,
    separatorBuilder: (_, __) => const SizedBox(height: 12),
    itemBuilder: (context, index) {
      final doc = docs[index];
      return InkWell(
        onTap: () => context.read<AppProvider>().setActivePdf(doc.uuid),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.fileText,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.originalPath.split(Platform.pathSeparator).last,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'آخر مرة: منذ يومين',
                      style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevronLeft,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
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
