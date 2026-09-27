import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';

import '../models/app_user.dart';
import '../models/university_folder.dart';
import '../models/university_file.dart';
import '../models/university_video.dart';
import '../services/university_service.dart';
import '../providers/app_state.dart';
import 'university_video_dialog.dart';
import 'viewer_components/youtube_player_w.dart';

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
      // Guarantees every uploaded booklet carries its own sync code, so the
      // viewer can auto-link to the shared session with no manual step.
      if (widget.user.isLecturer) {
        unawaited(_universityService.backfillSyncCodes());
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('✅ تم رفع الملف بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // Shown as a dialog so it always renders on top of any open window
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(LucideIcons.alertCircle, color: Colors.red, size: 22),
                SizedBox(width: 10),
                Text('فشل رفع الملف'),
              ],
            ),
            content: Text(
              '$e',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً'),
              ),
            ],
          ),
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
  StreamSubscription<List<UniversityVideo>>? _videoSub;
  List<UniversityVideo> _videos = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _downloadingHashes = {};
  final Set<String> _openingVideoIds = {};
  final Set<String> _cachedHashes = {};
  final Map<String, String> _localPaths = {};
  bool _isUploading = false;
  String? _uploadError;
  bool _uploadSuccess = false;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  /// Marks which library files already exist on disk. A file that is present
  /// opens instantly and offline, so it is worth telling apart from one that
  /// still has to be fetched. One directory listing covers the whole page.
  Future<void> _refreshCachedHashes(List<UniversityFile> files) async {
    final names = await widget.universityService.getDownloadedFileNames();
    if (names.isEmpty && files.isEmpty) return;
    final result = <String>{};
    for (final f in files) {
      final stored = f.storagePath.split('/').last;
      if (names.contains(stored) || names.contains(f.name)) {
        result.add(f.fileHash);
      }
    }
    if (!mounted) return;
    setState(() {
      _cachedHashes
        ..clear()
        ..addAll(result);
    });
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
            unawaited(_refreshCachedHashes(files));
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

    _videoSub = widget.universityService
        .streamVideosInFolder(widget.folder.id)
        .listen(
          (videos) {
            if (mounted) {
              setState(() => _videos = videos);
            }
          },
          onError: (err) {
            debugPrint('⚠️ [FolderDetail] Video stream error: $err');
          },
        );
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    _videoSub?.cancel();
    super.dispose();
  }

  bool get _isAdmin => widget.user.isAdmin;

  Future<void> _handleDownload(UniversityFile file) async {
    final hash = file.fileHash;
    if (_downloadingHashes.contains(hash)) return;

    setState(() => _downloadingHashes.add(hash));

    try {
      // 1. Open the local copy when one already exists. This is the fast path
      //    and the only one that works offline: the university library is in
      //    Firestore and Supabase, so a file that was never downloaded cannot
      //    be reached without a connection, while a cached one must never be
      //    made to wait on the network. The disk is asked first because a
      //    downloaded file stays openable even if its local record is gone.
      //
      //    _localPaths remembers what this page already opened. A file that was
      //    just fetched is in that map, so tapping it again cannot re-fetch it
      //    even if the two disk lookups below were to miss.
      var localPath = _localPaths[hash];
      localPath ??= await widget.universityService.getDownloadedPath(file);
      localPath ??= await widget.universityService.getCachedPath(hash);

      // 2. Only download when there is genuinely nothing on disk.
      if (localPath == null) {
        localPath = await widget.universityService.downloadPdfToLocal(file);
      }
      _localPaths[hash] = localPath;

      // The file is on disk either way, so the listing should say so now
      // rather than at the mercy of the next stream event.
      if (mounted) setState(() => _cachedHashes.add(hash));

      if (!mounted) return;

      // 3. Import into StudyFlow library and open
      await context.read<AppProvider>().loadPdfFromPath(localPath);

      // No confirmation snackbar: the file opens either way, and announcing a
      // download that mostly did not happen is noise.
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

  // ── Delete file (Admin only) ─────────────────────────────────────────

  Future<void> _deleteFile(UniversityFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الملف؟'),
        content: Text(
          'حذف "${file.name}" من المكتبة الجامعية؟\n'
          'سيُحذف من التخزين لجميع الأعضاء.',
        ),
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
        await widget.universityService.deleteFile(file);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🗑️ تم حذف الملف'),
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
                              '${_files.length} ملفات · ${_videos.length} دروس فيديو',
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Upload progress (inline, always visible) ────
                        if (_isUploading)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.indigo,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'جاري رفع الملف...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // ── Upload error banner (inline) ─────────────────
                        if (_uploadError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.alertCircle,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'فشل الرفع: $_uploadError',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.red,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () =>
                                        setState(() => _uploadError = null),
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        LucideIcons.x,
                                        color: Colors.red,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            if (_uploadSuccess)
                              const Text(
                                '✅ تم رفع الملف بنجاح',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _adminAddVideo,
                              icon: const Icon(
                                LucideIcons.youtube,
                                size: 18,
                                color: Color(0xFFEF4444),
                              ),
                              label: const Text('إضافة درس فيديو'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _isUploading ? null : _adminUpload,
                              icon: const Icon(LucideIcons.upload, size: 18),
                              label: const Text('رفع ملف جديد'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    Colors.indigo.withOpacity(0.5),
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
    if (_files.isEmpty && _videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.folderOpen,
              size: 48,
              color: textMuted.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد ملفات أو فيديوهات في هذا المجلد',
              style: TextStyle(color: textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_videos.isNotEmpty) ...[
          _sectionHeader('🎬 دروس فيديو', textMuted),
          ..._videos.map(
            (video) => _buildVideoTile(isDarkMode, textPrimary, textMuted, video),
          ),
        ],
        if (_files.isNotEmpty) ...[
          if (_videos.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('📄 ملفات PDF', textMuted),
          ],
          ..._files.map(
            (file) => _buildFileTile(isDarkMode, textPrimary, textMuted, file),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10, top: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textMuted.withOpacity(0.8),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildFileTile(
    bool isDarkMode,
    Color textPrimary,
    Color textMuted,
    UniversityFile file,
  ) {
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
                          // Files already on disk read brighter than the ones
                          // that still need fetching, so the ones that open
                          // instantly and work offline are recognisable at a
                          // glance. Colors.white alone was invisible here
                          // because textPrimary is already white in dark mode,
                          // so the two states needed to differ in weight and
                          // colour, not colour alone.
                          color: _cachedHashes.contains(file.fileHash)
                              ? Colors.white
                              : textMuted,
                          shadows: _cachedHashes.contains(file.fileHash)
                              ? const [
                                  Shadow(
                                    color: Color(0x66FFFFFF),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isAdmin)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: const Icon(
                          LucideIcons.trash2,
                          color: Color(0xFFF87171),
                          size: 18,
                        ),
                        tooltip: 'حذف الملف',
                        onPressed: () => _deleteFile(file),
                      ),
                    const Icon(
                      LucideIcons.downloadCloud,
                      color: Colors.indigo,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoTile(
    bool isDarkMode,
    Color textPrimary,
    Color textMuted,
    UniversityVideo video,
  ) {
    return DragTarget<Map<String, String>>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return _isAdmin &&
            data['dragType'] == 'uniVideo' &&
            data['folderId'] == widget.folder.id &&
            data['videoId'] != video.id;
      },
      onAcceptWithDetails: (details) {
        final draggedId = details.data['videoId'];
        if (draggedId != null) _reorderVideos(draggedId, video.id);
      },
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return Draggable<Map<String, String>>(
          data: {
            'dragType': 'uniVideo',
            'folderId': widget.folder.id,
            'videoId': video.id,
          },
          maxSimultaneousDrags: _isAdmin ? null : 0,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.youtube,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: hovering
                  ? const Color(0xFFEF4444).withOpacity(0.06)
                  : (isDarkMode
                      ? Colors.white.withOpacity(0.02)
                      : Colors.black.withOpacity(0.01)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hovering
                    ? const Color(0xFFEF4444).withOpacity(0.4)
                    : (isDarkMode
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05)),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _openVideo(video),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          LucideIcons.youtube,
                          color: Color(0xFFEF4444),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'يوتيوب',
                              style: TextStyle(
                                fontSize: 11,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isAdmin)
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              icon: const Icon(
                                LucideIcons.trash2,
                                color: Color(0xFFF87171),
                                size: 18,
                              ),
                              tooltip: 'حذف الفيديو',
                              onPressed: () => _deleteVideo(video),
                            ),
                          const Icon(
                            LucideIcons.play,
                            color: Color(0xFFEF4444),
                            size: 22,
                          ),
                        ],
                      ),
                    ],
                  ),
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
      setState(() {
        _isUploading = true;
        _uploadError = null;
        _uploadSuccess = false;
      });

      await widget.universityService.uploadPdf(
        filePath: filePath,
        folderId: widget.folder.id,
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadSuccess = true;
        });
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _uploadSuccess = false);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadError = e.toString();
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Video links (Admin add / delete / reorder) ────────────────────────

  Future<void> _adminAddVideo() async {
    await showDialog(
      context: context,
      builder: (_) => UniversityVideoDialog(
        folderId: widget.folder.id,
        user: widget.user,
      ),
    );
  }

  void _openVideo(UniversityVideo video) {
    if (_openingVideoIds.contains(video.id)) return;
    _openingVideoIds.add(video.id);
    showYouTubeVideoPlayer(context, video).whenComplete(() {
      _openingVideoIds.remove(video.id);
    });
  }

  Future<void> _deleteVideo(UniversityVideo video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الفيديو؟'),
        content: Text('حذف "${video.title}" من المكتبة الجامعية؟'),
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
        await widget.universityService.deleteVideo(video);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🗑️ تم حذف الفيديو'),
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

  Future<void> _reorderVideos(String draggedVideoId, String targetVideoId) async {
    if (!_isAdmin) return;
    try {
      await widget.universityService.reorderVideos(
        folderId: widget.folder.id,
        draggedVideoId: draggedVideoId,
        targetVideoId: targetVideoId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
