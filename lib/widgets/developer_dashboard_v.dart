import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';

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

            Color roleColor = (role == 'developer' || role == 'admin')
                ? Colors.amber
                : (role == 'lecturer' ? Colors.purple : Colors.blue);
            IconData roleIcon = (role == 'developer' || role == 'admin')
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
    final passCtrl = TextEditingController();
    final passConfCtrl = TextEditingController();
    String role = currentRole ?? 'student';
    final isEdit = id != null;
    // Get the current admin's universityId to auto-assign
    final adminUniversityId = context.read<AppProvider>().currentUser?.universityId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'تعديل بيانات المستخدم' : 'إضافة مستخدم جديد'),
        content: SingleChildScrollView(
          child: Column(
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
                labelText: 'الصلاحية (Role)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'student', child: Text('طالب (Student)')),
                DropdownMenuItem(value: 'admin', child: Text('مشرف (Admin)')),
              ],
              onChanged: (v) => role = v!,
            ),
            if (!isEdit) ...[
              const SizedBox(height: 16),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  helperText:
                      '6 أحرف على الأقل. سلّمها للمستخدم ليدخل بها الآن.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passConfCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      LucideIcons.fingerprint,
                      size: 16,
                      color: Colors.amber,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'يُنشأ الحساب بدون بصمة. أول من يسجّل الدخول يربط جهازه '
                        'به، وأي جهاز ثانٍ لنفس الحساب يُرفض.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (adminUniversityId != null && adminUniversityId.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.landmark, size: 16, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'University: $adminUniversityId',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          ),
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

              if (!isEdit) {
                // Validate before touching the network, and refuse a
                // mismatch rather than provisioning an account whose owner
                // can never reproduce the password.
                final pass = passCtrl.text;
                if (pass.length < 6) {
                  _toast(ctx, 'كلمة المرور يجب ألا تقل عن 6 أحرف');
                  return;
                }
                if (pass != passConfCtrl.text) {
                  _toast(ctx, 'كلمتا المرور غير متطابقتين');
                  return;
                }

                try {
                  final uid = await AuthService().provisionAccount(
                        username: uname,
                        password: pass,
                        displayName: dname,
                        role: role,
                        universityId: adminUniversityId,
                      );
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  _toast(context, 'تم إنشاء الحساب $uname ويمكنه الدخول الآن');
                  debugPrint('🎉 [Dashboard] Provisioned $uname as uid=$uid');
                } catch (e) {
                  if (!context.mounted) return;
                  _toast(context, 'تعذّر إنشاء الحساب: $e', isError: true);
                }
                return;
              }

              if (isEdit) {
                debugPrint('👤 Updating user: $id');
                final updates = <String, dynamic>{
                  'username': uname,
                  'displayName': dname,
                  'role': role,
                };
                if (adminUniversityId != null && adminUniversityId.isNotEmpty) {
                  updates['universityId'] = adminUniversityId;
                }
                await _firestore.collection('users').doc(id).update(updates);
              } else {
                final newUser = <String, dynamic>{
                  'username': uname,
                  'displayName': dname,
                  'role': role,
                  'hardwareId': '',
                  'createdAt': FieldValue.serverTimestamp(),
                };
                // Auto-assign universityId from admin's university
                if (adminUniversityId != null && adminUniversityId.isNotEmpty) {
                  newUser['universityId'] = adminUniversityId;
                }
                await _firestore.collection('users').add(newUser);
              }
              if (context.mounted) Navigator.pop(ctx);
            },
            child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String message, {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : null,
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
}
