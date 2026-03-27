import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../screens/auth/login_screen.dart';
import 'viewer_components/join_master_modal.dart';

class GlobalSettingsModal extends StatefulWidget {
  const GlobalSettingsModal({super.key});

  @override
  State<GlobalSettingsModal> createState() => _GlobalSettingsModalState();
}

class _GlobalSettingsModalState extends State<GlobalSettingsModal> {
  final Set<String> _selectedHashes = {};
  bool _isGenerating = false;
  String? _generatedMasterCode;

  // منطق التبديل للوحة المطور
  bool _showDevDashboard = false;

  Future<void> _generateMasterBundle(AppProvider app) async {
    if (_selectedHashes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء تحديد ملف واحد على الأقل.')),
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
            final sessionCode = await app.syncService.generateSessionCode(
              pdf.fileHash!,
              pdf.name,
              pdf.pageCount ?? 0,
              user.hardwareId,
              user.username,
              user.uid,
            );

            if (sessionCode != null) {
              bundle.add({
                'hash': pdf.fileHash,
                'sessionCode': sessionCode,
                'name': pdf.name,
              });
            }
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
                          'سجل الحزم السابقة',
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
                        _buildSettingsCard(surfaceAlt, panelBorder, [
                          _buildActionTile(
                            icon: LucideIcons.link2,
                            label: 'ربط حزمة دراسية (Master Bundle)',
                            onTap: () {
                              app.toggleSettings(false);
                              showDialog(
                                context: context,
                                builder: (context) => const JoinMasterModal(),
                              );
                            },
                            textPrimary: textPrimary,
                          ),
                        ]),
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
                            onTap: () {
                              setState(() => _showDevDashboard = true);
                            },
                            textPrimary: textPrimary,
                          ),
                        ]),
                      ],
                      const SizedBox(height: 32),
                      SizedBox(
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
                      ),
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
        content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
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
            child: const Text('تسجيل خروج'),
          ),
        ],
      ),
    );
  }

  // --- ميثودات مساعدة (Helper Widgets) ---

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
                'لا توجد حزم سابقة.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            );

          return Column(
            children: bundles.map((data) {
              final files = data['bundle'] as List? ?? [];
              final bool isLocked = data['isLocked'] as bool? ?? false;

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
                      const Icon(LucideIcons.lock, size: 14, color: Colors.red),
                    ],
                  ],
                ),
                subtitle: Text(
                  'عدد الملفات: ${files.length}',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                leading: Icon(
                  LucideIcons.package,
                  size: 18,
                  color: isLocked ? Colors.red : Colors.orange,
                ),
                trailing: IconButton(
                  icon: const Icon(
                    LucideIcons.copy,
                    size: 16,
                    color: Colors.blue,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: data['masterCode']));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ الكود')),
                    );
                  },
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
                      'كود الحزمة: ',
                      style: TextStyle(color: text, fontSize: 13),
                    ),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ الكود')),
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
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

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
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
  }

  Widget _buildSettingsCard(Color bg, Color border, List<Widget> children) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color textPrimary,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF3B82F6),
      title: Text(
        label,
        style: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      secondary: Icon(icon, size: 20, color: textPrimary.withOpacity(0.7)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDanger = false,
    required Color textPrimary,
  }) {
    final color = isDanger ? const Color(0xFFF87171) : textPrimary;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(LucideIcons.chevronLeft, size: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    );
  }

  Widget _buildAiSettingsContent(
    BuildContext context,
    AppProvider app,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    final isDark = app.isDarkMode;
    const geminiModels = ['gemini-2.5-flash', 'gemini-2.0-flash'];
    const groqModels = [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'mixtral-8x7b-32768',
    ];

    final selectedModel = app.aiProvider == 'groq'
        ? app.groqModel
        : app.geminiModel;
    final modelItems = (app.aiProvider == 'groq' ? groqModels : geminiModels)
        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
        .toList();

    InputDecoration decor(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: panelBorder),
      ),
    );

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
              decoration: decor('مزود الخدمة'),
              items: const [
                DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
                DropdownMenuItem(value: 'groq', child: Text('Groq')),
              ],
              onChanged: (v) => v != null ? app.setAiProvider(v) : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedModel,
              decoration: decor('النموذج المختار'),
              items: modelItems,
              onChanged: (v) {
                if (v == null) return;
                if (app.aiProvider == 'groq')
                  app.setGroqModel(v);
                else
                  app.setGeminiModel(v);
              },
            ),
            const SizedBox(height: 12),
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
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'أدخل المفتاح هنا...'),
        ),
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

// ─── DEVELOPER DASHBOARD VIEW (FULL VERSION) ───────────────────────────────

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
    final textMuted = isDark ? const Color(0xFF94A3B8) : Colors.black54;
    final surfaceAlt = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final panelBorder = isDark ? const Color(0xFF334155) : Colors.black12;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: Icon(LucideIcons.arrowRight, color: textPrimary, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              'مركز التحكم والإدارة للمطور',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildSectionHeader(
                'إحصائيات الأعضاء والصلاحيات',
                LucideIcons.barChart3,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildDetailedStats(surfaceAlt, panelBorder, isDark),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'الدروس والنشاط اللحظي (Sessions)',
                LucideIcons.radio,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildActiveSessionsList(surfaceAlt, panelBorder, isDark),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'إدارة الحزم الدراسية (Master Bundles)',
                LucideIcons.layers,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildActiveBundlesList(surfaceAlt, panelBorder, isDark),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'إدارة الإشعارات العامة',
                LucideIcons.bell,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildAnnouncementsList(surfaceAlt, panelBorder, isDark),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'إدارة قاعدة بيانات المستخدمين',
                LucideIcons.database,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildUserManagementList(surfaceAlt, panelBorder, isDark),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  // --- إحصائيات تفصيلية (Detailed Stats) ---
  Widget _buildDetailedStats(Color surface, Color border, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('sync_sessions').snapshots(),
          builder: (context, sessionSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('master_sessions').snapshots(),
              builder: (context, masterSnap) {
                final users = userSnap.data?.docs ?? [];
                final sessions = sessionSnap.data?.docs.length ?? 0;
                final bundles = masterSnap.data?.docs.length ?? 0;

                int admins = users
                    .where((u) => (u.data() as Map)['role'] == 'developer')
                    .length;
                int lecturers = users
                    .where((u) => (u.data() as Map)['role'] == 'lecturer')
                    .length;
                int students = users.length - admins - lecturers;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
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
                      'الدروس',
                      sessions.toString(),
                      LucideIcons.activity,
                      Colors.green,
                      surface,
                      border,
                    ),
                    _buildStatItem(
                      'الحزم',
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
                      Colors.blueGrey,
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
    String title,
    String value,
    IconData icon,
    Color color,
    Color surface,
    Color border,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- مراقبة الجلسات (Sessions Monitoring) ---
  Widget _buildActiveSessionsList(Color surface, Color border, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('sync_sessions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty)
          return _buildEmptyState(surface, 'لا توجد جلسات نشطة');

        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Column(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final participants = data['participants'] as List? ?? [];
              return ExpansionTile(
                dense: true,
                leading: const Icon(
                  LucideIcons.presentation,
                  size: 18,
                  color: Colors.blue,
                ),
                title: Text(
                  data['pdfName'] != null
                      ? 'درس: ${data['pdfName']} (${doc.id})'
                      : 'درس: ${doc.id}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'المالك: ${data['ownerName']} • طلاب متصلين: ${participants.length}',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: Colors.red,
                  ),
                  onPressed: () =>
                      _confirmDelete('sync_sessions', doc.id, 'الجلسة'),
                ),
                children: participants
                    .map(
                      (p) => ListTile(
                        dense: true,
                        leading: const Icon(LucideIcons.user, size: 12),
                        title: Text(
                          p is Map
                              ? (p['username'] ?? 'Unknown')
                              : p.toString(),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    )
                    .toList(),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // --- مراقبة الحزم (Bundles Monitoring) ---
  Widget _buildActiveBundlesList(Color surface, Color border, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('master_sessions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState(surface, 'لا توجد حزم نشطة');

        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Column(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final files = data['bundle'] as List? ?? [];
              return ExpansionTile(
                dense: true,
                leading: const Icon(
                  LucideIcons.package,
                  size: 18,
                  color: Colors.orange,
                ),
                title: Text(
                  'حزمة: ${data['masterCode'] ?? doc.id}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'المنشئ: ${data['ownerName']} • ملفات المنهج: ${files.length}',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: Colors.red,
                  ),
                  onPressed: () => _confirmDelete(
                    'master_sessions',
                    doc.id,
                    'الحزمة الدراسية',
                  ),
                ),
                children: files
                    .map(
                      (f) => ListTile(
                        dense: true,
                        leading: const Icon(LucideIcons.fileText, size: 12),
                        title: Text(
                          f['name'] ?? 'Unnamed',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    )
                    .toList(),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // --- إدارة الإشعارات (Announcements Monitoring) ---
  Widget _buildAnnouncementsList(Color surface, Color border, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('announcements').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty)
          return _buildEmptyState(surface, 'لا توجد إشعارات حالية');

        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Column(
            children: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return ListTile(
                dense: true,
                leading: const Icon(
                  LucideIcons.megaphone,
                  size: 18,
                  color: Colors.amber,
                ),
                title: Text(
                  data['title'] ?? 'بدون عنوان',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  data['content'] ?? '',
                  style: const TextStyle(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: Colors.red,
                  ),
                  onPressed: () =>
                      _confirmDelete('announcements', doc.id, 'الإشعار'),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // --- إدارة المستخدمين (User Management) ---
  Widget _buildUserManagementList(Color surface, Color border, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final docs = snapshot.data!.docs;

        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = docs[index];
              final data = user.data() as Map<String, dynamic>;
              final role = data['role'] ?? 'member';
              final isLinked = (data['hardwareId'] ?? '').toString().isNotEmpty;

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: _getRoleColor(role).withOpacity(0.1),
                  child: Icon(
                    _getRoleIcon(role),
                    size: 14,
                    color: _getRoleColor(role),
                  ),
                ),
                title: Text(
                  data['username'] ?? 'User',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  isLinked ? 'جهاز مرتبط ✅' : 'جهاز حر ❌',
                  style: TextStyle(
                    fontSize: 9,
                    color: isLinked ? Colors.green : Colors.red,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLinked)
                      IconButton(
                        icon: const Icon(LucideIcons.refreshCw, size: 14),
                        onPressed: () => _resetHardware(user.id),
                      ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      onPressed: () =>
                          _confirmDelete('users', user.id, 'المستخدم'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // --- Helpers & Logic ---
  Widget _buildEmptyState(Color surface, String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          msg,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    String collection,
    String docId,
    String itemType,
  ) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد حذف $itemType'),
        content: const Text(
          'هل أنت متأكد من حذف هذا العنصر نهائياً من قاعدة البيانات؟',
        ),
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تم حذف $itemType بنجاح')));
      }
    }
  }

  Color _getRoleColor(String role) {
    if (role == 'developer') return Colors.amber;
    if (role == 'lecturer') return Colors.purple;
    return Colors.blue;
  }

  IconData _getRoleIcon(String role) {
    if (role == 'developer') return LucideIcons.shieldCheck;
    if (role == 'lecturer') return LucideIcons.graduationCap;
    return LucideIcons.user;
  }

  Future<void> _resetHardware(String id) async =>
      await _firestore.collection('users').doc(id).update({'hardwareId': ''});
}
