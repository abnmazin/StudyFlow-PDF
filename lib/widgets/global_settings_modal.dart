import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../screens/admin/dev_dashboard.dart';
import '../screens/auth/login_screen.dart';

class GlobalSettingsModal extends StatelessWidget {
  const GlobalSettingsModal({super.key});

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
                const SizedBox(height: 24),
                _buildSectionHeader('أدوات التنظيف (المستند الحالي)', LucideIcons.trash2, textMuted),
                const SizedBox(height: 12),
                _buildSettingsCard(surfaceAlt, panelBorder, [
                  _buildActionTile(
                    icon: LucideIcons.eraser,
                    label: 'مسح كافة الملاحظات والرسومات',
                    onTap: () {
                      if (app.activePdf != null) {
                        _showCleanupDialog(context, app, app.activePdf!);
                      } else {
                        _showNoPdfError(context);
                      }
                    },
                    isDanger: true,
                    textPrimary: textPrimary,
                  ),
                  _buildDivider(panelBorder),
                  _buildActionTile(
                    icon: LucideIcons.trash2,
                    label: 'مسح شامل (كافة الملفات)',
                    onTap: () => _showGlobalCleanupDialog(context, app),
                    isDanger: true,
                    textPrimary: textPrimary,
                  ),
                ]),
                if (app.currentUser?.role == 'developer') ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('المزامنة اللحظية (للمطورين)', LucideIcons.radio, textMuted),
                  const SizedBox(height: 12),
                  _buildSettingsCard(surfaceAlt, panelBorder, [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(LucideIcons.activity, size: 18, color: textPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('طريقة مزامنة الرسم', style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                                Text('اختبر أداء مسار المزامنة (Stress Test)', style: TextStyle(color: textMuted, fontSize: 11)),
                              ],
                            ),
                          ),
                          DropdownButton<DrawingSyncStrategy>(
                            value: app.drawingSyncStrategy,
                            dropdownColor: surfaceAlt,
                            underline: const SizedBox(),
                            icon: Icon(LucideIcons.chevronDown, size: 16, color: textMuted),
                            style: TextStyle(color: textPrimary),
                            items: const [
                              DropdownMenuItem(value: DrawingSyncStrategy.disabled, child: Text('متوقف (يدوي)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: DrawingSyncStrategy.immediate, child: Text('مباشر (Immediate)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: DrawingSyncStrategy.buffered, child: Text('مؤجل (Buffered 5s)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: DrawingSyncStrategy.isolate, child: Text('معزول (Compute)', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (val) {
                              if (val != null) app.setDrawingSyncStrategy(val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ]),
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
                    _buildDivider(panelBorder),
                    _buildToggleTile(
                      icon: LucideIcons.bug,
                      label: 'إظهار معلومات المطور في الواجهة',
                      value: app.showDevInfo,
                      onChanged: (val) => app.toggleDevInfo(val),
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
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: textPrimary.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: textPrimary))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF3B82F6),
          ),
        ],
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
            Icon(LucideIcons.chevronRight, size: 16, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(Color border) => Divider(height: 1, color: border, indent: 48);

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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: panelBorder),
      ),
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

  void _showCleanupDialog(BuildContext context, AppProvider app, PdfItem pdf) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كل الملاحظات؟'),
        content: const Text('سيتم حذف كل الهايلايت والرسومات والملاحظات في هذا الملف نهائيًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              app.clearAllAnnotations(pdf.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم المسح بنجاح')));
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }

  void _showNoPdfError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى فتح ملف PDF أولاً لاستخدام أدوات التنظيف.')),
    );
  }

  void _showGlobalCleanupDialog(BuildContext context, AppProvider app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح شامل لكافة الملفات؟'),
        content: const Text(
            'سيتم حذف كافة الملاحظات والرسومات والهايلايت من جميع الملفات في كافة الفصول نهائيًا.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              app.clearAllGlobalAnnotations();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم مسح كافة البيانات بنجاح')));
            },
            child: const Text('تأكيد المسح الشامل'),
          ),
        ],
      ),
    );
  }
}
