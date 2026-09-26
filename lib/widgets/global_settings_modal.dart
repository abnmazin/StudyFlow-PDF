import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../screens/auth/login_screen.dart';
import '../services/mcp_client_service.dart';
import '../utils/sync_naming_utils.dart';
import 'developer_dashboard_v.dart';

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

  bool _mcpChecking = false;
  bool _mcpNodeInstalled = false;
  bool _mcpAuthenticated = false;

  final TextEditingController _joinCodeController = TextEditingController();
  bool _isJoining = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final app = context.read<AppProvider>();
      if (app.aiProvider == 'mcp') await _checkMcpStatus();
    });
  }

  @override
  void dispose() {
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _checkMcpStatus() async {
    setState(() => _mcpChecking = true);
    bool nodeOk = false;
    bool auth = false;
    try {
      nodeOk = await McpClientService.instance.isNodeAvailable;
      if (nodeOk) {
        final health = await McpClientService.instance.getHealth();
        final data = health['data'];
        if (data is Map<String, dynamic>) {
          auth = data['authenticated'] == true;
        }
      }
    } catch (_) {
      // Server may be off or crashing; still report node availability.
    }
    if (!mounted) return;
    setState(() {
      _mcpNodeInstalled = nodeOk;
      _mcpAuthenticated = auth;
      _mcpChecking = false;
    });
  }

  Future<void> _connectMcp() async {
    setState(() => _mcpChecking = true);
    try {
      await McpClientService.instance.setupAuth();
      await _checkMcpStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل ربط حساب MCP: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _mcpChecking = false);
    }
  }

  Future<void> _disconnectMcp() async {
    await McpClientService.instance.stop();
    if (mounted) await _checkMcpStatus();
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

  Future<void> _showBundleNameDialog(AppProvider app) async {
    if (_selectedHashes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد ملفاً واحداً على الأقل.')),
      );
      return;
    }

    // Attempt to guess a good name from the first selected file
    String initialName = SyncNamingUtils.bundleFallback;
    for (var cls in app.classes) {
      final firstMatch = cls.pdfs
          .where((p) => _selectedHashes.contains(p.fileHash))
          .firstOrNull;
      if (firstMatch != null) {
        initialName = SyncNamingUtils.generateSmartName(
          firstMatch.name,
          isBundle: true,
        );
        break;
      }
    }

    final nameCtrl = TextEditingController(text: initialName);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنشاء حزمة دراسية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل اسماً للحزمة ليظهر للطلاب:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم الحزمة',
                hintText: 'مثال: حزمة مراجعة الميد',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final val = nameCtrl.text.trim();
              Navigator.pop(ctx);
              _generateMasterBundle(app, val.isEmpty ? initialName : val);
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateMasterBundle(
    AppProvider app,
    String displayName,
  ) async {
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
              displayName: pdf
                  .name, // Lessons inside bundle use their PDF name as display name
            );
            if (code != null) {
              bundle.add({
                'hash': pdf.fileHash,
                'sessionCode': code,
                'name': pdf.name,
              });
            }
          }
        }
      }
      final masterCode = await app.syncService.createMasterBundle(
        user.username,
        bundle,
        displayName: displayName,
      );

      // NEW: Auto-link the generated bundle for the Lecturer so they don't have to manually 'Start Broadcast' later
      app.linkMasterBundle(bundle);

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

                      if (app.currentUser?.isLecturer ?? false) ...[
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

                      if (!(app.currentUser?.isLecturer ?? false)) ...[
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

                      if (app.currentUser?.role == 'lecturer' && !app.currentUser!.isAdmin) ...[
                        const SizedBox(height: 24),
                        _buildSectionHeader(
                          'الانضمام إلى حزمة',
                          LucideIcons.link2,
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

                      if (app.currentUser?.isAdmin ?? false) ...[
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
      StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('sync_sessions').snapshots(),
        builder: (context, sessionSnap) {
          if (sessionSnap.hasError) {
            debugPrint(
              '⚠️ [Settings] sync session stream failed: ${sessionSnap.error}',
            );
          }
          final activeCodes = sessionSnap.hasData
              ? sessionSnap.data!.docs.map((d) => d.id).toSet()
              : <String>{};

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: app.syncService.watchMasterBundlesByOwner(
              app.currentUser?.username ?? '',
            ),
            builder: (context, snapshot) {
              // A stream that is denied by firestore.rules reports hasData
              // false forever, exactly like one that is still loading, so
              // checking hasData alone turned a permission error into a
              // spinner that never resolved and said nothing about why.
              if (snapshot.hasError) {
                debugPrint(
                  '⚠️ [Settings] master bundle stream failed: ${snapshot.error}',
                );
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'تعذّر تحميل الحزم: ${snapshot.error}',
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 13,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                );
              }

              final allBundles = snapshot.data!;

              // 1. Gather all local hashes for existence check
              final localHashes = <String>{};
              for (var cls in app.classes) {
                for (var pdf in cls.pdfs) {
                  if (pdf.fileHash != null) localHashes.add(pdf.fileHash!);
                }
              }

              // 2. Filter bundles
              final List<Map<String, dynamic>> activeBundles = [];
              final Map<String, List<dynamic>> filteredFilesMap = {};

              for (var data in allBundles) {
                final rawFiles = data['bundle'] as List? ?? [];
                final filteredFiles = rawFiles.where((f) {
                  if (f is! Map) return false;
                  final code = f['sessionCode']?.toString();
                  return code != null && activeCodes.contains(code);
                }).toList();

                if (filteredFiles.isNotEmpty) {
                  activeBundles.add(data);
                  filteredFilesMap[data['id'] ?? data['masterCode']] =
                      filteredFiles;
                }
              }

              if (activeBundles.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'لا توجد حزم نشطة حالياً.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                );
              }

              return Column(
                children: activeBundles.map((data) {
                  final docId = data['id'] ?? data['masterCode'];
                  final files = filteredFilesMap[docId] ?? [];
                  final bool isLocked = data['isLocked'] as bool? ?? false;

                  int locallyPresentCount = 0;
                  for (var f in files) {
                    if (f is Map && localHashes.contains(f['hash'])) {
                      locallyPresentCount++;
                    }
                  }

                  return ExpansionTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            data['displayName'] ?? data['masterCode'],
                            style: TextStyle(
                              color: isLocked ? Colors.red : text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLocked) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            LucideIcons.lock,
                            size: 12,
                            color: Colors.red,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data['displayName'] != null)
                          Text(
                            'الكود: ${data['masterCode']}',
                            style: TextStyle(
                              color: muted,
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                        Row(
                          children: [
                            Text(
                              'المحاضر: ${data['ownerName'] ?? "..."}',
                              style: TextStyle(color: muted, fontSize: 10),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ملفات: ${files.length}',
                              style: TextStyle(color: muted, fontSize: 10),
                            ),
                            if (locallyPresentCount < files.length) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${files.length - locallyPresentCount} مفقود محلياً',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
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
                          onPressed: () => _confirmDelete(
                            'master_sessions',
                            docId,
                            'الحزمة',
                          ),
                          tooltip: 'حذف نهائي',
                        ),
                      ],
                    ),
                    children: files.map((f) {
                      final bool locallyExists =
                          f is Map && localHashes.contains(f['hash']);
                      return ListTile(
                        dense: true,
                        title: Text(
                          f['name'] ?? 'Unnamed',
                          style: TextStyle(
                            color: locallyExists
                                ? text
                                : muted.withOpacity(0.5),
                            fontSize: 11,
                            decoration: locallyExists
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        leading: Icon(
                          locallyExists
                              ? LucideIcons.fileText
                              : LucideIcons.fileX,
                          size: 14,
                          color: locallyExists
                              ? null
                              : Colors.red.withOpacity(0.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!locallyExists)
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Text(
                                  '(محذوف من Dashboard)',
                                  style: TextStyle(
                                    color: Colors.red.withOpacity(0.6),
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                f['sessionCode'] ?? 'بدون كود',
                                style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            if (f['sessionCode'] != null)
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.copy,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                                iconSize: 14,
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: f['sessionCode']),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم نسخ الكود!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              );
            },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withOpacity(0.9), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.14 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border.withOpacity(0.9)),
              ),
              child: TextField(
                controller: _joinCodeController,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: text,
                ),
                decoration: InputDecoration(
                  hintText: 'أدخل الكود',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: muted.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: _isJoining ? null : () => _joinMasterBundle(app),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: const Color(
                  0xFF2563EB,
                ).withOpacity(0.6),
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(60, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _isJoining
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('ربط', key: ValueKey('text')),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ─── الهيلبرز المتبقية (بدون تغيير) ──────────────────────────────────────────

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
                    : () => _showBundleNameDialog(app),
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
    const mcpModels = ['gemini-2.5 (personal)', 'gemini-2.0 (personal)'];
    final isMcp = app.aiProvider == 'mcp';
    final selectedModel = isMcp
        ? app.mcpModel
        : app.aiProvider == 'groq'
            ? app.groqModel
            : app.geminiModel;
    final modelOptions = isMcp
        ? mcpModels
        : app.aiProvider == 'groq'
            ? groqModels
            : geminiModels;

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                DropdownMenuItem(
                  value: 'mcp',
                  child: Text('Gemini (الحساب الشخصي)'),
                ),
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
              items: modelOptions
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => v == null
                  ? null
                  : isMcp
                        ? app.setMcpModel(v)
                        : app.aiProvider == 'groq'
                            ? app.setGroqModel(v)
                            : app.setGeminiModel(v),
            ),
            if (isMcp) ...[
              const SizedBox(height: 12),
              _buildMcpStatusCard(textMuted, panelBorder),
            ] else
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

  Widget _buildMcpStatusCard(Color textMuted, Color panelBorder) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_sync_outlined,
                size: 16,
                color: Color(0xFF3B82F6),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Gemini — الحساب الشخصي',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_mcpChecking)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _mcpNodeInstalled
                ? 'Node.js: متوفر'
                : 'Node.js: غير متوفر — ثبّت Node.js لاستخدام هذا المزود',
            style: TextStyle(
              color: _mcpNodeInstalled ? textMuted : Colors.redAccent,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            !_mcpNodeInstalled
                ? '—'
                : _mcpAuthenticated
                    ? 'الحساب: متصل'
                    : 'الحساب: غير متصل',
            style: TextStyle(
              color: _mcpAuthenticated
                  ? const Color(0xFF22C55E)
                  : Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _mcpChecking ? null : _disconnectMcp,
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('قطع الاتصال'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _mcpChecking ? null : _connectMcp,
                icon: const Icon(Icons.link, size: 16),
                label: const Text('ربط حساب Google'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
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
