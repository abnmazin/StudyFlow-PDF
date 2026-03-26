import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

class DevDashboard extends StatefulWidget {
  const DevDashboard({super.key});

  @override
  State<DevDashboard> createState() => _DevDashboardState();
}

class _DevDashboardState extends State<DevDashboard> {
  final _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isDark = app.isDarkMode;
    final scheme = Theme.of(context).colorScheme;

    final bg = isDark ? const Color(0xFF0F172A) : scheme.surface;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('لوحة تحكم المطور'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.userPlus),
            onPressed: () => _addUserDialog(context),
            tooltip: 'إضافة مستخدم جديد',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final user = users[index];
              final data = user.data() as Map<String, dynamic>;
              final username = data['username'] ?? 'بدون اسم';
              final role = data['role'] ?? 'member';
              final hardwareId = data['hardwareId'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        role == 'developer' ? Colors.amber : Colors.blue,
                    child: Icon(
                      role == 'developer'
                          ? LucideIcons.shieldAlert
                          : LucideIcons.user,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    username,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'الدور: $role | UUID: ${hardwareId.isEmpty ? "غير مرتبط" : "مرتبط"}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.refreshCw, size: 18),
                        onPressed: () => _resetUuid(user.id),
                        tooltip: 'فك ارتباط الجهاز (Reset UUID)',
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.trash2,
                          size: 18,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteUser(user.id, username),
                        tooltip: 'حذف المستخدم',
                      ),
                    ],
                  ),
                  onTap: () => _editRole(user.id, role),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _resetUuid(String userId) async {
    await _firestore.collection('users').doc(userId).update({'hardwareId': ''});
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم المزامنة بنجاح وفك الارتباط')));
    }
  }

  Future<void> _deleteUser(String userId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف مستخدم؟'),
        content: Text('هل أنت متأكد من حذف الحساب "$name"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore.collection('users').doc(userId).delete();
    }
  }

  void _addUserDialog(BuildContext context) {
    final nameController = TextEditingController();
    String selectedRole = 'member';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('إضافة مستخدم جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: selectedRole,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member (Student)')),
                  DropdownMenuItem(value: 'lecturer', child: Text('Lecturer (Teacher)')),
                  DropdownMenuItem(value: 'developer', child: Text('Developer (Admin)')),
                ],
                onChanged: (v) => setState(() => selectedRole = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  await _firestore.collection('users').add({
                    'username': name,
                    'role': selectedRole,
                    'hardwareId': '',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _editRole(String userId, String currentRole) {
     showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('تغيير دور المستخدم'),
        children: ['member', 'lecturer', 'developer'].map((r) => SimpleDialogOption(
          onPressed: () async {
            await _firestore.collection('users').doc(userId).update({'role': r});
            Navigator.pop(ctx);
          },
          child: Text(r, style: TextStyle(fontWeight: r == currentRole ? FontWeight.bold : FontWeight.normal)),
        )).toList(),
      ),
    );
  }
}
