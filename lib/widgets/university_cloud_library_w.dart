import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';

import '../models/app_user.dart';
import '../models/university_folder.dart';
import '../models/university_file.dart';
import '../services/university_service.dart';
import '../services/file_manager_service.dart';
import '../providers/app_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UniversityCloudLibraryWidget
//
// Cloud-First University Library that replaces local Isar folder grid
// for users tied to a universityId.
//
// Admin/Dev: can create folders + upload PDFs
// Student: can browse folders + download files
//
// Announcements and To-Do lists remain visible in the dashboard —
// only this widget replaces the legacy folder grid + quick actions.
// ─────────────────────────────────────────────────────────────────────────────

class UniversityCloudLibraryWidget extends StatefulWidget {
  final bool isDarkMode;
  final AppUser user;

  const UniversityCloudLibraryWidget({
    super.key,
    required this.isDarkMode,
    required this.user,
  });

  @override
  State<UniversityCloudLibraryWidget> createState() =>
      _UniversityCloudLibraryWidgetState();
}

class _UniversityCloudLibraryWidgetState
    extends State<UniversityCloudLibraryWidget> {
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
      if (!_universityService.isReady) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
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

  bool get _isAdmin => widget.user.isAdmin;

  // ── Create Folder Dialog ──────────────────────────────────────────────

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final isDarkMode = widget.isDarkMode;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'إضافة مجلد جديد',
          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
          decoration: const InputDecoration(hintText: 'اسم المجلد...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('إنشاء'),
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
              content: Text('✅ تم إنشاء المجلد'),
              backgroundColor: Colors.green,
            ),
          );
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

  // ── Delete Folder ─────────────────────────────────────────────────────

  Future<void> _deleteFolder(UniversityFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المجلد؟'),
        content: Text('حذف "${folder.name}" وجميع ملفاته؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await _universityService.deleteFolder(folder.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ── Upload file to a folder (Admin) ───────────────────────────────────

  Future<void> _uploadFile(UniversityFolder folder) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('جاري رفع الملف...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      await _universityService.uploadPdf(
        filePath: filePath,
        folderId: folder.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم رفع الملف بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Open folder view (show files) ─────────────────────────────────────

  void _openFolder(UniversityFolder folder) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: ChangeNotifierProvider.value(
              value: context.read<AppProvider>(),
              child: _FolderDetailScreen(
                folder: folder,
                isDarkMode: widget.isDarkMode,
                user: widget.user,
                universityService: _universityService,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final univName = widget.user.universityId ?? 'الجامعة';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ───────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.cloud,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المكتبة الجامعية',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF0F172A),
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
            if (_isAdmin)
              TextButton.icon(
                onPressed: _showCreateFolderDialog,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('مجلد جديد'),
                style: TextButton.styleFrom(foregroundColor: Colors.indigo),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Content ──────────────────────────────────────────────────────
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
          _buildFolderGrid(isDarkMode),
      ],
    );
  }

  Widget _buildError(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.alertCircle, color: Colors.red, size: 32),
          const SizedBox(height: 12),
          Text(
            'تعذر تحميل بيانات الجامعة',
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
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1E293B).withOpacity(0.5)
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
            _isAdmin
                ? 'لا توجد مجلدات بعد. أنشئ واحداً!'
                : 'لا توجد ملفات متاحة بعد',
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

  Widget _buildFolderGrid(bool isDarkMode) {
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
          isAdmin: _isAdmin,
          onTap: () => _openFolder(folder),
          onDelete: _isAdmin ? () => _deleteFolder(folder) : null,
          onUpload: _isAdmin ? () => _uploadFile(folder) : null,
        );
      },
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
  final VoidCallback? onUpload;

  const _FolderCard({
    required this.folder,
    required this.isDarkMode,
    required this.isAdmin,
    required this.onTap,
    this.onDelete,
    this.onUpload,
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
            // Accent gradient
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
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
                  const Text(
                    'مجلد دراسي',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            // Admin actions
            if (isAdmin) ...[
              // Upload button top-left
              Positioned(
                top: 4,
                left: 4,
                child: GestureDetector(
                  onTap: onUpload,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.upload,
                      size: 14,
                      color: Colors.indigo,
                    ),
                  ),
                ),
              ),
              // Delete button top-right
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
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
          ],
        ),
      ),
    );
  }
}

// ─── Folder Detail Screen (Files inside a folder) ────────────────────────

class _FolderDetailScreen extends StatefulWidget {
  final UniversityFolder folder;
  final bool isDarkMode;
  final AppUser user;
  final UniversityService universityService;

  const _FolderDetailScreen({
    required this.folder,
    required this.isDarkMode,
    required this.user,
    required this.universityService,
  });

  @override
  State<_FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<_FolderDetailScreen> {
  StreamSubscription<List<UniversityFile>>? _fileSub;
  List<UniversityFile> _files = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _downloadingHashes = {};

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  void _startStream() {
    _fileSub = widget.universityService
        .streamFilesInFolder(widget.folder.id)
        .listen(
          (files) {
            if (mounted) {
              setState(() {
                _files = files;
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
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    super.dispose();
  }

  bool get _isAdmin => widget.user.isAdmin;

  Future<void> _handleDownload(UniversityFile file) async {
    final hash = file.fileHash;
    if (_downloadingHashes.contains(hash)) return;

    setState(() => _downloadingHashes.add(hash));

    try {
      // 1. Download to app documents directory
      final localPath = await widget.universityService.downloadPdfToLocal(file);

      if (!mounted) return;

      // 2. Import into StudyFlow library and open
      await context.read<AppProvider>().loadPdfFromPath(localPath);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم التحميل والفتح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل التحميل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingHashes.remove(hash));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    // Premium Midnight/Slate color palette for floating panel
    final bg = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final textPrimary = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDarkMode
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Center(
        child: Container(
          width: 650,
          height: 600,
          margin: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                // ── Modern Header Panel ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02),
                    border: Border(
                      bottom: BorderSide(
                        color: isDarkMode ? Colors.white10 : Colors.black54,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          LucideIcons.folder,
                          color: Colors.indigo,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.folder.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              '${_files.length} ملفات تعليمية',
                              style: TextStyle(
                                fontSize: 12,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          backgroundColor: isDarkMode
                              ? Colors.white10
                              : Colors.black.withOpacity(0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Main File List Area ─────────────────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      // Accent background in dark mode
                      if (isDarkMode)
                        Positioned(
                          bottom: -50,
                          left: -50,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.indigo.withOpacity(0.03),
                            ),
                          ),
                        ),
                      _buildBody(isDarkMode, textPrimary, textMuted),
                    ],
                  ),
                ),
                // ── Footer (Admin Quick Upload) ──────────────────────────
                if (_isAdmin)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.01)
                          : Colors.black.withOpacity(0.01),
                      border: Border(
                        top: BorderSide(
                          color: isDarkMode ? Colors.white10 : Colors.black54,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _adminUpload,
                          icon: const Icon(LucideIcons.upload, size: 18),
                          label: const Text('رفع ملف جديد'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDarkMode, Color textPrimary, Color textMuted) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.alertTriangle,
                color: Colors.red,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _startStream,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.fileX,
              size: 48,
              color: textMuted.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد ملفات في هذا المجلد',
              style: TextStyle(color: textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isDownloading = _downloadingHashes.contains(file.fileHash);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withOpacity(0.02)
                : Colors.black.withOpacity(0.01),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: isDownloading ? null : () => _handleDownload(file),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            LucideIcons.fileText,
                            color: Colors.red,
                            size: 22,
                          ),
                        ),
                        if (isDownloading)
                          const SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _formatBytes(file.sizeBytes),
                            style: TextStyle(fontSize: 11, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      LucideIcons.downloadCloud,
                      color: Colors.indigo,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _adminUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.single.path;
      if (filePath == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري رفع ملف PDF الجديد...'),
          duration: Duration(seconds: 30),
        ),
      );

      await widget.universityService.uploadPdf(
        filePath: filePath,
        folderId: widget.folder.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم رفع الملف'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل الرفع: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
