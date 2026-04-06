import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

  final TextEditingController _joinCodeController = TextEditingController();
  bool _isJoining = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _joinCodeController.dispose();
    super.dispose();
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
    final panelBorder = isDark
        ? const Color(0xFF334155)
        : scheme.outlineVariant;
    final textPrimary = isDark ? Colors.white : scheme.onSurface;
    final textMuted = isDark
        ? const Color(0xFF94A3B8)
        : scheme.onSurfaceVariant;
    final surfaceAlt = isDark
        ? const Color(0xFF1E293B)
        : scheme.surfaceContainerHighest;

    return Container(
      width: 450,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.settings,
                          color: textPrimary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'الإعدادات العامة',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => app.toggleSettings(false),
                      icon: Icon(LucideIcons.x, color: textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: ListView(
                    children: [
                      _buildSectionHeader(
                        'المظهر والنظام',
                        LucideIcons.palette,
                        textMuted,
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsCard(surfaceAlt, panelBorder, [
                        _buildToggleTile(
                          icon: isDark ? LucideIcons.sun : LucideIcons.moon,
                          label: isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
                          value: isDark,
                          onChanged: (_) => app.toggleDarkMode(),
                          textPrimary: textPrimary,
                        ),
                      ]),
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                        'إعدادات الذكاء الاصطناعي',
                        LucideIcons.bot,
                        textMuted,
                      ),
                      const SizedBox(height: 12),
                      _buildAiSettingsContent(
                        context,
                        app,
                        surfaceAlt,
                        panelBorder,
                        textPrimary,
                        textMuted,
                      ),

                      if (app.currentUser?.role == 'lecturer' ||
                          app.currentUser?.role == 'developer') ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader(
                          'أدوات المحاضر: إنشاء حزمة',
                          LucideIcons.graduationCap,
                          textMuted,
                        ),
                        const SizedBox(height: 12),
                        _buildMasterBundleCreator(
                          app,
                          surfaceAlt,
                          panelBorder,
                          textPrimary,
                          textMuted,
                          isDark,
                        ),

                        const SizedBox(height: 24),
                        _buildSectionHeader(
                          'سجل الحزم السابقة وإدارتها',
                          LucideIcons.history,
                          textMuted,
                        ),
                        const SizedBox(height: 12),
                        _buildMasterBundleHistory(
                          app,
                          surfaceAlt,
                          panelBorder,
                          textPrimary,
                          textMuted,
                        ),
                      ],

                      if (app.currentUser?.role != 'lecturer') ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader(
                          'أدوات الطالب',
                          LucideIcons.userCheck,
                          textMuted,
                        ),
                        const SizedBox(height: 12),
                        _buildCompactJoinCard(
                          context,
                          app,
                          surfaceAlt,
                          panelBorder,
                          textPrimary,
                          textMuted,
                        ),
                      ],

                      if (app.currentUser?.role == 'developer') ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader(
                          'خيارات المطور المتقدمة',
                          LucideIcons.code,
                          textMuted,
                        ),
                        const SizedBox(height: 12),
                        _buildSettingsCard(surfaceAlt, panelBorder, [
                          _buildActionTile(
                            icon: LucideIcons.shieldCheck,
                            label: 'إدارة النظام (Dashboard)',
                            onTap: () =>
                                setState(() => _showDevDashboard = true),
                            textPrimary: textPrimary,
                          ),
                        ]),
                      ],
                      const SizedBox(height: 32),
                      _buildLogoutButton(context, app),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isDark = app.isDarkMode;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final surfaceAlt = isDark ? const Color(0xFF1E293B) : Colors.white;
    final panelBorder = isDark ? const Color(0xFF334155) : Colors.grey.shade300;

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
        const SizedBox(height: 24),

        // ─── Main Dashboard Content ─────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            physics: const BouncingScrollPhysics(),
            children: [
              _buildAdminSectionHeader(
                'إحصائيات النظام الشاملة',
                LucideIcons.barChart3,
              ),
              _buildDetailedStats(surfaceAlt, panelBorder),

              const SizedBox(height: 24),
              _buildAdminSectionHeader('إدارة المستخدمين', LucideIcons.users),
              _buildAdminCard(
                surfaceAlt,
                panelBorder,
                _buildUserManagementList(),
              ),

              const SizedBox(height: 24),
              _buildAdminSectionHeader('الأجهزة المحظورة', LucideIcons.ban),
              _buildAdminCard(
                surfaceAlt,
                panelBorder,
                _buildBannedDevicesList(),
              ),

              const SizedBox(height: 24),
              _buildAdminSectionHeader(
                'إدارة الحزم الدراسية (Master Bundles)',
                LucideIcons.layers,
                trailing: _buildClearButton(
                  'مسح الكل',
                  () => _confirmWipe(
                    context,
                    'master_sessions',
                    'الحزم الدراسية',
                  ),
                ),
              ),
              _buildAdminCard(
                surfaceAlt,
                panelBorder,
                _buildActiveBundlesList(app),
              ),

              const SizedBox(height: 24),
              _buildAdminSectionHeader(
                'الدروس والنشاط اللحظي (Sessions)',
                LucideIcons.radio,
                trailing: _buildClearButton(
                  'مسح الكل',
                  () => _confirmWipe(context, 'sync_sessions', 'الدروس'),
                ),
              ),
              _buildAdminCard(
                surfaceAlt,
                panelBorder,
                _buildActiveSessionsList(app),
              ),

              const SizedBox(height: 24),
              _buildAdminSectionHeader(
                'إدارة الإشعارات العامة',
                LucideIcons.bell,
              ),
              _buildAdminCard(
                surfaceAlt,
                panelBorder,
                _buildAnnouncementsList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Modular UI Components ────────────────────────────────────────────────

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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
