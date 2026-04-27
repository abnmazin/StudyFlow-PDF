import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../screens/auth/login_screen.dart';

class GlobalSettingsModal extends StatefulWidget {
  const GlobalSettingsModal({super.key});

  @override
  State<GlobalSettingsModal> createState() => _GlobalSettingsModalState();
}

class _GlobalSettingsModalState extends State<GlobalSettingsModal> {
  final Set<String> _selectedHashes = {};
  bool _isGenerating = false;
  String? _generatedMasterCode;
  bool _showDevDashboard = false;
  int _selectedIndex = 0;

  // Version management
  String _currentAppVersion = '';
  String _minVersion = '';
  String _latestVersion = '';
  bool _versionLoading = true;
  bool _versionSaving = false;
  final TextEditingController _minVersionController = TextEditingController();
  final TextEditingController _latestVersionController =
      TextEditingController();

  final TextEditingController _joinCodeController = TextEditingController();
  bool _isJoining = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadVersionData();
  }

  @override
  void dispose() {
    _minVersionController.dispose();
    _latestVersionController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadVersionData() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _currentAppVersion = packageInfo.version);

      // Load remote versions for developer editing
      if (context.read<AppProvider>().currentUser?.role == 'developer') {
        final doc = await FirebaseFirestore.instance
            .collection('app_config')
            .doc('version')
            .get();
        if (!mounted) return;
        if (doc.exists && doc.data() != null) {
          setState(() {
            _minVersion = doc.data()!['min_version'] as String? ?? '';
            _latestVersion = doc.data()!['latest_version'] as String? ?? '';
            _minVersionController.text = _minVersion;
            _latestVersionController.text = _latestVersion;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _versionLoading = false);
    }
  }

  Future<void> _saveVersions() async {
    final newMin = _minVersionController.text.trim();
    final newLatest = _latestVersionController.text.trim();
    final semver = RegExp(r'^\d+\.\d+\.\d+$');
    if (!semver.hasMatch(newMin) || !semver.hasMatch(newLatest)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('صيغة غير صحيحة — استخدم x.y.z مثل 1.0.0'),
        ),
      );
      return;
    }
    setState(() => _versionSaving = true);
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('version').set({
        'min_version': newMin,
        'latest_version': newLatest,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _minVersion = newMin;
        _latestVersion = newLatest;
        _versionSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ الإصدار بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _versionSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ فشل الحفظ: $e')));
    }
  }

  // ─── ميثودات التحكم بالحزم (قفل، حظر، حذف) ──────────────────────────────────

  Future<void> _joinMasterBundle(AppProvider app) async {
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('الرجاء إدخال كود الحزمة')));
      return;
    }

    setState(() => _isJoining = true);

    try {
      final bundleDoc = await app.syncService.getMasterBundle(code);
      if (bundleDoc == null) {
        throw Exception('كود الحزمة غير صحيح أو لا يوجد');
      }

      final bundleList = bundleDoc['bundle'] as List<dynamic>? ?? [];
      final bool isLocked = bundleDoc['isLocked'] as bool? ?? false;
      final List bannedUsernames = bundleDoc['bannedUsernames'] as List? ?? [];
      final String? currentUsername = app.currentUser?.username;

      if (isLocked) {
        throw Exception('هذه الحزمة مغلقة حالياً من قبل المحاضر.');
      }

      if (currentUsername != null &&
          bannedUsernames.contains(currentUsername)) {
        throw Exception('لقد تم حظرك من الوصول إلى محتويات هذه الحزمة.');
      }

      if (currentUsername != null) {
        await app.syncService.registerMasterBundleActivation(
          code,
          currentUsername,
        );
      }

      final result = app.linkMasterBundle(bundleList);
      final int successCount = result['successCount'] ?? 0;
      final List<String> missingFiles = List<String>.from(
        result['missingFiles'] ?? [],
      );

      if (mounted) {
        _joinCodeController.clear();
        _showJoinSummaryDialog(context, successCount, missingFiles);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ: ${e.toString().replaceAll("Exception:", "").trim()}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  void _showJoinSummaryDialog(
    BuildContext context,
    int successCount,
    List<String> missingFiles,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: const Row(
            children: [
              Icon(LucideIcons.checkCircle, color: Colors.green),
              SizedBox(width: 8),
              Text('نتيجة الربط'),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تم ربط ($successCount) ملفات بنجاح. 🔗',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (missingFiles.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(
                        LucideIcons.alertTriangle,
                        color: Colors.orange,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تنبيه: الملفات التالية غير متوفرة بجهازك:',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black12 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: missingFiles.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '- ${missingFiles[index]}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('موافق'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleLock(AppProvider app, String docId, bool status) async {
    await app.syncService.toggleMasterBundleLock(docId, status);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status ? 'تم قفل الحزمة' : 'تم فتح الحزمة')),
      );
    }
  }

  void _manageBannedUsers(
    BuildContext context,
    AppProvider app,
    String bundleId,
    List<String> activators,
    List<String> bannedUsernames,
  ) {
    final controller = TextEditingController();
    final allStudents = <String>{...activators, ...bannedUsernames}.toList()
      ..sort();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إدارة مستخدمي الحزمة'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'حظر يوزر يدوي...',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.userPlus,
                        color: Colors.blue,
                      ),
                      onPressed: () async {
                        final name = controller.text.trim();
                        if (name.isNotEmpty) {
                          await app.syncService.banUserFromMasterBundle(
                            bundleId,
                            name,
                          );
                          controller.clear();
                          Navigator.pop(ctx);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'قائمة الطلاب النشطين والمحظورين:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (allStudents.isEmpty)
                  const Text(
                    'لا يوجد مسجلون.',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: allStudents.length,
                      itemBuilder: (context, index) {
                        final username = allStudents[index];
                        final isBanned = bannedUsernames.contains(username);
                        return ListTile(
                          dense: true,
                          title: Text(
                            username,
                            style: TextStyle(
                              fontSize: 12,
                              color: isBanned ? Colors.red : null,
                              decoration: isBanned
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isBanned
                                  ? LucideIcons.userCheck
                                  : LucideIcons.userX,
                              color: isBanned ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            onPressed: () async {
                              if (isBanned)
                                await app.syncService.unbanUserFromMasterBundle(
                                  bundleId,
                                  username,
                                );
                              else
                                await app.syncService.banUserFromMasterBundle(
                                  bundleId,
                                  username,
                                );
                              Navigator.pop(ctx);
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    String collection,
    String docId,
    String itemType,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف $itemType'),
        content: const Text('هل أنت متأكد؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection(collection).doc(docId).delete();
    }
  }

  // ─── منطق إنشاء الحزمة ─────────────────────────────────────────────────────

  Future<void> _generateMasterBundle(AppProvider app) async {
    if (_selectedHashes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد ملفاً واحداً على الأقل.')),
      );
      return;
    }
    setState(() {
      _isGenerating = true;
      _generatedMasterCode = null;
    });
    try {
      final user = app.currentUser;
      if (user == null) throw Exception('Unauthorized');
      final List<Map<String, dynamic>> bundle = [];
      for (var cls in app.classes) {
        for (var pdf in cls.pdfs) {
          if (pdf.fileHash != null && _selectedHashes.contains(pdf.fileHash)) {
            final code = await app.syncService.generateSessionCode(
              pdf.fileHash!,
              pdf.name,
              pdf.pageCount ?? 0,
              user.hardwareId,
              user.username,
              user.uid,
            );
            if (code != null)
              bundle.add({
                'hash': pdf.fileHash,
                'sessionCode': code,
                'name': pdf.name,
              });
          }
        }
      }
      final masterCode = await app.syncService.createMasterBundle(
        user.username,
        bundle,
      );
      setState(() => _generatedMasterCode = masterCode);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isDark = app.isDarkMode;
    final scheme = Theme.of(context).colorScheme;

    final bg = isDark ? const Color(0xFF0F172A) : scheme.surface;
    final panelBorder = isDark ? const Color(0xFF334155) : scheme.outlineVariant;
    final textPrimary = isDark ? Colors.white : scheme.onSurface;
    final textMuted = isDark ? const Color(0xFF94A3B8) : scheme.onSurfaceVariant;
    final surfaceAlt = isDark ? const Color(0xFF1E293B) : scheme.surfaceContainerHighest;
    final role = app.currentUser?.role ?? 'member';
    final isDev = role == 'developer';
    final isLecturer = role == 'lecturer';
    final isStudent = !isDev && !isLecturer;

    return Container(
      width: 650,
      height: 650,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(-5, 0),
          ),
        ],
      ),
      child: _showDevDashboard
          ? DeveloperDashboardView(
              onBack: () => setState(() => _showDevDashboard = false),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sidebar (الجانب الأيمن) ──
                SizedBox(
                  width: 170,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          padding: const EdgeInsets.all(12),
                          onPressed: () => app.toggleSettings(false),
                          icon: Icon(LucideIcons.x, color: textMuted),
                        ),
                      ),
                      _buildSidebarHeader(app),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildNavItem(LucideIcons.palette, 'المظهر', 0, textPrimary, textMuted),
                            _buildNavItem(LucideIcons.bot, 'الذكاء الاصطناعي', 1, textPrimary, textMuted),
                            _buildNavItem(LucideIcons.info, 'عن التطبيق', 2, textPrimary, textMuted),

                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Divider(height: 1),
                            ),

                            if (isStudent)
                              _buildNavItem(LucideIcons.link2, 'ربط حزمة', 3, textPrimary, textMuted),

                            if (isLecturer || isDev) ...[
                              _buildNavItem(LucideIcons.graduationCap, 'إنشاء حزمة', 3, textPrimary, textMuted),
                              _buildNavItem(LucideIcons.history, 'سجل الحزم', 4, textPrimary, textMuted),
                            ],

                            if (isDev) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                child: Divider(height: 1),
                              ),
                              _buildNavItem(LucideIcons.shieldCheck, 'لوحة التحكم', 5, textPrimary, textMuted),
                              _buildNavItem(LucideIcons.packageOpen, 'الإصدارات', 6, textPrimary, textMuted),
                            ],
                          ],
                        ),
                      ),
                      _buildLogoutItem(app),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

                // فاصل عمودي
                VerticalDivider(width: 1, color: panelBorder, thickness: 1),

                // ── Content Area (الجانب الأيسر) ──
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(_selectedIndex),
                      child: _selectedIndex == 5 && isDev
                          // لوحة التحكم تملك الـ Scroll الخاص بها، لذا لا نضعها بداخل SingleChildScrollView
                          ? Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: DeveloperDashboardView(
                                onBack: () => setState(() => _selectedIndex = 0),
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              physics: const BouncingScrollPhysics(),
                              child: _buildContentForIndex(
                                _selectedIndex,
                                app,
                                surfaceAlt,
                                panelBorder,
                                textPrimary,
                                textMuted,
                                isDark,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildContentForIndex(
    int index,
    AppProvider app,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
    bool isDark,
  ) {
    final role = app.currentUser?.role ?? 'member';
    final isDev = role == 'developer';
    final isLecturer = role == 'lecturer';

    switch (index) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('المظهر والنظام', LucideIcons.palette, textPrimary),
            const SizedBox(height: 16),
            _buildSettingsCard(surfaceAlt, panelBorder, [
              _buildToggleTile(
                icon: isDark ? LucideIcons.sun : LucideIcons.moon,
                label: isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
                value: isDark,
                onChanged: (_) => app.toggleDarkMode(),
                textPrimary: textPrimary,
              ),
            ]),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('إعدادات الذكاء الاصطناعي', LucideIcons.bot, textPrimary),
            const SizedBox(height: 16),
            _buildAiSettingsContent(context, app, surfaceAlt, panelBorder, textPrimary, textMuted),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('عن التطبيق', LucideIcons.info, textPrimary),
            const SizedBox(height: 16),
            _buildAboutSection(surfaceAlt, panelBorder, textPrimary, textMuted),
          ],
        );
      case 3:
        if (isLecturer || isDev) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('أدوات المحاضر: إنشاء حزمة', LucideIcons.graduationCap, textPrimary),
              const SizedBox(height: 16),
              _buildMasterBundleCreator(app, surfaceAlt, panelBorder, textPrimary, textMuted, isDark),
              if (isLecturer) ...[
                const SizedBox(height: 32),
                _buildSectionHeader('الانضمام إلى حزمة', LucideIcons.link2, textPrimary),
                const SizedBox(height: 16),
                _buildCompactJoinCard(context, app, surfaceAlt, panelBorder, textPrimary, textMuted),
              ]
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('أدوات الطالب', LucideIcons.userCheck, textPrimary),
              const SizedBox(height: 16),
              _buildCompactJoinCard(context, app, surfaceAlt, panelBorder, textPrimary, textMuted),
            ],
          );
        }
      case 4:
        if (isLecturer || isDev) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('سجل الحزم السابقة وإدارتها', LucideIcons.history, textPrimary),
              const SizedBox(height: 16),
              _buildMasterBundleHistory(app, surfaceAlt, panelBorder, textPrimary, textMuted),
            ],
          );
        }
        return const SizedBox.shrink();
      case 6:
        if (isDev) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('إدارة إصدارات التطبيق', LucideIcons.packageOpen, textPrimary),
              const SizedBox(height: 16),
              _buildVersionManagement(surfaceAlt, panelBorder, textPrimary, textMuted),
            ],
          );
        }
        return const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSidebarHeader(AppProvider app) {
    final role = app.currentUser?.role ?? 'member';
    final name = app.currentUser?.displayName ?? app.currentUser?.username ?? 'مستخدم';

    Color roleColor = Colors.blue;
    String roleLabel = 'طالب';
    if (role == 'developer') {
      roleColor = Colors.amber;
      roleLabel = 'مشرف (مطور)';
    } else if (role == 'lecturer') {
      roleColor = Colors.purple;
      roleLabel = 'محاضر';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: roleColor.withOpacity(0.15),
            child: Icon(LucideIcons.user, color: roleColor, size: 26),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              roleLabel,
              style: TextStyle(fontSize: 10, color: roleColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index, Color textPrimary, Color textMuted) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3B82F6).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF3B82F6) : textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? const Color(0xFF3B82F6) : textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutItem(AppProvider app) {
    return InkWell(
      onTap: () => _confirmLogout(context, app),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.logOut,
              size: 16,
              color: Colors.red,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'تسجيل الخروج',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, AppProvider app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () {
              app.logout();
              app.toggleSettings(false);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('خروج'),
          ),
        ],
      ),
    );
  }

  // ─── عناصر واجهة السجل مع أزرار التحكم ───────────────────────────────────────

  Widget _buildMasterBundleHistory(
    AppProvider app,
    Color surface,
    Color border,
    Color text,
    Color muted,
  ) {
    return _buildSettingsCard(surface, border, [
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: app.syncService.watchMasterBundlesByOwner(
          app.currentUser?.username ?? '',
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            );
          final bundles = snapshot.data!;
          if (bundles.isEmpty)
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'لا توجد حزم.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            );

          return Column(
            children: bundles.map((data) {
              final files = data['bundle'] as List? ?? [];
              final bool isLocked = data['isLocked'] as bool? ?? false;
              final docId = data['id'] ?? data['masterCode'];

              return ExpansionTile(
                title: Row(
                  children: [
                    Text(
                      data['masterCode'],
                      style: TextStyle(
                        color: isLocked ? Colors.red : text,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    if (isLocked) ...[
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.lock, size: 12, color: Colors.red),
                    ],
                  ],
                ),
                subtitle: Text(
                  'ملفات: ${files.length}',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                leading: Icon(
                  LucideIcons.package,
                  size: 18,
                  color: isLocked ? Colors.red : Colors.orange,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isLocked ? LucideIcons.unlock : LucideIcons.lock,
                        size: 16,
                        color: isLocked ? Colors.green : Colors.red,
                      ),
                      onPressed: () => _toggleLock(app, docId, !isLocked),
                      tooltip: isLocked ? 'فتح الحزمة' : 'قفل الحزمة',
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.userX,
                        size: 16,
                        color: Colors.amber,
                      ),
                      onPressed: () => _manageBannedUsers(
                        context,
                        app,
                        docId,
                        List<String>.from(data['activators'] ?? []),
                        List<String>.from(data['bannedUsernames'] ?? []),
                      ),
                      tooltip: 'إدارة المحظورين',
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.trash2,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      onPressed: () =>
                          _confirmDelete('master_sessions', docId, 'الحزمة'),
                      tooltip: 'حذف نهائي',
                    ),
                  ],
                ),
                children: files
                    .map(
                      (f) => ListTile(
                        dense: true,
                        title: Text(
                          f['name'] ?? 'Unnamed',
                          style: TextStyle(color: text, fontSize: 11),
                        ),
                        leading: const Icon(LucideIcons.fileText, size: 14),
                      ),
                    )
                    .toList(),
              );
            }).toList(),
          );
        },
      ),
    ]);
  }

  Widget _buildCompactJoinCard(
    BuildContext context,
    AppProvider app,
    Color surface,
    Color border,
    Color text,
    Color muted,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.link2,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الارتباط بحزمة دراسية',
                      style: TextStyle(
                        color: text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'أدخل كود المنهج للوصول الفوري للملفات',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _joinCodeController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.blue,
                  ),
                  decoration: InputDecoration(
                    hintText: 'الكود هنا...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0,
                      color: muted.withOpacity(0.5),
                      fontWeight: FontWeight.normal,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0F172A)
                        : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isJoining ? null : () => _joinMasterBundle(app),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: _isJoining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'ربط',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── الهيلبرز المتبقية ──────────────────────────────────────────

  Widget _buildMasterBundleCreator(
    AppProvider app,
    Color surface,
    Color border,
    Color text,
    Color muted,
    bool isDark,
  ) {
    return _buildSettingsCard(surface, border, [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ...app.classes.map((cls) {
              final bool allSelected =
                  cls.pdfs.isNotEmpty &&
                  cls.pdfs.every(
                    (p) =>
                        p.fileHash != null &&
                        _selectedHashes.contains(p.fileHash),
                  );
              return ExpansionTile(
                title: Text(
                  cls.name,
                  style: TextStyle(
                    color: text,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: const Icon(
                  LucideIcons.folder,
                  size: 18,
                  color: Colors.blue,
                ),
                trailing: Checkbox(
                  value: allSelected,
                  onChanged: (val) {
                    setState(() {
                      for (var p in cls.pdfs) {
                        if (p.fileHash != null && p.fileHash!.isNotEmpty) {
                          if (val == true)
                            _selectedHashes.add(p.fileHash!);
                          else
                            _selectedHashes.remove(p.fileHash!);
                        }
                      }
                    });
                  },
                ),
                children: cls.pdfs.map((pdf) {
                  final bool hasHash =
                      pdf.fileHash != null && pdf.fileHash!.isNotEmpty;
                  final bool isSel =
                      hasHash && _selectedHashes.contains(pdf.fileHash);
                  return CheckboxListTile(
                    value: isSel,
                    onChanged: !hasHash
                        ? null
                        : (val) {
                            setState(() {
                              if (val == true)
                                _selectedHashes.add(pdf.fileHash!);
                              else
                                _selectedHashes.remove(pdf.fileHash!);
                            });
                          },
                    title: Text(
                      pdf.name,
                      style: TextStyle(
                        color: hasHash ? text : muted,
                        fontSize: 12,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }).toList(),
              );
            }).toList(),
            const SizedBox(height: 16),
            if (_generatedMasterCode != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _generatedMasterCode!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.copy,
                        size: 16,
                        color: Colors.green,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _generatedMasterCode!),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isGenerating
                    ? null
                    : () => _generateMasterBundle(app),
                icon: _isGenerating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.plus, size: 18),
                label: Text(
                  _isGenerating ? 'جاري الإنشاء...' : 'إنشاء حزمة دراسية',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildLogoutButton(BuildContext context, AppProvider app) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmLogout(context, app),
        icon: const Icon(
          LucideIcons.logOut,
          size: 18,
          color: Color(0xFFDC2626),
        ),
        label: const Text(
          'تسجيل الخروج',
          style: TextStyle(color: Color(0xFFDC2626)),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFDC2626)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) => Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 1.2,
        ),
      ),
    ],
  );

  Widget _buildSettingsCard(Color bg, Color border, List<Widget> children) =>
      Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        child: Column(children: children),
      );

  Widget _buildVersionManagement(
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    if (_versionLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return _buildSettingsCard(surfaceAlt, panelBorder, [
      // Current version display
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(LucideIcons.tag, color: textMuted, size: 18),
            const SizedBox(width: 12),
            Text('الإصدار الحالي للتطبيق', style: TextStyle(color: textPrimary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF38BDF8).withOpacity(0.4),
                ),
              ),
              child: Text(
                _currentAppVersion.isEmpty ? '...' : _currentAppVersion,
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      // min_version field
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _buildVersionField(
          label: 'الحد الأدنى — Force Update',
          controller: _minVersionController,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
      ),
      // latest_version field
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _buildVersionField(
          label: 'الأحدث — Soft Update',
          controller: _latestVersionController,
          textPrimary: textPrimary,
          textMuted: textMuted,
        ),
      ),
      // Save button
      Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _versionSaving ? null : _saveVersions,
            icon: _versionSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: Text(_versionSaving ? 'جاري الحفظ...' : 'حفظ الإصدار'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8).withOpacity(0.15),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: const Color(0xFF38BDF8).withOpacity(0.4),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildVersionField({
    required String label,
    required TextEditingController controller,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(color: textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: '1.0.0',
            hintStyle: TextStyle(color: textMuted.withOpacity(0.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: textMuted.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF38BDF8),
                width: 1.5,
              ),
            ),
            filled: true,
            fillColor: textMuted.withOpacity(0.05),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    return _buildSettingsCard(surfaceAlt, panelBorder, [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(LucideIcons.info, color: textMuted, size: 18),
            const SizedBox(width: 12),
            Text('إصدار التطبيق', style: TextStyle(color: textPrimary)),
            const Spacer(),
            Text(
              _currentAppVersion.isEmpty ? '...' : 'v$_currentAppVersion',
              style: TextStyle(
                color: textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color textPrimary,
  }) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    activeColor: const Color(0xFF3B82F6),
    title: Text(label, style: TextStyle(color: textPrimary, fontSize: 13)),
    secondary: Icon(icon, size: 20, color: textPrimary.withOpacity(0.7)),
  );

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color textPrimary,
  }) => ListTile(
    onTap: onTap,
    leading: Icon(icon, size: 20, color: textPrimary),
    title: Text(label, style: TextStyle(color: textPrimary, fontSize: 13)),
    trailing: const Icon(LucideIcons.chevronLeft, size: 16),
  );

  Widget _buildAiSettingsContent(
    BuildContext context,
    AppProvider app,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    const geminiModels = ['gemini-2.5-flash', 'gemini-2.0-flash'];
    const groqModels = ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'];
    final selectedModel = app.aiProvider == 'groq'
        ? app.groqModel
        : app.geminiModel;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: panelBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: app.aiProvider,
              decoration: InputDecoration(
                labelText: 'المزود',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                DropdownMenuItem(value: 'groq', child: Text('Groq')),
              ],
              onChanged: (v) => v != null ? app.setAiProvider(v) : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedModel,
              decoration: InputDecoration(
                labelText: 'النموذج',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: (app.aiProvider == 'groq' ? groqModels : geminiModels)
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => v == null
                  ? null
                  : (app.aiProvider == 'groq'
                        ? app.setGroqModel(v)
                        : app.setGeminiModel(v)),
            ),
            _buildKeyRow(
              context,
              app.aiProvider == 'groq' ? 'Groq API Key' : 'Gemini API Key',
              app.aiProvider == 'groq' ? app.groqApiKey : app.geminiApiKey,
              (v) => app.aiProvider == 'groq'
                  ? app.setGroqApiKey(v)
                  : app.setGeminiApiKey(v),
              textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String> onSave,
    Color textMuted,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            value.isEmpty ? '$label غير مضبوط' : '$label مضبوط',
            style: TextStyle(color: textMuted, fontSize: 12),
          ),
        ),
        TextButton.icon(
          onPressed: () => _showKeyDialog(context, label, value, onSave),
          icon: const Icon(LucideIcons.keyRound, size: 14),
          label: const Text('تعديل'),
        ),
      ],
    );
  }

  void _showKeyDialog(
    BuildContext context,
    String title,
    String initialValue,
    ValueChanged<String> onSave,
  ) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, obscureText: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

// ─── DEVELOPER DASHBOARD VIEW (ADMIN CONTROL PANEL UPGRADE) ─────────────────

class DeveloperDashboardView extends StatefulWidget {
  final VoidCallback onBack;
  const DeveloperDashboardView({super.key, required this.onBack});
  @override
  State<DeveloperDashboardView> createState() => _DeveloperDashboardViewState();
}

class _DeveloperDashboardViewState extends State<DeveloperDashboardView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _adminTabsScrollController = ScrollController();
  int _adminTabIndex = 0;

  @override
  void dispose() {
    _adminTabsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isDark = app.isDarkMode;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final surfaceAlt = isDark ? const Color(0xFF1E293B) : Colors.white;
    final panelBorder = isDark ? const Color(0xFF334155) : Colors.grey.shade300;

    final tabContent = switch (_adminTabIndex) {
      0 => _buildAdminCard(
          surfaceAlt,
          panelBorder,
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(12),
            child: _buildDetailedStats(surfaceAlt, panelBorder),
          ),
        ),
      1 => _buildAdminCard(
          surfaceAlt,
          panelBorder,
          _buildUserManagementList(),
        ),
      2 => _buildAdminCard(
          surfaceAlt,
          panelBorder,
          _buildBannedDevicesList(),
        ),
      3 => _buildAdminCard(
          surfaceAlt,
          panelBorder,
          _buildActiveBundlesList(app),
        ),
      4 => _buildAdminCard(
          surfaceAlt,
          panelBorder,
          _buildActiveSessionsList(app),
        ),
      5 => _buildAdminCard(
          surfaceAlt,
          panelBorder,
          _buildAnnouncementsList(),
        ),
      _ => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Header ─────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: Icon(
                    LucideIcons.arrowRight,
                    color: textPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'لوحة تحكم المشرف',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () => _modernUserDialog(context),
              icon: const Icon(LucideIcons.userPlus, size: 14),
              label: const Text(
                'مستخدم جديد',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildAdminChoiceChip('الإحصائيات', LucideIcons.barChart3, 0),
              _buildAdminChoiceChip('المستخدمين', LucideIcons.users, 1),
              _buildAdminChoiceChip('المحظورين', LucideIcons.ban, 2),
              _buildAdminChoiceChip('الحزم', LucideIcons.layers, 3),
              _buildAdminChoiceChip('الدروس', LucideIcons.radio, 4),
              _buildAdminChoiceChip('الإشعارات', LucideIcons.bell, 5),
            ],
          ),
        ),
          const SizedBox(height: 12),
          Expanded(child: tabContent),
      ],
    );

    }

    Widget _buildAdminChoiceChip(String label, IconData icon, int index) {
      final isSelected = _adminTabIndex == index;
      return ChoiceChip(
          selected: isSelected,
          onSelected: (_) => setState(() => _adminTabIndex = index),
          avatar: Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.white : Colors.blueGrey,
          ),
          label: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.blueGrey,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          selectedColor: const Color(0xFF3B82F6),
          backgroundColor: Colors.blueGrey.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
    }

  Widget _buildAdminSectionHeader(
    String title,
    IconData icon, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildClearButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const Icon(LucideIcons.trash2, size: 12, color: Colors.redAccent),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard(Color bg, Color border, Widget child) {
    return Card(
      elevation: 0,
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  // ─── Statistics Grid ──────────────────────────────────────────────────────

  Widget _buildDetailedStats(Color surface, Color border) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('sync_sessions').snapshots(),
          builder: (context, sessionSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('master_sessions').snapshots(),
              builder: (context, masterSnap) {
                if (!userSnap.hasData ||
                    !sessionSnap.hasData ||
                    !masterSnap.hasData) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final users = userSnap.data!.docs;
                final sessions = sessionSnap.data!.docs.length;
                final bundles = masterSnap.data!.docs.length;

                int admins = 0;
                int lecturers = 0;
                for (var u in users) {
                  final data = u.data() as Map<String, dynamic>?;
                  if (data != null) {
                    final r = data['role']?.toString().toLowerCase();
                    if (r == 'developer')
                      admins++;
                    else if (r == 'lecturer')
                      lecturers++;
                  }
                }
                int students = users.length - admins - lecturers;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.2,
                  children: [
                    _buildStatItem(
                      'المشرفين',
                      admins.toString(),
                      LucideIcons.shieldCheck,
                      Colors.amber,
                      surface,
                      border,
                    ),
                    _buildStatItem(
                      'المحاضرين',
                      lecturers.toString(),
                      LucideIcons.graduationCap,
                      Colors.purple,
                      surface,
                      border,
                    ),
                    _buildStatItem(
                      'الطلاب',
                      students.toString(),
                      LucideIcons.users,
                      Colors.blue,
                      surface,
                      border,
                    ),
                    _buildStatItem(
                      'الدروس النشطة',
                      sessions.toString(),
                      LucideIcons.activity,
                      Colors.green,
                      surface,
                      border,
                    ),
                    _buildStatItem(
                      'إجمالي الحزم',
                      bundles.toString(),
                      LucideIcons.layers,
                      Colors.orange,
                      surface,
                      border,
                    ),
                    _buildStatItem(
                      'إجمالي المسجلين',
                      users.length.toString(),
                      LucideIcons.database,
                      Colors.teal,
                      surface,
                      border,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatItem(
    String t,
    String v,
    IconData i,
    Color c,
    Color s,
    Color b,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: s,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: b),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(i, size: 18, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  v,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                Text(
                  t,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Logic Implementation Methods ─────────────────────────────────────────

  Widget _buildUserManagementList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState('لا يوجد مستخدمين مسجلين');

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          itemBuilder: (context, index) {
            final user = docs[index];
            final data = user.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'member';
            final hwId = (data['hardwareId'] ?? "").toString();

            Color roleColor = role == 'developer'
                ? Colors.amber
                : (role == 'lecturer' ? Colors.purple : Colors.blue);
            IconData roleIcon = role == 'developer'
                ? LucideIcons.shieldCheck
                : (role == 'lecturer'
                      ? LucideIcons.graduationCap
                      : LucideIcons.user);

            final displayName = data['displayName'] as String? ?? '';
            final username = data['username'] as String? ?? 'User';
            final appVersion = (data['appVersion'] ?? '').toString();

            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: roleColor.withOpacity(0.15),
                child: Icon(roleIcon, size: 16, color: roleColor),
              ),
              title: Text(
                displayName.isNotEmpty ? displayName : username,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@$username • ${user.id.substring(0, 8)}...',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  Text(
                    hwId.isNotEmpty ? 'الجهاز مرتبط ✅' : 'الجهاز حر ❌',
                    style: TextStyle(
                      fontSize: 10,
                      color: hwId.isNotEmpty ? Colors.green : Colors.redAccent,
                    ),
                  ),
                  Text(
                    'الإصدار: ${appVersion.isEmpty ? "-" : appVersion}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hwId.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        LucideIcons.refreshCw,
                        size: 16,
                        color: Colors.blue,
                      ),
                      tooltip: 'تصفير الجهاز',
                      onPressed: () => _firestore
                          .collection('users')
                          .doc(user.id)
                          .update({'hardwareId': ''}),
                    ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.edit,
                      size: 16,
                      color: Colors.orange,
                    ),
                    tooltip: 'تعديل المستخدم',
                    onPressed: () {
                      debugPrint('👤 Loading displayName for user: ${user.id}');
                      _modernUserDialog(
                        context,
                        id: user.id,
                        currentName: data['username'],
                        currentDisplayName: data['displayName'],
                        currentRole: role,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.trash2,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'حذف المستخدم',
                    onPressed: () =>
                        _confirmDelete('users', user.id, 'المستخدم'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBannedDevicesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('blacklisted_devices').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState('لا توجد أجهزة محظورة');

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.red,
                child: Icon(
                  LucideIcons.smartphone,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              title: Text(
                data['hardwareId'] ?? docs[index].id,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              subtitle: Text(
                'المستخدم المحظور: ${data['username'] ?? 'مجهول'}',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.withOpacity(0.1),
                  foregroundColor: Colors.green,
                ),
                onPressed: () => _firestore
                    .collection('blacklisted_devices')
                    .doc(docs[index].id)
                    .delete(),
                child: const Text(
                  'فك الحظر',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveBundlesList(AppProvider app) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('master_sessions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState('لا توجد حزم نشطة');

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final files = data['bundle'] as List? ?? [];
            final bool isLocked = data['isLocked'] as bool? ?? false;

            return ExpansionTile(
              dense: true,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isLocked ? Colors.red : Colors.orange).withOpacity(
                    0.1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.package,
                  size: 18,
                  color: isLocked ? Colors.red : Colors.orange,
                ),
              ),
              title: Text(
                data['displayName'] ?? 'حزمة: ${data['masterCode'] ?? doc.id}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'المنشئ: ${data['ownerName'] ?? data['createdBy'] ?? 'غير معروف'}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isLocked ? LucideIcons.unlock : LucideIcons.lock,
                      size: 16,
                      color: isLocked ? Colors.green : Colors.red,
                    ),
                    onPressed: () => app.syncService.toggleMasterBundleLock(
                      doc.id,
                      !isLocked,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.trash2,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                    onPressed: () =>
                        _confirmDelete('master_sessions', doc.id, 'الحزمة'),
                  ),
                ],
              ),
              children: files
                  .map(
                    (f) => ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      title: Text(
                        f['name'] ?? 'Unnamed',
                        style: const TextStyle(fontSize: 11),
                      ),
                      leading: const Icon(LucideIcons.fileText, size: 14),
                    ),
                  )
                  .toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveSessionsList(AppProvider app) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('sync_sessions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState('لا توجد دروس حالية');

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final parts = data['participants'] as List? ?? [];
            return ExpansionTile(
              dense: true,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.presentation,
                  size: 18,
                  color: Colors.blue,
                ),
              ),
              title: Text(
                data['displayName'] ?? 'درس: ${doc.id}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'المنشئ: ${data['ownerName'] ?? data['createdBy'] ?? 'غير معروف'} • الطلاب: ${parts.length}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              trailing: IconButton(
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 16,
                  color: Colors.redAccent,
                ),
                onPressed: () =>
                    _confirmDelete('sync_sessions', doc.id, 'الجلسة'),
              ),
              children: parts.map((p) {
                final uid = p is Map ? p['uid'] : "";
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(LucideIcons.user, size: 14),
                  title: Text(
                    p is Map ? p['username'] : p.toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () =>
                        app.syncService.kickParticipant(doc.id, uid),
                    child: const Text(
                      'طرد',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildAnnouncementsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('announcements').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState('لا توجد إشعارات عامة');

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.bellRing,
                  color: Colors.orange,
                  size: 18,
                ),
              ),
              title: Text(
                data['title'] ?? 'بدون عنوان',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              subtitle: Text(
                data['content'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
              trailing: IconButton(
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 16,
                  color: Colors.redAccent,
                ),
                onPressed: () =>
                    _confirmDelete('announcements', docs[index].id, 'الإشعار'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.folderOpen,
              size: 40,
              color: Colors.grey.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              msg,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Modal Dialogs & Helpers ──────────────────────────────────────────────

  void _modernUserDialog(
    BuildContext context, {
    String? id,
    String? currentName,
    String? currentDisplayName,
    String? currentRole,
  }) {
    final nameCtrl = TextEditingController(text: currentName);
    final dispCtrl = TextEditingController(text: currentDisplayName);
    String role = currentRole ?? 'member';
    final isEdit = id != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'تعديل بيانات المستخدم' : 'إضافة مستخدم جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'اسم المستخدم (المعرف)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dispCtrl,
              decoration: InputDecoration(
                labelText: 'الاسم المستعار (العرض)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: role,
              decoration: InputDecoration(
                labelText: 'الصلاحية',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'member', child: Text('طالب')),
                DropdownMenuItem(value: 'lecturer', child: Text('محاضر')),
                DropdownMenuItem(
                  value: 'developer',
                  child: Text('مشرف (مطور)'),
                ),
              ],
              onChanged: (v) => role = v!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final uname = nameCtrl.text.trim();
              final dname = dispCtrl.text.trim();
              if (uname.isEmpty) return;

              if (isEdit) {
                debugPrint('👤 Updating displayName for user: $id');
                await _firestore.collection('users').doc(id).update({
                  'username': uname,
                  'displayName': dname,
                  'role': role,
                });
              } else {
                await _firestore.collection('users').add({
                  'username': uname,
                  'displayName': dname,
                  'role': role,
                  'hardwareId': '',
                  'createdAt': FieldValue.serverTimestamp(),
                });
              }
              if (context.mounted) Navigator.pop(ctx);
            },
            child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String c, String id, String t) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('حذف $t'),
        content: const Text('هل أنت متأكد؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (conf == true) await _firestore.collection(c).doc(id).delete();
  }

  Future<void> _confirmWipe(BuildContext ctx, String col, String t) async {
    final conf = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('مسح كافة $t؟'),
        content: Text('سيتم مسح جميع بيانات $t بالكامل. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تأكيد المسح'),
          ),
        ],
      ),
    );
    if (conf == true) {
      final snap = await _firestore.collection(col).get();
      for (var d in snap.docs) {
        await d.reference.delete();
      }
    }
  }
}
