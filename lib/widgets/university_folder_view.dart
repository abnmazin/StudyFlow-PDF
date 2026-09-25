import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:isar/isar.dart';

import '../models/app_user.dart';
import '../models/university_folder.dart';
import '../models/university_file.dart';
import '../models/university_video.dart';
import '../models/isar_models.dart';
import '../services/university_service.dart';
import '../services/file_manager_service.dart';
import '../providers/app_state.dart';
import 'university_upload_dialog.dart';
import 'university_video_dialog.dart';
import 'viewer_components/youtube_player_w.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FolderViewScreen
// Displays files inside a university folder with role-adaptive controls.
//
// Admin: sees Upload button, swipe-to-delete on files
// Student: sees Download/Open buttons, read-only, no delete
// ─────────────────────────────────────────────────────────────────────────────

class FolderViewScreen extends StatefulWidget {
  final UniversityFolder folder;
  final bool isDarkMode;
  final AppUser user;

  const FolderViewScreen({
    super.key,
    required this.folder,
    required this.isDarkMode,
    required this.user,
  });

  @override
  State<FolderViewScreen> createState() => _FolderViewScreenState();
}

class _FolderViewScreenState extends State<FolderViewScreen> {
  final UniversityService _universityService = UniversityService();
  StreamSubscription<List<UniversityFile>>? _fileSub;
  List<UniversityFile> _files = [];
  StreamSubscription<List<UniversityVideo>>? _videoSub;
  List<UniversityVideo> _videos = [];
  bool _isLoading = true;
  String? _error;

  /// Tracks which files are currently being downloaded (by fileHash).
  final Set<String> _downloadingFiles = {};

  @override
  void initState() {
    super.initState();
    _initFiles();
  }

  Future<void> _initFiles() async {
    try {
      _fileSub = _universityService
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

      _videoSub = _universityService
          .streamVideosInFolder(widget.folder.id)
          .listen(
        (videos) {
          if (mounted) {
            setState(() => _videos = videos);
          }
        },
        onError: (err) {
          debugPrint('⚠️ [FolderView] Video stream error: $err');
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
    _fileSub?.cancel();
    _videoSub?.cancel();
    super.dispose();
  }

  // ── Upload (Admin only) ───────────────────────────────────────────────

  Future<void> _showUploadDialog() async {
    await showDialog(
      context: context,
      builder: (_) => UploadPdfDialog(
        folderId: widget.folder.id,
        user: widget.user,
      ),
    );
  }

  Future<void> _showAddVideoDialog() async {
    await showDialog(
      context: context,
      builder: (_) => UniversityVideoDialog(
        folderId: widget.folder.id,
        user: widget.user,
      ),
    );
  }

  // ── Download (Student + Admin) ────────────────────────────────────────

  Future<void> _downloadAndOpen(UniversityFile file) async {
    setState(() => _downloadingFiles.add(file.fileHash));

    try {
      // Ensure file is cached locally (download if needed)
      final cached = await _universityService.getCachedPath(file.fileHash);
      if (cached == null) {
        await _universityService.downloadPdf(file);
      }

      if (!mounted) return;

      // Open the PDF via AppProvider
      final app = context.read<AppProvider>();
      final fileManager = context.read<FileManagerService>();

      // Find the local PdfDocument by fileHash
      final doc = await fileManager.isar.pdfDocuments
          .filter()
          .fileHashEqualTo(file.fileHash)
          .findFirst();

      if (doc != null) {
        if (app.isSplitMode && app.activePdfId != doc.uuid) {
          app.setSecondaryPdf(doc.uuid);
        } else {
          app.setActivePdf(doc.uuid);
        }

        // Restore reading progress
        _restoreReadingProgress(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingFiles.remove(file.fileHash));
      }
    }
  }

  /// Restore reading progress from Firestore (fileHash-based).
  Future<void> _restoreReadingProgress(UniversityFile file) async {
    try {
      final progress = await _universityService.getReadingProgress(
        fileHash: file.fileHash,
      );
      if (progress != null && mounted) {
        final fileManager = context.read<FileManagerService>();
        final doc = await fileManager.isar.pdfDocuments
            .filter()
            .fileHashEqualTo(file.fileHash)
            .findFirst();
        if (doc != null) {
          await fileManager.updateReadingState(
            doc.uuid,
            page: progress['lastPage'] as int?,
            scroll: (progress['scrollTop'] as num?)?.toDouble(),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '📖 Resumed from page ${progress['lastPage']}',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ [FolderView] Could not restore progress: $e');
    }
  }

  // ── Delete file (Admin only) ──────────────────────────────────────────

  Future<void> _deleteFile(UniversityFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File?'),
        content: Text('Delete "${file.name}" from the university?'),
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
        await _universityService.deleteFile(file);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🗑️ File deleted')),
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

  // ── Delete video link (Admin only) ────────────────────────────────────

  Future<void> _deleteVideo(UniversityVideo video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Video?'),
        content: Text('Delete "${video.title}" from the university?'),
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
        await _universityService.deleteVideo(video);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🗑️ Video deleted')),
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

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final isAdmin = widget.user.isAdmin;

    final bgColor =
        isDarkMode ? const Color(0xFF020617) : const Color(0xFFE2E8F0);
    final canvasColor =
        isDarkMode ? const Color(0xFF0F172A) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: canvasColor,
        title: Text(
          widget.folder.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isAdmin)
            TextButton.icon(
              onPressed: _showAddVideoDialog,
              icon: const Icon(
                LucideIcons.youtube,
                size: 18,
                color: Color(0xFFEF4444),
              ),
              label: const Text('Add Video'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          if (isAdmin)
            TextButton.icon(
              onPressed: _showUploadDialog,
              icon: const Icon(LucideIcons.upload, size: 18),
              label: const Text('Upload PDF'),
              style: TextButton.styleFrom(foregroundColor: Colors.indigo),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildContent(isDarkMode, isAdmin),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDarkMode, bool isAdmin) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertCircle, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
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
              color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isAdmin
                  ? 'No files or videos yet. Upload a PDF or add a video!'
                  : 'No files or videos available yet',
              style: TextStyle(
                color: isDarkMode
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (_videos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '🎬 دروس فيديو',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDarkMode
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
          for (final video in _videos)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _VideoTile(
                video: video,
                isDarkMode: isDarkMode,
                isAdmin: isAdmin,
                onPlay: () => showYouTubeVideoPlayer(context, video),
                onDelete: isAdmin ? () => _deleteVideo(video) : null,
              ),
            ),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8, bottom: 10),
              child: Text(
                '📄 ملفات PDF',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
        ],
        for (var i = 0; i < _files.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _FileTile(
            file: _files[i],
            isDarkMode: isDarkMode,
            isAdmin: isAdmin,
            isDownloading: _downloadingFiles.contains(_files[i].fileHash),
            onDownload: () => _downloadAndOpen(_files[i]),
            onDelete: isAdmin ? () => _deleteFile(_files[i]) : null,
          ),
        ],
      ],
    );
  }
}

// ─── Video Tile ────────────────────────────────────────────────────────────

class _VideoTile extends StatelessWidget {
  final UniversityVideo video;
  final bool isDarkMode;
  final bool isAdmin;
  final VoidCallback onPlay;
  final VoidCallback? onDelete;

  const _VideoTile({
    required this.video,
    required this.isDarkMode,
    required this.isAdmin,
    required this.onPlay,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('video-${video.id}'),
      direction: isAdmin ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      onDismissed: onDelete != null ? (_) => onDelete!() : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF1E293B).withValues(alpha: 0.6)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                LucideIcons.youtube,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'يوتيوب',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تشغيل',
              icon: const Icon(
                LucideIcons.play,
                color: Color(0xFFEF4444),
                size: 22,
              ),
              onPressed: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── File Tile ─────────────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final UniversityFile file;
  final bool isDarkMode;
  final bool isAdmin;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;

  const _FileTile({
    required this.file,
    required this.isDarkMode,
    required this.isAdmin,
    required this.isDownloading,
    required this.onDownload,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final sizeStr = _formatBytes(file.sizeBytes);
    final pagesStr =
        file.totalPages != null ? '${file.totalPages} pages' : null;

    return Dismissible(
      key: Key(file.id),
      direction: isAdmin ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      onDismissed: onDelete != null ? (_) => onDelete!() : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF1E293B)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            // PDF icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                LucideIcons.fileText,
                color: Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color:
                          isDarkMode ? Colors.white : const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        sizeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      if (pagesStr != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF475569)
                                : const Color(0xFFCBD5E1),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          pagesStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Download / Open button
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: isDownloading ? null : onDownload,
                icon: isDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        LucideIcons.download,
                        size: 16,
                        color: isDarkMode ? Colors.white : Colors.indigo,
                      ),
                label: Text(
                  isDownloading ? 'Opening...' : 'Open',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDownloading
                        ? Colors.grey
                        : (isDarkMode ? Colors.white : Colors.indigo),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDownloading
                      ? Colors.grey.withValues(alpha: 0.1)
                      : Colors.indigo.withValues(alpha: 0.1),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}