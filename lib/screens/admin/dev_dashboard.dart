import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../services/sync_service.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

class DevDashboard extends StatefulWidget {
  const DevDashboard({super.key});

  @override
  State<DevDashboard> createState() => _DevDashboardState();
}

class _DevDashboardState extends State<DevDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncService _syncService = SyncService();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isDark = app.isDarkMode;
    final scheme = Theme.of(context).colorScheme;

    // لوحة ألوان Modern Slate
    final bg = isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC);
    final surface = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text(
          'مركز التحكم والإدارة',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => _modernUserDialog(context),
              icon: const Icon(LucideIcons.userPlus, size: 18),
              label: const Text('إضافة مستخدم'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. قسم الملخص (تصميم القائمة المستطيلة الجديد)
          _buildSectionHeader('ملخص حالة النظام', LucideIcons.barChart3),
          _buildSliverStats(surface, isDark),

          // 2. مراقبة الدروس (هيكلية منسدلة)
          _buildSectionHeader('الدروس والنشاط اللحظي', LucideIcons.radio),
          _buildSessionsHierarchy(scheme, surface, isDark),

          // 3. قاعدة بيانات المستخدمين
          _buildSectionHeader('إدارة أعضاء المنصة', LucideIcons.database),
          _buildUsersList(scheme, surface, isDark),

          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ],
      ),
    );
  }

  // --- عناصر واجهة الإحصائيات (قائمة مستطيلة) ---
  Widget _buildSliverStats(Color surface, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, userSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('sync_sessions').snapshots(),
          builder: (context, sessionSnapshot) {
            int totalUsers = 0, admins = 0, lecturers = 0;
            int sessions = sessionSnapshot.data?.docs.length ?? 0;

            if (userSnapshot.hasData) {
              for (var doc in userSnapshot.data!.docs) {
                totalUsers++;
                final role = doc['role'] as String? ?? 'member';
                if (role == 'developer') admins++;
                if (role == 'lecturer') lecturers++;
              }
            }

            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildStatRectCard(
                    'إجمالي الأعضاء',
                    totalUsers.toString(),
                    LucideIcons.users,
                    Colors.blue,
                    surface,
                    isDark,
                    null,
                  ),
                  _buildStatRectCard(
                    'المشرفين (Developers)',
                    admins.toString(),
                    LucideIcons.shieldAlert,
                    Colors.amber.shade700,
                    surface,
                    isDark,
                    null,
                  ),
                  _buildStatRectCard(
                    'المحاضرين (Lecturers)',
                    lecturers.toString(),
                    LucideIcons.graduationCap,
                    Colors.purple,
                    surface,
                    isDark,
                    null,
                  ),
                  _buildStatRectCard(
                    'الدروس النشطة حالياً',
                    sessions.toString(),
                    LucideIcons.activity,
                    Colors.green,
                    surface,
                    isDark,
                    null,
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatRectCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color surface,
    bool isDark,
    VoidCallback? onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            IconButton(
              icon: Icon(LucideIcons.arrowLeft, color: color),
              onPressed: onTap,
              style: IconButton.styleFrom(
                backgroundColor: color.withOpacity(0.05),
              ),
            ),
        ],
      ),
    );
  }

  // --- هيكلية الدروس المنسدلة ---
  Widget _buildSessionsHierarchy(
    ColorScheme scheme,
    Color surface,
    bool isDark,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('sync_sessions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const SliverToBoxAdapter(child: LinearProgressIndicator());
        final sessions = snapshot.data!.docs;
        if (sessions.isEmpty)
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('لا توجد جلسات نشطة'),
              ),
            ),
          );

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final session = sessions[index];
              final data = session.data() as Map<String, dynamic>;
              final participants = data['participants'] as List? ?? [];

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                  ),
                ),
                child: ExpansionTile(
                  leading: const Icon(
                    LucideIcons.presentation,
                    color: Colors.blue,
                  ),
                  title: Text(
                    'درس: ${session.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'المالك: ${data['ownerName'] ?? 'Unnamed'} • طلاب: ${participants.length}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      LucideIcons.trash2,
                      color: Colors.red,
                      size: 18,
                    ),
                    onPressed: () => _terminateSession(session.id),
                  ),
                  children: [
                    const Divider(height: 1),
                    ...participants.map((p) {
                      final String displayName = p is Map
                          ? (p['username'] ?? 'Unknown')
                          : p.toString();
                      final String pId = (p is Map)
                          ? (p['id']?.toString() ?? p['hardwareId']?.toString() ?? "")
                          : p.toString();
                      final String pUid = (p is Map) ? (p['uid']?.toString() ?? "") : "";
                      return ListTile(
                        dense: true,
                        leading: const Icon(LucideIcons.user, size: 14),
                        title: Text(
                          displayName,
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          pId,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            if (pId.isEmpty && pUid.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("خطأ: معرفات المستخدم فارغة")),
                              );
                              return;
                            }
                            _kickParticipant(session.id, pUid);
                          },
                          child: const Text(
                            'طرد',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }, childCount: sessions.length),
          ),
        );
      },
    );
  }

  // --- قائمة المستخدمين ---
  Widget _buildUsersList(ColorScheme scheme, Color surface, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const SliverToBoxAdapter(child: SizedBox());
        final users = snapshot.data!.docs;

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final user = users[index];
              final data = user.data() as Map<String, dynamic>;
              final role = data['role'] ?? 'member';
              final isLinked = (data['hardwareId'] ?? '').toString().isNotEmpty;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
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
                      color: role == 'developer'
                          ? Colors.amber
                          : (role == 'lecturer' ? Colors.purple : Colors.blue),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    data['username'] ?? 'مستخدم',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    isLinked ? 'جهاز مرتبط ✅' : 'غير مرتبط ❌',
                    style: TextStyle(
                      fontSize: 11,
                      color: isLinked ? Colors.green : Colors.red,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLinked)
                        IconButton(
                          icon: const Icon(LucideIcons.refreshCw, size: 16),
                          onPressed: () => _resetUuid(user.id),
                        ),
                      IconButton(
                        icon: const Icon(LucideIcons.edit3, size: 16),
                        onPressed: () => _modernUserDialog(
                          context,
                          id: user.id,
                          name: data['username'],
                          role: role,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.trash2,
                          size: 16,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteUser(user.id),
                      ),
                    ],
                  ),
                ),
              );
            }, childCount: users.length),
          ),
        );
      },
    );
  }

  // --- العمليات والمنطق (Logic) ---

  Future<void> _terminateSession(String id) async {
    final confirm = await _showConfirm(
      'إلغاء الدرس؟',
      'هل تريد إغلاق هذه الجلسة نهائياً؟',
    );
    if (confirm) await _firestore.collection('sync_sessions').doc(id).delete();
  }

  Future<void> _kickParticipant(String sId, String pUid) async {
    await _syncService.kickParticipant(sId, pUid);
  }

  Future<void> _resetUuid(String id) async {
    await _firestore.collection('users').doc(id).update({'hardwareId': ''});
  }

  Future<void> _deleteUser(String id) async {
    if (await _showConfirm(
      'حذف مستخدم؟',
      'سيتم حذف الحساب نهائياً من النظام.',
    )) {
      await _firestore.collection('users').doc(id).delete();
    }
  }

  // --- النوافذ المنبثقة (Modern Dialogs) ---

  void _modernUserDialog(
    BuildContext context, {
    String? id,
    String? name,
    String? role,
  }) {
    final nameCtrl = TextEditingController(text: name);
    String selectedRole = role ?? 'member';
    final isEdit = id != null;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, a1, a2) => const SizedBox(),
      transitionBuilder: (ctx, a1, a2, child) {
        return Transform.scale(
          scale: a1.value,
          child: Opacity(
            opacity: a1.value,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(isEdit ? 'تعديل مستخدم' : 'مستخدم جديد'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('طالب')),
                      DropdownMenuItem(value: 'lecturer', child: Text('محاضر')),
                      DropdownMenuItem(value: 'developer', child: Text('مشرف')),
                    ],
                    onChanged: (v) => selectedRole = v!,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'الصلاحية',
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
                  onPressed: () async {
                    final data = {
                      'username': nameCtrl.text.trim(),
                      'role': selectedRole,
                    };
                    if (isEdit) {
                      await _firestore.collection('users').doc(id).update(data);
                    } else {
                      await _firestore.collection('users').add({
                        ...data,
                        'hardwareId': '',
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('تأكيد'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showConfirm(String t, String m) async {
    return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t),
            content: Text(m),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تراجع'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.blueGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
