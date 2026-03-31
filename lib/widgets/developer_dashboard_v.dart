import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

// ─── DEVELOPER DASHBOARD VIEW (COMPREHENSIVE VERSION) ───────────────────────

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
                const Text(
                  'مركز التحكم المتقدم',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () => _modernUserDialog(context),
              icon: const Icon(LucideIcons.userPlus, size: 14),
              label: const Text('مستخدم جديد', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildSectionHeader(
                'إحصائيات النظام الشاملة',
                LucideIcons.barChart3,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildDetailedStats(surfaceAlt, panelBorder),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'الدروس والنشاط اللحظي (Sessions)',
                LucideIcons.radio,
                textMuted,
                trailing: TextButton(
                  onPressed: () =>
                      _confirmWipe(context, 'sync_sessions', 'الدروس'),
                  child: const Text(
                    'مسح الكل',
                    style: TextStyle(color: Colors.red, fontSize: 10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildActiveSessionsList(surfaceAlt, panelBorder, app),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'إدارة قاعدة بيانات المستخدمين',
                LucideIcons.database,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildUserManagementList(surfaceAlt, panelBorder),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

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
                // Determine if we are still loading any core data
                if (!userSnap.hasData ||
                    !sessionSnap.hasData ||
                    !masterSnap.hasData) {
                  return SizedBox(
                    height: 120,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'جاري تحميل الإحصائيات...',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final users = userSnap.data!.docs;
                final sessions = sessionSnap.data!.docs.length;
                final bundles = masterSnap.data!.docs.length;

                // Safe role calculation
                int admins = 0;
                int lecturers = 0;

                for (var u in users) {
                  final data = u.data() as Map<String, dynamic>?;
                  if (data != null) {
                    final r = data['role']?.toString().toLowerCase();
                    if (r == 'developer') {
                      admins++;
                    } else if (r == 'lecturer') {
                      lecturers++;
                    }
                  }
                }

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
                      'الدروس والنشاط',
                      sessions.toString(),
                      LucideIcons.activity,
                      Colors.green,
                      surface,
                      border,
                    ),
                    _buildStatItem(
                      'الحزم الدراسية',
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
    String t,
    String v,
    IconData i,
    Color c,
    Color s,
    Color b,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: s,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: b),
    ),
    child: Row(
      children: [
        Icon(i, size: 16, color: c),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              v,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            Text(
              t,
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

  Widget _buildActiveSessionsList(Color s, Color b, AppProvider app) {
    final currentUser = app.currentUser;
    final bool isDeveloper = currentUser?.role == 'developer';

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('sync_sessions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        // 1. Filter sessions:
        // - If Developer: show all.
        // - If Lecturer: show only their own (by UID).
        final rawDocs = snapshot.data!.docs;
        final docs = isDeveloper
            ? rawDocs
            : rawDocs.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return d['createdBy'] == currentUser?.uid;
              }).toList();

        if (docs.isEmpty)
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: s,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                isDeveloper
                    ? 'لا توجد دروس حالية في النظام'
                    : 'ليس لديك دروس نشطة حالياً',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          );

        return Container(
          decoration: BoxDecoration(
            color: s,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: b),
          ),
          child: Column(
            children: [
              if (isDeveloper)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'عرض القائمة الكاملة (إدارة المطور)',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.amber.withOpacity(0.8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final parts = data['participants'] as List? ?? [];
                return ExpansionTile(
                  dense: true,
                  leading: const Icon(
                    LucideIcons.presentation,
                    size: 18,
                    color: Colors.blue,
                  ),
                  title: Text(
                    '${data['pdfName'] ?? 'بدون اسم ملف'} (${doc.id})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'الطلاب: ${parts.length}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      LucideIcons.trash2,
                      size: 14,
                      color: Colors.red,
                    ),
                    onPressed: () =>
                        _confirmDelete('sync_sessions', doc.id, 'الجلسة'),
                  ),
                  children: parts
                      .map(
                        (p) => ListTile(
                          dense: true,
                          title: Text(
                            p is Map ? p['username'] : p.toString(),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: TextButton(
                            onPressed: () => app.syncService.kickParticipant(
                              doc.id,
                              p is Map ? p['uid'] : "",
                            ),
                            child: const Text(
                              'طرد',
                              style: TextStyle(color: Colors.red, fontSize: 10),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserManagementList(Color s, Color b) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;
        return Container(
          decoration: BoxDecoration(
            color: s,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: b),
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
              final hwId = (data['hardwareId'] ?? "").toString();
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      (role == 'developer'
                              ? Colors.amber
                              : (role == 'lecturer'
                                    ? Colors.purple
                                    : Colors.blue))
                          .withOpacity(0.1),
                  child: Icon(
                    role == 'developer'
                        ? LucideIcons.shieldCheck
                        : (role == 'lecturer'
                              ? LucideIcons.graduationCap
                              : LucideIcons.user),
                    size: 14,
                    color: role == 'developer'
                        ? Colors.amber
                        : (role == 'lecturer' ? Colors.purple : Colors.blue),
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
                  hwId.isNotEmpty ? 'جهاز مرتبط ✅' : 'حر ❌',
                  style: TextStyle(
                    fontSize: 9,
                    color: hwId.isNotEmpty ? Colors.green : Colors.red,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hwId.isNotEmpty)
                      IconButton(
                        icon: const Icon(LucideIcons.refreshCw, size: 14),
                        onPressed: () => _firestore
                            .collection('users')
                            .doc(user.id)
                            .update({'hardwareId': ''}),
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

  void _modernUserDialog(BuildContext context) {
    final name = TextEditingController();
    String role = 'member';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مستخدم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'الاسم الكامل'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: 'الصلاحية'),
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
              if (name.text.trim().isEmpty) return;
              await _firestore.collection('users').add({
                'username': name.text.trim(),
                'role': role,
                'hardwareId': '',
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String t,
    IconData i,
    Color c, {
    Widget? trailing,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 8),
          Text(
            t,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: c,
            ),
          ),
        ],
      ),
      if (trailing != null) trailing,
    ],
  );

  Future<void> _confirmDelete(String c, String id, String t) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف $t'),
        content: const Text('هل أنت متأكد؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لا'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم'),
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
        title: Text('مسح كافة $t؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('مسح'),
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
