import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../screens/admin/dev_dashboard.dart';
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

      final masterCode = await app.syncService.createMasterBundle(user.username, bundle);
      setState(() => _generatedMasterCode = masterCode);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.settings, color: textPrimary, size: 24),
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
                _buildSectionHeader('المظهر والنظام', LucideIcons.palette, textMuted),
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
                _buildSectionHeader('إعدادات الذكاء الاصطناعي', LucideIcons.bot, textMuted),
                const SizedBox(height: 12),
                _buildAiSettingsContent(context, app, surfaceAlt, panelBorder, textPrimary, textMuted),

                // Phase 13.1: Inline Master Bundle Creator
                if (app.currentUser?.role == 'lecturer' || app.currentUser?.role == 'developer') ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('أدوات المحاضر: إنشاء حزمة', LucideIcons.graduationCap, textMuted),
                  const SizedBox(height: 12),
                  _buildMasterBundleCreator(app, surfaceAlt, panelBorder, textPrimary, textMuted, isDark),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('سجل الحزم السابقة', LucideIcons.history, textMuted),
                  const SizedBox(height: 12),
                  _buildMasterBundleHistory(app, surfaceAlt, panelBorder, textPrimary, textMuted),
                ],

                // Student Tools (Join Master Bundle)
                if (app.currentUser?.role != 'lecturer') ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('أدوات الطالب', LucideIcons.userCheck, textMuted),
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
                  _buildSectionHeader('خيارات المطور', LucideIcons.code, textMuted),
                  const SizedBox(height: 12),
                  _buildSettingsCard(surfaceAlt, panelBorder, [
                    _buildActionTile(
                      icon: LucideIcons.users,
                      label: 'لوحة التحكم للمطور (إدارة المستخدمين)',
                      onTap: () {
                        app.toggleSettings(false);
                         Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DevDashboard()),
                        );
                      },
                      textPrimary: textPrimary,
                    ),
                  ]),
                ],
                const SizedBox(height: 32),
                // Logout Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
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
                    },
                    icon: const Icon(LucideIcons.logOut, size: 18, color: Color(0xFFDC2626)),
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

  void _manageBannedUsers(BuildContext context, AppProvider app, String bundleId, List<String> activators, List<String> bannedUsernames) {
    final controller = TextEditingController();
    final allStudents = <String>{...activators, ...bannedUsernames}.toList()..sort();

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
                        decoration: const InputDecoration(hintText: 'حظر مستخدم يدوي (اسم المستخدم)...', isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.userPlus, color: Colors.blue),
                      onPressed: () async {
                        final username = controller.text.trim();
                        if (username.isNotEmpty) {
                          await app.syncService.banUserFromMasterBundle(bundleId, username);
                          controller.clear();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة الحظر')));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('قائمة الطلاب المتفاعلين والمحظورين:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (allStudents.isEmpty)
                  const Text('لا يوجد طلاب مسجلون حالياً.', style: TextStyle(color: Colors.grey, fontSize: 11))
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
                          title: Text(username, style: TextStyle(fontSize: 13, color: isBanned ? Colors.red : null, decoration: isBanned ? TextDecoration.lineThrough : null)),
                          trailing: IconButton(
                            icon: Icon(isBanned ? LucideIcons.userCheck : LucideIcons.userX, color: isBanned ? Colors.green : Colors.red, size: 18),
                            onPressed: () async {
                               if (isBanned) {
                                 await app.syncService.unbanUserFromMasterBundle(bundleId, username);
                               } else {
                                 await app.syncService.banUserFromMasterBundle(bundleId, username);
                               }
                               Navigator.pop(ctx);
                               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isBanned ? 'تم فك الحظر' : 'تم الحظر شمولياً')));
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterBundleHistory(AppProvider app, Color surface, Color border, Color text, Color muted) {
    return _buildSettingsCard(surface, border, [
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: app.syncService.watchMasterBundlesByOwner(app.currentUser?.username ?? ''),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
          final bundles = snapshot.data!;
          if (bundles.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text('لا توجد حزم سابقة.', style: TextStyle(color: muted, fontSize: 13)));

          return Column(
            children: bundles.map((data) {
              final files = data['bundle'] as List? ?? [];
              final bool isLocked = data['isLocked'] as bool? ?? false;

              return ExpansionTile(
                title: Row(
                  children: [
                    Text(data['masterCode'], style: TextStyle(color: isLocked ? Colors.red : text, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    if (isLocked) ...[
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.lock, size: 14, color: Colors.red),
                    ],
                  ],
                ),
                subtitle: Text('عدد الملفات: ${files.length} • المحظورين: ${(data['bannedUsernames'] as List? ?? []).length}', style: TextStyle(color: muted, fontSize: 11)),
                leading: Icon(LucideIcons.package, size: 18, color: isLocked ? Colors.red : Colors.orange),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(isLocked ? LucideIcons.unlock : LucideIcons.lock, size: 16, color: isLocked ? Colors.green : Colors.red),
                      tooltip: isLocked ? 'فتح الاستخدام' : 'قفل الاستخدام',
                      onPressed: () => app.syncService.toggleMasterBundleLock(data['id'], !isLocked),
                    ),
                    IconButton(
                        icon: const Icon(LucideIcons.userX, size: 16, color: Colors.amber),
                        tooltip: 'إدارة المحظورين',
                        onPressed: () => _manageBannedUsers(
                              context,
                              app,
                              data['id'],
                              List<String>.from(data['activators'] ?? []),
                              List<String>.from(data['bannedUsernames'] ?? []),
                            )),
                    IconButton(
                      icon: const Icon(LucideIcons.copy, size: 16, color: Colors.blue),
                      onPressed: () {
                         Clipboard.setData(ClipboardData(text: data['masterCode']));
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الكود')));
                      },
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('حذف الحزمة؟'),
                            content: const Text('هل تريد حذف هذه الحزمة نهائياً؟'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await FirebaseFirestore.instance.collection('master_sessions').doc(data['id']).delete();
                        }
                      },
                    ),
                  ],
                ),
                children: files.map((f) => ListTile(
                  dense: true,
                  title: Text(f['name'] ?? 'Unnamed', style: TextStyle(color: text, fontSize: 11)),
                  leading: const Icon(LucideIcons.fileText, size: 14),
                )).toList(),
              );
            }).toList(),
          );
        },
      ),
    ]);
  }

  Widget _buildMasterBundleCreator(AppProvider app, Color surface, Color border, Color text, Color muted, bool isDark) {
    return _buildSettingsCard(surface, border, [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ...app.classes.map((cls) {
               final bool allSelected = cls.pdfs.isNotEmpty && cls.pdfs.every((p) => p.fileHash != null && _selectedHashes.contains(p.fileHash));
               return ExpansionTile(
                 title: Text(cls.name, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.bold)),
                 leading: const Icon(LucideIcons.folder, size: 18, color: Colors.blue),
                 trailing: Checkbox(
                   value: allSelected,
                   onChanged: (val) {
                     setState(() {
                       for (var p in cls.pdfs) {
                         if (p.fileHash != null && p.fileHash!.isNotEmpty) {
                           if (val == true) _selectedHashes.add(p.fileHash!);
                           else _selectedHashes.remove(p.fileHash!);
                         }
                       }
                     });
                   },
                 ),
                 children: cls.pdfs.map((pdf) {
                   final bool hasHash = pdf.fileHash != null && pdf.fileHash!.isNotEmpty;
                   final bool isSel = hasHash && _selectedHashes.contains(pdf.fileHash);
                   return CheckboxListTile(
                     value: isSel,
                     onChanged: !hasHash ? null : (val) {
                       setState(() {
                         if (val == true) _selectedHashes.add(pdf.fileHash!);
                         else _selectedHashes.remove(pdf.fileHash!);
                       });
                     },
                     title: Text(pdf.name, style: TextStyle(color: hasHash ? text : muted, fontSize: 12)),
                     subtitle: !hasHash ? const Text('بانتظار حساب المعرف...', style: TextStyle(fontSize: 10, color: Colors.red)) : null,
                     controlAffinity: ListTileControlAffinity.leading,
                   );
                 }).toList(),
               );
            }).toList(),

            const SizedBox(height: 16),
            if (_generatedMasterCode != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('كود الحزمة: ', style: TextStyle(color: text, fontSize: 13)),
                    Text(_generatedMasterCode!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green, letterSpacing: 2)),
                    IconButton(
                      icon: const Icon(LucideIcons.copy, size: 16, color: Colors.green),
                      onPressed: () {
                         Clipboard.setData(ClipboardData(text: _generatedMasterCode!));
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الكود')));
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
                onPressed: _isGenerating ? null : () => _generateMasterBundle(app),
                icon: _isGenerating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(LucideIcons.plus, size: 18),
                label: Text(_isGenerating ? 'جاري الإنشاء...' : 'إنشاء حزمة دراسية', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 12)),
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
      title: Text(label, style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
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
      title: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
      trailing: Icon(LucideIcons.chevronRight, size: 16, color: color.withOpacity(0.5)),
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
    const groqModels = ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant', 'mixtral-8x7b-32768'];

    final selectedModel = app.aiProvider == 'groq' ? app.groqModel : app.geminiModel;
    final modelItems = (app.aiProvider == 'groq' ? groqModels : geminiModels)
        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
        .toList();

    InputDecoration decor(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: panelBorder)),
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
            decoration: decor('النموذج المختير'),
            items: modelItems,
            onChanged: (v) {
              if (v == null) return;
              if (app.aiProvider == 'groq') app.setGroqModel(v);
              else app.setGeminiModel(v);
            },
          ),
          const SizedBox(height: 12),
           _buildKeyRow(
            context,
            app.aiProvider == 'groq' ? 'Groq API Key' : 'Gemini API Key',
            app.aiProvider == 'groq' ? app.groqApiKey : app.geminiApiKey,
            (v) => app.aiProvider == 'groq' ? app.setGroqApiKey(v) : app.setGeminiApiKey(v),
            textMuted,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildKeyRow(BuildContext context, String label, String value, ValueChanged<String> onSave, Color textMuted) {
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

  void _showKeyDialog(BuildContext context, String title, String initialValue, ValueChanged<String> onSave) {
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () { onSave(controller.text); Navigator.pop(ctx); }, child: const Text('حفظ')),
        ],
      ),
    );
  }
}
