import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/sync_service.dart';

class DeveloperDashboardView extends StatefulWidget {
  final VoidCallback onBack;

  const DeveloperDashboardView({super.key, required this.onBack});

  @override
  State<DeveloperDashboardView> createState() => _DeveloperDashboardViewState();
}

class _DeveloperDashboardViewState extends State<DeveloperDashboardView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncService _syncService = SyncService();

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
        // Header with Back Button
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: Icon(LucideIcons.arrowRight, color: textPrimary, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              'إدارة النظام المتقدمة',
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
                'حالة الخادم والبيانات',
                LucideIcons.activity,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildStatsGrid(surfaceAlt, panelBorder, isDark),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'الجلسات والحزم الحالية',
                LucideIcons.radio,
                textMuted,
              ),
              const SizedBox(height: 12),
              _buildActiveUnits(surfaceAlt, panelBorder, isDark),

              const SizedBox(height: 24),
              _buildSectionHeader(
                'إدارة المستخدمين',
                LucideIcons.users,
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

  // --- إحصائيات سريعة (Stats) ---
  Widget _buildStatsGrid(Color surface, Color border, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('sync_sessions').snapshots(),
          builder: (context, sessionSnap) {
            final users = userSnap.data?.docs.length ?? 0;
            final sessions = sessionSnap.data?.docs.length ?? 0;

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
              children: [
                _buildCompactStatCard(
                  'الأعضاء',
                  users.toString(),
                  LucideIcons.users,
                  Colors.blue,
                  surface,
                  border,
                ),
                _buildCompactStatCard(
                  'الجلسات',
                  sessions.toString(),
                  LucideIcons.activity,
                  Colors.green,
                  surface,
                  border,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCompactStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color surface,
    Color border,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  // --- إدارة الجلسات والحزم (Compact) ---
  Widget _buildActiveUnits(Color surface, Color border, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          _buildActionTile(
            icon: LucideIcons.database,
            label: 'مسح كافة جلسات المزامنة',
            color: Colors.redAccent,
            onTap: () =>
                _confirmWipe('الجلسات', () => _syncService.deleteAllSessions()),
          ),
          const Divider(height: 1),
          _buildActionTile(
            icon: LucideIcons.layers,
            label: 'مسح كافة الحزم الدراسية',
            color: Colors.orange,
            onTap: () => _confirmWipe(
              'الحزم',
              () => _syncService.deleteAllMasterBundles(),
            ),
          ),
        ],
      ),
    );
  }

  // --- قائمة المستخدمين ---
  Widget _buildUserManagementList(Color surface, Color border, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: LinearProgressIndicator());
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
              final bool isLinked = (data['hardwareId'] ?? '')
                  .toString()
                  .isNotEmpty;

              return ListTile(
                dense: true,
                leading: Icon(
                  role == 'developer'
                      ? LucideIcons.shieldCheck
                      : LucideIcons.user,
                  size: 18,
                  color: role == 'developer' ? Colors.amber : Colors.blue,
                ),
                title: Text(
                  data['username'] ?? 'User',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  isLinked ? 'مرتبط ✅' : 'حر ❌',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.edit2, size: 14),
                      onPressed: () =>
                          _modernUserDialog(user.id, data['username'], role),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _deleteUser(user.id),
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

  // --- Helpers ---
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
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 18, color: color),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(LucideIcons.chevronLeft, size: 14),
    );
  }

  // Logic Stubs (Keep existing logic from your dev_dashboard.dart)
  Future<void> _confirmWipe(
    String title,
    Future<void> Function() action,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد المسح: $title'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح نهائي'),
          ),
        ],
      ),
    );
    if (confirm == true) await action();
  }

  void _modernUserDialog(String? id, String? name, String? role) {
    // Implement your user edit dialog here (similar to your original)
  }

  Future<void> _deleteUser(String id) async {
    await _firestore.collection('users').doc(id).delete();
  }
}
