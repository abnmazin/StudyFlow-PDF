import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/university_folder.dart';
import '../../models/university_file.dart';
import '../../models/university_video.dart';
import '../../services/university_service.dart';
import '../../services/file_manager_service.dart';
import '../../providers/app_state.dart';
import 'youtube_player_w.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CollegeCollectionWidget
//
// Lives under "المكتبة الجامعية" in the left sidebar as a collapsible
// section. It reveals the Supabase-backed university folders; clicking a
// folder shows its PDFs.
//
// File actions:
//   * Tap the file row → downloads the PDF, saves it inside the local
//     "Quick Access" folder, then opens it — exactly like a local file.
// ─────────────────────────────────────────────────────────────────────────────

class CollegeCollectionWidget extends StatefulWidget {
  final bool isDarkMode;
  final Color panelBg;
  final Color panelBorder;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textMuted;

  /// When true, the header renders as a compact sidebar folder row
  /// (like class folders in "أقسامك") instead of a bordered card.
  final bool folderStyle;

  const CollegeCollectionWidget({
    super.key,
    required this.isDarkMode,
    required this.panelBg,
    required this.panelBorder,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    this.folderStyle = false,
  });

  @override
  State<CollegeCollectionWidget> createState() =>
      _CollegeCollectionWidgetState();
}

class _CollegeCollectionWidgetState extends State<CollegeCollectionWidget> {
  final UniversityService _universityService = UniversityService();

  bool _isExpanded = false;
  bool _foldersLoading = true;
  String? _foldersError;
  List<UniversityFolder> _folders = [];
  StreamSubscription<List<UniversityFolder>>? _foldersSub;

  /// Folder currently showing its PDFs inline (by folder id).
  String? _openFolderId;
  StreamSubscription<List<UniversityFile>>? _filesSub;
  List<UniversityFile> _files = [];
  StreamSubscription<List<UniversityVideo>>? _videosSub;
  List<UniversityVideo> _videos = [];
  bool _filesLoading = false;
  String? _filesError;

  /// Tracks which files are currently being opened (download + open).
  final Set<String> _openHashes = {};

  bool _serviceReady = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final app = context.read<AppProvider>();
    final user = app.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _foldersLoading = false;
          _foldersError = 'سجّل الدخول لعرض المكتبة الجامعية';
        });
      }
      return;
    }
    try {
      await _universityService.init(user);
      if (!_universityService.isReady) {
        if (mounted) {
          setState(() {
            _foldersLoading = false;
            _foldersError = 'لا يوجد معرف جامعة مرتبط بحسابك';
          });
        }
        return;
      }
      _serviceReady = true;
      // In sidebar (folderStyle) mode the folder list is always visible, so
      // load it immediately. In card mode it stays lazy until first expand.
      if (widget.folderStyle || _isExpanded) {
        _foldersLoading = true;
        _startFoldersStream();
      } else {
        if (mounted) {
          setState(() => _foldersLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _foldersLoading = false;
          _foldersError = e.toString();
        });
      }
    }
  }

  /// Expands/collapses the collection. Engines: first ever expand forces a
  /// fresh stream; lazy so a closed folder never loads anything.
  void _toggleExpand() {
    final expanding = !_isExpanded;
    setState(() {
      _isExpanded = expanding;
      if (expanding && _serviceReady) {
        _foldersLoading = true;
        _foldersError = null;
      }
    });
    if (expanding && _serviceReady) {
      _startFoldersStream();
    }
  }

  void _startFoldersStream() {
    _foldersSub?.cancel();
    _foldersSub = _universityService.streamFolders().listen(
      (folders) {
        if (mounted) {
          setState(() {
            _folders = folders;
            _foldersLoading = false;
            _foldersError = null;
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _foldersError = err.toString();
            _foldersLoading = false;
          });
        }
      },
    );
  }

  void _openFolder(UniversityFolder folder) {
    final nextId = _openFolderId == folder.id ? null : folder.id;
    setState(() {
      _openFolderId = nextId;
      _files = [];
      _videos = [];
      _filesError = null;
    });
    _filesSub?.cancel();
    _videosSub?.cancel();
    if (nextId == null) return;
    setState(() => _filesLoading = true);
    _filesSub = _universityService.streamFilesInFolder(folder.id).listen(
      (files) {
        if (mounted && _openFolderId == folder.id) {
          setState(() {
            _files = files;
            _filesLoading = false;
            _filesError = null;
          });
        }
      },
      onError: (err) {
        if (mounted && _openFolderId == folder.id) {
          setState(() {
            _filesError = err.toString();
            _filesLoading = false;
          });
        }
      },
    );
    _videosSub = _universityService.streamVideosInFolder(folder.id).listen(
      (videos) {
        if (mounted && _openFolderId == folder.id) {
          setState(() => _videos = videos);
        }
      },
      onError: (err) {
        debugPrint('⚠️ [College] Video stream error: $err');
      },
    );
  }

  @override
  void dispose() {
    _foldersSub?.cancel();
    _filesSub?.cancel();
    _videosSub?.cancel();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;

    if (widget.folderStyle) {
      return _buildSidebarFolder(isDark);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: widget.panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.panelBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header: collapsed folder (pinned) ─────────────────────────
          InkWell(
            onTap: _toggleExpand,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isExpanded ? LucideIcons.folderOpen : LucideIcons.folder,
                      size: 18,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المكتبة الجامعية',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: widget.textPrimary,
                          ),
                        ),
                        Text(
                          _foldersLoading && _isExpanded
                              ? 'جاري التحميل…'
                              : '${_folders.length} مجلد دراسي',
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 18,
                    color: widget.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded body: supabase folders ───────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isExpanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: widget.panelBorder,
                      ),
                      _buildFoldersBody(isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Renders the university folders DIRECTLY (no wrapper row) using exactly
  /// the same compact folder style as local class folders: each folder is a
  /// row, and clicking it shows its files inline underneath.
  Widget _buildSidebarFolder(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildExpandedTiles(isDark),
    );
  }

  List<Widget> _buildExpandedTiles(bool isDark) {
    if (_foldersLoading) {
      return const [
        Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    if (_foldersError != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _foldersError!,
            style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _foldersLoading = true;
              _foldersError = null;
            });
            _startFoldersStream();
          },
          icon: const Icon(LucideIcons.refreshCw, size: 14),
          label: const Text('إعادة المحاولة', style: TextStyle(fontSize: 12)),
        ),
      ];
    }
    if (_folders.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'لا توجد مجلدات بعد',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
      ];
    }

    return [
      for (final folder in _folders)
        _buildSidebarSubfolder(isDark, folder),
    ];
  }

  Widget _buildSidebarSubfolder(bool isDark, UniversityFolder folder) {
    final isOpen = _openFolderId == folder.id;
    final scheme = Theme.of(context).colorScheme;
    final isAdmin = context.read<AppProvider>().currentUser?.isAdmin ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder row wrapped in a DragTarget so admins can drop a dragged
        // folder onto it to reorder (mirrors local class folders).
        DragTarget<Map<String, String>>(
          onWillAccept: (data) =>
              data != null &&
              data['dragType'] == 'uniFolder' &&
              data['folderId'] != null &&
              data['folderId'] != folder.id,
          onAccept: (data) {
            final draggedId = data['folderId'];
            if (draggedId != null) _reorderFolders(draggedId, folder.id);
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return InkWell(
              onTap: () => _openFolder(folder),
              borderRadius: BorderRadius.circular(4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      isHovering
                          ? const Color(0x223B82F6)
                          : (isOpen
                                ? activeSidebarBg(isDark)
                                : Colors.transparent),
                  borderRadius: BorderRadius.circular(4),
                  border: isHovering
                      ? Border.all(color: const Color(0xFF3B82F6), width: 1)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      isOpen ? LucideIcons.folderOpen : LucideIcons.folder,
                      size: 13,
                      color: isDark
                          ? const Color(0xFF93C5FD)
                          : Colors.indigo.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isOpen
                              ? const Color(0xFF60A5FA)
                              : widget.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      isOpen
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 14,
                      color: widget.textMuted,
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 4),
                      Draggable<Map<String, String>>(
                        data: {
                          'dragType': 'uniFolder',
                          'folderId': folder.id,
                        },
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 200,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  LucideIcons.folder,
                                  size: 14,
                                  color: Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    folder.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFFF1F5F9),
                                      decoration: TextDecoration.none,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        childWhenDragging: Icon(
                          LucideIcons.gripVertical,
                          size: 14,
                          color: widget.textMuted.withOpacity(0.35),
                        ),
                        child: Icon(
                          LucideIcons.gripVertical,
                          size: 14,
                          color: widget.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        // Files of the open folder appear inline underneath it, exactly like
        // local PDFs under a class folder.
        if (isOpen)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildFilesList(isDark),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Color activeSidebarBg(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return isDark ? const Color(0xFF1E293B) : scheme.surfaceContainerHigh;
  }

  List<Widget> _buildFilesList(bool isDark) {
    if (_filesLoading) {
      return const [
        Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    if (_filesError != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'تعذر تحميل الملفات: $_filesError',
            style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
          ),
        ),
      ];
    }
    if (_files.isEmpty && _videos.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'لا توجد ملفات أو فيديوهات في هذا المجلد',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
      ];
    }
    return [
      if (_videos.isNotEmpty) ...[
        for (final video in _videos) _buildVideoTile(isDark, video),
        const SizedBox(height: 4),
      ],
      for (final file in _files)
        _buildFileTile(isDark, file, _openFolderId ?? ''),
    ];
  }

  /// Drag & drop: reorder a folder in front of [targetFolderId]. The batch
  /// write in the service syncs the new order to every member in real time.
  Future<void> _reorderFolders(String draggedFolderId, String targetFolderId) async {
    if (draggedFolderId == targetFolderId) return;
    final user = context.read<AppProvider>().currentUser;
    if (user == null) return;
    try {
      if (!_universityService.isReady) await _universityService.init(user);
      await _universityService.reorderFolders(
        draggedFolderId: draggedFolderId,
        targetFolderId: targetFolderId,
      );
    } catch (e) {
      debugPrint('📂 [College] Folder reorder failed: $e');
    }
  }

  /// Drag & drop: reorder a file in front of [targetFileId] within [folderId].
  Future<void> _reorderFiles(
    String folderId,
    String draggedFileId,
    String targetFileId,
  ) async {
    if (draggedFileId == targetFileId) return;
    final user = context.read<AppProvider>().currentUser;
    if (user == null) return;
    try {
      if (!_universityService.isReady) await _universityService.init(user);
      await _universityService.reorderFiles(
        folderId: folderId,
        draggedFileId: draggedFileId,
        targetFileId: targetFileId,
      );
    } catch (e) {
      debugPrint('🗂️ [College] File reorder failed: $e');
    }
  }

  Widget _buildFoldersBody(bool isDark) {
    if (_foldersLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_foldersError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              LucideIcons.cloudOff,
              size: 22,
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              _foldersError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _foldersLoading = true;
                  _foldersError = null;
                });
                _startFoldersStream();
              },
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('إعادة المحاولة', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (_folders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              LucideIcons.inbox,
              size: 22,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'لا توجد مجلدات بعد',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final folder in _folders)
          _buildFolderTile(isDark, folder),
        if (_filesLoading || _filesError != null || _files.isNotEmpty)
          const Divider(height: 1, thickness: 1, color: Colors.transparent),
        if (_openFolderId != null) _buildFilesBody(isDark),
      ],
    );
  }

  Widget _buildFolderTile(bool isDark, UniversityFolder folder) {
    final isOpen = _openFolderId == folder.id;
    return Column(
      children: [
        InkWell(
          onTap: () => _openFolder(folder),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
            child: Row(
              children: [
                Icon(
                  isOpen ? LucideIcons.folderOpen : LucideIcons.folder,
                  size: 16,
                  color: isDark ? const Color(0xFF93C5FD) : Colors.indigo.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: widget.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  isOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 14,
                  color: widget.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (!isOpen)
          Divider(
            height: 1,
            thickness: 1,
            color: widget.panelBorder.withValues(alpha: 0.6),
          ),
      ],
    );
  }

  Widget _buildFilesBody(bool isDark) {
    if (_filesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_filesError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'تعذر تحميل الملفات: $_filesError',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
        ),
      );
    }

    if (_files.isEmpty && _videos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'لا توجد ملفات أو فيديوهات في هذا المجلد',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_videos.isNotEmpty) ...[
          for (final video in _videos) _buildVideoTile(isDark, video),
          const SizedBox(height: 4),
        ],
        for (final file in _files)
          _buildFileTile(isDark, file, _openFolderId ?? ''),
      ],
    );
  }

  Widget _buildVideoTile(bool isDark, UniversityVideo video) {
    final folderId = _openFolderId ?? '';
    final isAdmin = context.read<AppProvider>().currentUser?.isAdmin ?? false;

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        // Tap anywhere on the row → open the embedded YouTube player.
        onTap: () => showYouTubeVideoPlayer(context, video),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.youtube,
                size: 14,
                color: Color(0xFFF87171),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  video.title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 2),
                Draggable<Map<String, String>>(
                  data: {
                    'dragType': 'uniVideo',
                    'folderId': folderId,
                    'videoId': video.id,
                  },
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.youtube,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              video.title,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  childWhenDragging: Icon(
                    LucideIcons.gripVertical,
                    size: 13,
                    color: widget.textMuted.withOpacity(0.35),
                  ),
                  child: Icon(
                    LucideIcons.gripVertical,
                    size: 13,
                    color: widget.textMuted,
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: const Icon(
                    LucideIcons.trash2,
                    size: 13,
                    color: Color(0xFFF87171),
                  ),
                  tooltip: 'حذف الفيديو',
                  onPressed: () => _deleteVideo(video),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return DragTarget<Map<String, String>>(
      onWillAccept: (data) =>
          data != null &&
          data['dragType'] == 'uniVideo' &&
          data['videoId'] != null &&
          data['videoId'] != video.id &&
          data['folderId'] == folderId,
      onAccept: (data) {
        final draggedId = data['videoId'];
        if (draggedId != null) _reorderVideos(folderId, draggedId, video.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isHovering
                ? const Color(0x22EF4444)
                : Colors.transparent,
            border: isHovering
                ? Border.all(color: const Color(0xFFEF4444), width: 1)
                : null,
          ),
          child: child,
        );
      },
    );
  }

  /// Drag & drop: reorder a video in front of [targetVideoId] within [folderId].
  Future<void> _reorderVideos(
    String folderId,
    String draggedVideoId,
    String targetVideoId,
  ) async {
    if (draggedVideoId == targetVideoId) return;
    final user = context.read<AppProvider>().currentUser;
    if (user == null) return;
    try {
      if (!_universityService.isReady) await _universityService.init(user);
      await _universityService.reorderVideos(
        folderId: folderId,
        draggedVideoId: draggedVideoId,
        targetVideoId: targetVideoId,
      );
    } catch (e) {
      debugPrint('🎬 [College] Video reorder failed: $e');
    }
  }

  /// Deletes a video link (Admin only).
  Future<void> _deleteVideo(UniversityVideo video) async {
    final user = context.read<AppProvider>().currentUser;
    if (user == null) return;
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
        if (!_universityService.isReady) await _universityService.init(user);
        await _universityService.deleteVideo(video);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🗑️ تم حذف الفيديو')),
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

  Widget _buildFileTile(bool isDark, UniversityFile file, String folderId) {
    final isBusy = _openHashes.contains(file.fileHash);
    final isAdmin = context.read<AppProvider>().currentUser?.isAdmin ?? false;

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        // Tap anywhere on the row → download + save to Quick Access + open.
        onTap: isBusy ? null : () => _openPdf(file),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.fileText,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.name,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (isAdmin && !isBusy) ...[
                const SizedBox(width: 2),
                Draggable<Map<String, String>>(
                  data: {
                    'dragType': 'uniFile',
                    'folderId': folderId,
                    'fileId': file.id,
                  },
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.fileText,
                            size: 14,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              file.name,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFF1F5F9),
                                decoration: TextDecoration.none,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  childWhenDragging: Icon(
                    LucideIcons.gripVertical,
                    size: 13,
                    color: widget.textMuted.withOpacity(0.35),
                  ),
                  child: Icon(
                    LucideIcons.gripVertical,
                    size: 13,
                    color: widget.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return DragTarget<Map<String, String>>(
      onWillAccept: (data) =>
          data != null &&
          data['dragType'] == 'uniFile' &&
          data['fileId'] != null &&
          data['fileId'] != file.id &&
          data['folderId'] == folderId,
      onAccept: (data) {
        final draggedId = data['fileId'];
        if (draggedId != null) _reorderFiles(folderId, draggedId, file.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isHovering ? const Color(0x223B82F6) : Colors.transparent,
            border: isHovering
                ? Border.all(color: const Color(0xFF3B82F6), width: 1)
                : null,
          ),
          child: child,
        );
      },
    );
  }

  /// Tap action: download the PDF, save it inside the local "Quick Access"
  /// folder, then open it — exactly like a local file.
  Future<void> _openPdf(UniversityFile file) async {
    final hash = file.fileHash;
    if (_openHashes.contains(hash)) return;
    setState(() => _openHashes.add(hash));

    try {
      final app = context.read<AppProvider>();

      // 1. Make sure "Quick Access" exists as the download destination.
      await app.ensureQuickAccessExists();
      final fileManager = FileManagerService();
      if (!fileManager.isInitialized) await fileManager.init();
      final quickAccess = await fileManager.getOrCreateQuickAccessFolder();

      // 2. Download to a local path (no record yet).
      final localPath = await _universityService.downloadPdfToLocal(file);
      if (!mounted) return;

      // 3. Import into "Quick Access" (hash-deduped) + hydrate + open.
      final doc = await fileManager.importAndOpenPdf(
        localPath,
        classId: quickAccess.uuid,
      );
      await app.importPdfFromPath(doc.uuid, quickAccess.uuid);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('✅ تم تحميل وفتح "${file.name}"'),
              duration: const Duration(seconds: 2),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('❌ فشل التحميل: $e'),
              backgroundColor: Colors.red,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _openHashes.remove(hash));
    }
  }
}