import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/university_folder.dart';
import '../../models/university_file.dart';
import '../../services/university_service.dart';
import '../../services/file_manager_service.dart';
import '../../providers/app_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CollegeCollectionWidget
//
// Lives inside "أقسامك" in the left sidebar as a closed folder. Clicking it
// expands to reveal the Supabase-backed university folders (المجموعة الجامعية).
// Clicking a folder shows its PDFs.
//
// File actions:
//   * Tap the file row  → opens the PDF in the viewer WITHOUT saving it into
//     any folder (ephemeral / view-only).
//   * Tap the install (download) button → small folder-picker popup; the file
//     is imported into the chosen class folder.
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
  bool _filesLoading = false;
  String? _filesError;

  /// Tracks which files are currently being opened (ephemeral, view-only).
  final Set<String> _openHashes = {};

  /// Files currently being installed (downloading) into a class folder.
  final Set<String> _installingHashes = {};

  /// Files already installed into a local class folder.
  final Set<String> _installedHashes = {};

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
          _foldersError = 'سجّل الدخول لعرض المجموعة الجامعية';
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
      if (_isExpanded) {
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
      _filesError = null;
    });
    _filesSub?.cancel();
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
  }

  @override
  void dispose() {
    _foldersSub?.cancel();
    _filesSub?.cancel();
    super.dispose();
  }

  // ── Install pipeline: download → pick target class → import ─────────────

  Future<void> _installPdf(UniversityFile file) async {
    final hash = file.fileHash;
    if (_installingHashes.contains(hash)) return;
    if (_installedHashes.contains(hash)) return;

    final app = context.read<AppProvider>();

    // Ensure "Quick Access" always exists so it appears in the picker.
    await app.ensureQuickAccessExists();

    if (app.classes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('أنشئ قسمًا أولاً لتثبيت الملف فيه'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    setState(() => _installingHashes.add(hash));

    try {
      // 1. Download (pure download, no Isar record yet) → local path.
      final localPath = await _universityService.downloadPdfToLocal(file);

      if (!mounted) return;

      // 2. Let the user pick the target class folder.
      final chosenClassId = await _pickClassFolder(app, file.name);
      if (!mounted) return;
      if (chosenClassId == null) return; // cancelled → abort install

      // 3. Import into the chosen folder (hash-deduped inside that folder).
      final fileManager = FileManagerService();
      if (!fileManager.isInitialized) {
        await fileManager.init();
      }
      final doc = await fileManager.importAndOpenPdf(
        localPath,
        classId: chosenClassId,
      );

      // 4. Re-hydrate + activate via the provider.
      await app.importPdfFromPath(doc.uuid, chosenClassId);

      if (!mounted) return;
      setState(() => _installedHashes.add(hash));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('✅ تم تثبيت "${file.name}"'),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('❌ فشل التثبيت: $e'),
              backgroundColor: Colors.red,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _installingHashes.remove(hash));
    }
  }

  /// Dialog listing the user's class folders; returns the chosen classId.
  /// Compact size: narrower than the device and capped height.
  Future<String?> _pickClassFolder(AppProvider app, String fileName) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          'تثبيت "$fileName"',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختر القسم الذي تريد تثبيت الملف فيه:',
                style: TextStyle(
                  fontSize: 12.5,
                  color: widget.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final cls in app.classes)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            LucideIcons.folder,
                            size: 18,
                            color: widget.isDarkMode
                                ? const Color(0xFF93C5FD)
                                : Colors.indigo.shade400,
                          ),
                          title: Text(
                            cls.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          onTap: () => Navigator.of(ctx).pop(cls.id),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
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
                          'المجموعة الجامعية',
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

  /// Compact folder row matching the "أقسامك" folder style in the sidebar.
  Widget _buildSidebarFolder(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final activeBg = isDark
        ? const Color(0xFF1E293B)
        : scheme.surfaceContainerHigh;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggleExpand,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: _isExpanded ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        _isExpanded
                            ? LucideIcons.folderOpen
                            : LucideIcons.folder,
                        size: 14,
                        color: const Color(0xFF60A5FA),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'المجموعة الجامعية',
                          style: TextStyle(
                            color: _isExpanded
                                ? const Color(0xFF60A5FA)
                                : widget.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isExpanded
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 16,
                  color: widget.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isDark ? const Color(0xFF1E293B) : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildExpandedTiles(isDark),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
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
      if (_openFolderId != null) ...[
        const Divider(height: 1, thickness: 1, color: Colors.transparent),
        ..._buildFilesList(isDark),
      ],
    ];
  }

  Widget _buildSidebarSubfolder(bool isDark, UniversityFolder folder) {
    final isOpen = _openFolderId == folder.id;
    return Column(
      children: [
        InkWell(
          onTap: () => _openFolder(folder),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isOpen ? activeSidebarBg(isDark) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  isOpen ? LucideIcons.folderOpen : LucideIcons.folder,
                  size: 13,
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
                      fontWeight: FontWeight.w500,
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
    if (_files.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'لا توجد ملفات في هذا المجلد',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
      ];
    }
    return [for (final file in _files) _buildFileTile(isDark, file)];
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

    if (_files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'لا توجد ملفات في هذا المجلد',
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
        for (final file in _files) _buildFileTile(isDark, file),
      ],
    );
  }

  Widget _buildFileTile(bool isDark, UniversityFile file) {
    final isBusy =
        _openHashes.contains(file.fileHash) ||
        _installingHashes.contains(file.fileHash);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Tap anywhere on the row → open the PDF without saving it anywhere.
        onTap: isBusy ? null : () => _openPdf(file),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.black.withValues(alpha: 0.01),
            border: Border(
              bottom: BorderSide(
                color: widget.panelBorder.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.fileText,
                  color: Colors.red,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.textPrimary,
                      ),
                    ),
                    Text(
                      _formatBytes(file.sizeBytes),
                      style: TextStyle(fontSize: 10.5, color: widget.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                // Install (download) button → small folder-picker popup.
                InkWell(
                  onTap: () => _installPdf(file),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (_installedHashes.contains(file.fileHash)
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF3B82F6))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _installedHashes.contains(file.fileHash)
                              ? LucideIcons.check
                              : LucideIcons.download,
                          size: 13,
                          color: _installedHashes.contains(file.fileHash)
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _installedHashes.contains(file.fileHash)
                              ? 'مثبّت'
                              : 'تثبيت',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _installedHashes.contains(file.fileHash)
                                ? (isDark
                                      ? const Color(0xFF86EFAC)
                                      : const Color(0xFF16A34A))
                                : (isDark
                                      ? const Color(0xFF93C5FD)
                                      : const Color(0xFF2563EB)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tap action: open the PDF in the viewer WITHOUT saving it into any folder.
  Future<void> _openPdf(UniversityFile file) async {
    final hash = file.fileHash;
    if (_openHashes.contains(hash)) return;
    setState(() => _openHashes.add(hash));

    try {
      final localPath = await _universityService.downloadPdfToLocal(file);
      if (!mounted) return;
      await context.read<AppProvider>().openEphemeralPdf(
        localPath,
        name: file.name,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('✅ تم فتح "${file.name}"'),
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
              content: Text('❌ فشل الفتح: $e'),
              backgroundColor: Colors.red,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _openHashes.remove(hash));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}