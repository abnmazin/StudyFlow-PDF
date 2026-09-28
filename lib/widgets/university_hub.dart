import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/app_user.dart';
import '../models/university_folder.dart';
import '../services/university_service.dart';
import '../providers/app_state.dart';
import 'university_folder_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UniversityHub
// Main unified university component injected into the dashboard.
//
// Role-adaptive:
//   - Admin: sees folders + "Create Folder" FAB
//   - Student: sees folders (read-only), no create button
//
// Replaces the old personal "مجلداتي" section when user has a universityId.
// ─────────────────────────────────────────────────────────────────────────────

class UniversityHub extends StatefulWidget {
  final bool isDarkMode;
  final AppUser user;

  const UniversityHub({
    super.key,
    required this.isDarkMode,
    required this.user,
  });

  @override
  State<UniversityHub> createState() => _UniversityHubState();
}

class _UniversityHubState extends State<UniversityHub> {
  final UniversityService _universityService = UniversityService();
  StreamSubscription<List<UniversityFolder>>? _folderSub;
  List<UniversityFolder> _folders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    try {
      await _universityService.init(widget.user);

      // Graceful exit if user has no universityId (no crash, no rebuild loop)
      if (!_universityService.isReady) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Listen to real-time folder updates
      _folderSub = _universityService.streamFolders().listen(
        (folders) {
          if (mounted) {
            setState(() {
              _folders = folders;
              _isLoading = false;
              _error = null;
            });
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _error = err.toString();
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _folderSub?.cancel();
    super.dispose();
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final isDarkMode = widget.isDarkMode;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Create University Folder',
          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: 'e.g. Math 301 - Lectures',
            hintStyle: TextStyle(
              color: isDarkMode ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty && mounted) {
      try {
        await _universityService.createFolder(name: name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Folder created successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteFolder(UniversityFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder?'),
        content: Text('Delete "${folder.name}" and all its files?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _universityService.deleteFolder(folder.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('🗑️ Folder deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final isAdmin = widget.user.isAdmin;
    final univName = widget.user.universityId ?? 'University';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header with University Name ────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.landmark,
                    color: Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'University Hub',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      univName,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (isAdmin)
              TextButton.icon(
                onPressed: _showCreateFolderDialog,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('New Folder'),
                style: TextButton.styleFrom(foregroundColor: Colors.indigo),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Content ───────────────────────────────────────────────────
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_error != null)
          _buildError(isDarkMode)
        else if (_folders.isEmpty)
          _buildEmpty(isDarkMode)
        else
          _buildFolderGrid(isDarkMode, isAdmin),
      ],
    );
  }

  Widget _buildError(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.alertCircle, color: Colors.red, size: 32),
          const SizedBox(height: 12),
          Text(
            'Could not load university data',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1E293B).withValues(alpha: 0.5)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Icon(
            LucideIcons.folderOpen,
            size: 48,
            color: isDarkMode ? Colors.grey[600] : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            widget.user.isAdmin
                ? 'No folders yet. Create one!'
                : 'No folders available yet',
            style: TextStyle(
              color: isDarkMode
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderGrid(bool isDarkMode, bool isAdmin) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.3,
      ),
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return _FolderCard(
          folder: folder,
          isDarkMode: isDarkMode,
          isAdmin: isAdmin,
          onTap: () => _openFolder(folder),
          onDelete: isAdmin ? () => _deleteFolder(folder) : null,
        );
      },
    );
  }

  void _openFolder(UniversityFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<AppProvider>(),
          child: FolderViewScreen(
            folder: folder,
            isDarkMode: widget.isDarkMode,
            user: widget.user,
          ),
        ),
      ),
    );
  }
}

// ─── Folder Card ───────────────────────────────────────────────────────────

class _FolderCard extends StatelessWidget {
  final UniversityFolder folder;
  final bool isDarkMode;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _FolderCard({
    required this.folder,
    required this.isDarkMode,
    required this.isAdmin,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Stack(
          children: [
            // Accent decoration
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(60),
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.folder, color: Colors.indigo[400], size: 32),
                  const SizedBox(height: 12),
                  Text(
                    folder.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'University folder',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            // Delete button (admin only)
            if (isAdmin && onDelete != null)
              Positioned(
                top: 4,
                left: 4,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.trash2,
                      size: 14,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
