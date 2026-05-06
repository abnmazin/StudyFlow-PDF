import 'package:pdfrx/pdfrx.dart' hide PdfDocument;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'dart:ui';
import '../services/translation_service.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../models/app_user.dart';
import '../models/print_settings.dart'; // NEW
import '../services/print_service.dart'; // NEW
import 'viewer_components/viewer_toolbar.dart';
import 'viewer_components/viewer_right_panel.dart';
import 'viewer_components/print_dialog.dart';
import '../painters/highlight_painter.dart';
import 'draggable_text_widget.dart';
import '../models/isar_models.dart'; // NEW: for PdfDocument
import '../services/file_manager_service.dart'; // NEW: for getRecentDocuments
import 'dialogs/merge_pdf_dialog.dart'; // NEW
import 'dialogs/images_to_pdf_dialog.dart'; // NEW
import '../services/sync_service.dart';
import '../utils/responsive_utils.dart';

part 'pdf_viewer_widget_dashboard.dart';
part 'pdf_viewer_widget_actions.dart';
part 'pdf_viewer_widget_print.dart';
part 'pdf_viewer_widget_gestures.dart';
part 'pdf_viewer_widget_style.dart';
part 'pdf_viewer_widget_overlay.dart';

class PDFViewerWidget extends StatefulWidget {
  const PDFViewerWidget({super.key});

  @override
  State<PDFViewerWidget> createState() => _PDFViewerWidgetState();
}

class _PDFViewerWidgetState extends State<PDFViewerWidget> {
  late PdfViewerController _pdfController;
  late PdfViewerController _secondaryPdfController;
  int? _lastModified;
  int? _secondaryLastModified;
  String? _currentPdfId;
  String? _secondaryCurrentPdfId;
  // Hard isolation mode: fully unmount PdfViewer during print pipeline.
  bool _isPrintingMode = false;

  bool _isRightPanelOpen = false;
  bool _isPointerOverAiChat = false;
  bool _isShapesPaletteVisible = false;
  bool _isSettingsMode = false;
  int _rightPanelTabIndex = 0; // 0: Tools, 1: AI, 2: Translate
  String? _currentListeningCode;
  String?
  _currentListeningFileHash; // Track which PDF hash we are listening for
  late AppProvider _app;

  // _tool is now managed by AppProvider.currentTool
  ToolType get _tool => context.read<AppProvider>().currentTool;

  // â”€â”€ Per-tool colors: changing one never affects another â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Color _penColor = const Color(0xFF000000);
  Color _highlightColor = const Color(0xFFFFFF00);
  Color _shapeStrokeColor = const Color(0xFF000000); // arrow/rect/circle
  Color _textColor = const Color(0xFF000000);
  String _textFontFamily = 'Times New Roman';

  /// Current stroke/main color for whatever tool is active.
  Color get _currentColor {
    switch (_tool) {
      case ToolType.pen:
        return _penColor;
      case ToolType.highlight:
        return _highlightColor;
      case ToolType.text:
        return _textColor;
      default: // arrow, rectangle, circle, cursor
        return _shapeStrokeColor;
    }
  }

  Color _colorForTool(ToolType tool) {
    switch (tool) {
      case ToolType.pen:
        return _penColor;
      case ToolType.highlight:
        return _highlightColor;
      case ToolType.text:
        return _textColor;
      default:
        return _shapeStrokeColor;
    }
  }

  // â”€â”€ Per-tool stroke widths: changing one never affects another â”€â”€â”€â”€â”€â”€â”€â”€
  final Map<ToolType, double> _toolStrokeWidths = {
    ToolType.pen: 2.0,
    ToolType.highlight: 15.0,
    ToolType.arrow: 4.0,
    ToolType.rectangle: 2.0,
    ToolType.circle: 2.0,
  };

  /// Current stroke width for whatever tool is active.
  double get _currentStrokeWidth => _toolStrokeWidths[_tool] ?? 2.0;
  double _fontSize = 14.0;
  bool _isBold = false;
  bool _isLatex = false; // NEW: LaTeX annotation mode
  bool _showBorder = true;
  Color _borderColor = const Color(0xFF000000); // Black border by default
  Color _textBgColor = Colors.transparent;
  Color _shapeFillColor = Colors.transparent;
  // Current drawing state
  List<Offset>? _currentPath;
  int _currentPage = -1;
  bool _isProcessing = false; // Processing lock
  Timer? _scrollDebounce;
  Timer? _scrollMaintenanceDebounce;
  Timer? _autoFitDebounce;
  int _lastReportedPage = 0;
  int _lastMemoryTrimAt = 0;
  static const int _defaultTrimDelayMs = 500;
  static const int _defaultTrimMinIntervalMs = 6000;
  int get _trimDelayMs =>
      context.read<AppProvider>().devSettings.trimDelayMs ??
      _defaultTrimDelayMs;
  int get _trimMinIntervalMs =>
      context.read<AppProvider>().devSettings.trimMinIntervalMs ??
      _defaultTrimMinIntervalMs;
  Size? _lastPdfViewSize;
  bool _isAutoFitting = false;
  bool _autoFitEnabled = true;

  String? _editingCommentId;

  // Hard Reload Tracking
  bool _needsReload = false;
  int _targetPageAfterReload = 1;
  // double _targetZoomAfterReload = 1.0; // Unused

  final FocusNode _searchFocusNode = FocusNode(); // NEW: Focus node for search
  PdfTextSearcher? _textSearcher;
  bool _isSearchVisible = false;
  PdfTextSelection? _textSelection;
  bool _isTextSelectionMenuVisible = false;
  bool _isTranslating = false;
  String? _translatedText;
  bool _suppressTextSelection =
      false; // Suppress zombie refire after clearing selection
  int _selectionChangeToken = 0;
  DateTime _ignoreSelectionEventsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? _selectedHighlightId; // NEW: Track selected shape
  Offset? _shapeTransformStart;
  Rect? _shapeTransformInitialBounds;
  List<Offset>? _shapeTransformOriginalPath;
  bool _isMovingSelectedShape = false;
  int? _activeResizeHandleIndex;
  MouseCursor _shapeHoverCursor = SystemMouseCursors.basic;

  StreamSubscription? _sessionSub;
  StreamSubscription? _annotationsSub;

  Future<void> _handleTextSelectionChange(PdfTextSelection? selection) async {
    if (!mounted) return;

    // Null selection always clears UI immediately.
    if (selection == null) {
      setState(() {
        _textSelection = null;
        _isTextSelectionMenuVisible = false;
      });
      return;
    }

    if (_suppressTextSelection) return;
    if (DateTime.now().isBefore(_ignoreSelectionEventsUntil)) return;

    final token = ++_selectionChangeToken;

    try {
      final ranges = await selection.getSelectedTextRanges();
      if (!mounted) return;
      if (token != _selectionChangeToken) return;
      if (_suppressTextSelection) return;
      if (DateTime.now().isBefore(_ignoreSelectionEventsUntil)) return;

      if (ranges.isEmpty) {
        setState(() {
          _textSelection = null;
          _isTextSelectionMenuVisible = false;
        });
        return;
      }

      setState(() {
        _textSelection = selection;
        _isTextSelectionMenuVisible = true;
      });
    } catch (_) {
      // Ignore transient selection failures from underlying PDF engine.
    }
  }

  Future<void> _handleTranslate() async {
    if (_textSelection == null) return;

    setState(() {
      _isTranslating = true;
      _translatedText = "جاري الترجمة...";
    });

    try {
      final text = await _textSelection!.getSelectedText();
      final result = await TranslationService().translate(text, _app);
      if (mounted) {
        setState(() {
          _translatedText = result;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _translatedText = "تعذر الترجمة: $e";
          _isTranslating = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onControllerChanged);
    _secondaryPdfController = PdfViewerController();
    _secondaryPdfController.addListener(_onControllerChanged);

    // Phase 11: Real-time Session Status Listener
    _app = context.read<AppProvider>();
    _app.addListener(_onAppStatusChanged);
  }

  void _onAppStatusChanged() {
    if (!mounted) return;
    _setupSessionListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initial setup handled by initState + post-frame or immediate call
    _setupSessionListener();
  }

  void _setupSessionListener() {
    final app = context.read<AppProvider>();
    final code = app.currentSessionCode;
    final user = app.currentUser;
    final pdf = app.activePdf;
    final fileHash = pdf?.fileHash;

    // 1. If session code changed, user logged out, or not a member, reset
    if (code == null ||
        user == null ||
        user.role != 'member' ||
        fileHash == null) {
      if (_sessionSub != null || _annotationsSub != null) {
        _sessionSub?.cancel();
        _sessionSub = null;
        _annotationsSub?.cancel();
        _annotationsSub = null;
        _currentListeningCode = null;
        _currentListeningFileHash = null;
      }
      return;
    }

    // 2. If we are already listening to a different code OR different PDF hash, cancel and restart
    if ((_sessionSub != null || _annotationsSub != null) &&
        (_currentListeningCode != code ||
            _currentListeningFileHash != fileHash)) {
      _sessionSub?.cancel();
      _sessionSub = null;
      _annotationsSub?.cancel();
      _annotationsSub = null;
    }

    // 3. Start listener if not active
    if (_sessionSub == null) {
      _currentListeningCode = code;
      _currentListeningFileHash = fileHash;

      _sessionSub = SyncService().watchSession(code).listen((snap) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // SCENARIO 3: SESSION DELETED / ENDED
          if (!snap.exists) {
            _sessionSub?.cancel();
            _annotationsSub
                ?.cancel(); // CANCEL INSTANTLY SO SCREEN DOES NOT WIPE
            _sessionSub = null;
            _annotationsSub = null;
            _currentListeningCode = null;
            app.setSessionCode(null);
            // Keep local annotations intact!
            return;
          }

          final data = snap.data()!;
          final kicked =
              (data['kicked_usernames'] as List?)?.cast<String>() ?? [];
          final isPurge =
              data['notesPurgeFor'] ==
              user.username; // Assuming this flag exists

          // SCENARIO 1 & 2: KICKED (WITH OR WITHOUT PURGE)
          if (kicked.contains(user.username)) {
            _sessionSub?.cancel();
            _annotationsSub?.cancel(); // CANCEL INSTANTLY
            _sessionSub = null;
            _annotationsSub = null;
            _currentListeningCode = null;
            app.setSessionCode(null);

            // If Purge & Kick: Only keep my own drawings
            if (isPurge) {
              final pdf = app.activePdf;
              if (pdf != null) {
                pdf.highlights.removeWhere(
                  (h) => h.createdBy != null && h.createdBy != user.username,
                );
                pdf.comments.removeWhere(
                  (c) => c.createdBy != null && c.createdBy != user.username,
                );
                app.saveStateNow(); // Flush to disk immediately
              }
            }

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('تم إنهاء الجلسة'),
                content: const Text('لقد تم إنهاء وصولك لهذه الجلسة.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('حسناً'),
                  ),
                ],
              ),
            );
            return;
          }
        });
      });

      // Real-time annotation stream intentionally disabled.
      // Sync is now manual only via toolbar button / Ctrl+S.
      _annotationsSub = null;
    }
  }

  void _onControllerChanged() {
    // MEMORY FIX: Removed blind setState(() {}).
    // Firing setState on every scroll pixel causes a 1.5GB native memory leak.
    // If specific UI elements (like the slider) need to update, they should use
    // AnimatedBuilder or ValueListenableBuilder tied directly to the controller.
  }

  PdfViewerController _syncViewerController({
    required PdfViewerController controller,
    required PdfItem? pdf,
    required bool isSecondary,
  }) {
    if (pdf == null) return controller;

    final currentPdfId = isSecondary ? _secondaryCurrentPdfId : _currentPdfId;
    final lastModified = isSecondary ? _secondaryLastModified : _lastModified;

    if (currentPdfId == null ||
        currentPdfId != pdf.id ||
        lastModified != pdf.lastModified) {
      controller.removeListener(_onControllerChanged);
      final nextController = PdfViewerController();
      nextController.addListener(_onControllerChanged);

      if (isSecondary) {
        _secondaryPdfController = nextController;
        _secondaryCurrentPdfId = pdf.id;
        _secondaryLastModified = pdf.lastModified;
      } else {
        _pdfController = nextController;
        _currentPdfId = pdf.id;
        _lastModified = pdf.lastModified;
        _isProcessing = false;
        _textSearcher = null;
        _isSearchVisible = false;
        _textSelection = null;
        _isTextSelectionMenuVisible = false;
      }

      return nextController;
    }

    return controller;
  }

  @override
  void dispose() {
    _app.removeListener(_onAppStatusChanged);
    _pdfController.removeListener(_onControllerChanged);
    _secondaryPdfController.removeListener(_onControllerChanged);
    _scrollDebounce?.cancel();
    _scrollMaintenanceDebounce?.cancel();
    _autoFitDebounce?.cancel();
    _searchFocusNode.dispose();
    _textSearcher?.dispose();
    _sessionSub?.cancel();
    _annotationsSub?.cancel();
    super.dispose();
  }

  // â”€â”€â”€ UNDO HANDLER: Global Ctrl+Z / Cmd+Z â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Handles undo action with smart detection of text field focus.
  /// If a text field is currently focused (like DraggableTextWidget),
  /// we don't override the native text undo. Otherwise, we undo the last
  /// annotation (highlight or comment).
  void _handleUndo(AppProvider app, String? editingCommentId) {
    // Check if actively editing a comment (in text field)
    // If so, let the text field handle undo natively
    if (editingCommentId != null) {
      debugPrint('âŒ¨ï¸  Undo: Text editor active, skipping global undo');
      return;
    }

    // Check if search box is visible and might have focus
    if (_isSearchVisible) {
      debugPrint(
        'âŒ¨ï¸  Undo: Search box active, proceeding with global undo',
      );
    }

    // Execute global undo
    debugPrint('ðŸ”™ Undo: Reverting last annotation...');
    app.undoLastAction();
  }

  void _handleRedo(AppProvider app, String? editingCommentId) {
    if (editingCommentId != null) {
      debugPrint('âŒ¨ï¸  Redo: Text editor active, skipping global redo');
      return;
    }

    debugPrint('â†ªï¸ Redo: Reapplying last annotation...');
    app.redoLastAction();
  }

  Future<void> _syncNow() async {
    final app = context.read<AppProvider>();
    if (app.isSyncing) return;
    if (app.currentSessionCode == null || app.activePdf == null) return;

    try {
      await app.performBidirectionalSync();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تمت المزامنة بنجاح. تم تحديث وحذف العناصر غير المتطابقة.',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('فشل التزامن: $e')));
          }
        });
      }
    }
  }

  void _activateTool(ToolType nextTool) {
    final app = context.read<AppProvider>();
    if (nextTool != ToolType.cursor && _isPointerOverAiChat) {
      _isPointerOverAiChat = false;
    }
    setState(() {
      _isSettingsMode = false;

      // Leaving selection mode should clear selected shape visuals/state.
      if (nextTool != ToolType.select) {
        _selectedHighlightId = null;
        _endShapeTransform();
        _shapeHoverCursor = SystemMouseCursors.basic;
      }
    });

    // Delegate to Provider for global tool state & sync triggering
    app.setCurrentTool(nextTool);
  }

  void _setAiChatPointerHover(bool isHovering) {
    if (_isPointerOverAiChat == isHovering) return;
    setState(() {
      _isPointerOverAiChat = isHovering;
    });
  }

  void _maybeTrimWindowsMemory({bool force = false, int minIntervalMs = 1800}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastMemoryTrimAt < minIntervalMs) {
      return;
    }
    _lastMemoryTrimAt = now;
    _trimWindowsMemory();
  }

  void _schedulePostScrollMaintenance() {
    _scrollMaintenanceDebounce?.cancel();
    _scrollMaintenanceDebounce = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      Future.delayed(Duration(milliseconds: _trimDelayMs), () {
        if (!mounted) return;

        bool isStillScrolling = false;
        try {
          final dynamic controller = _pdfController;
          final Iterable<dynamic> positions =
              (controller.positions as Iterable<dynamic>? ?? const []);
          isStillScrolling = positions.any(
            (p) => p.userScrollDirection != ScrollDirection.idle,
          );
        } catch (_) {
          // Some pdfrx controller builds do not expose `positions`.
          isStillScrolling = false;
        }

        if (isStillScrolling) return;

        _maybeTrimWindowsMemory(minIntervalMs: _trimMinIntervalMs);
      });
    });
  }

  ToolType? _selectedAnnotationTool(PdfItem? pdf) {
    if (_selectedHighlightId == null || pdf == null) return null;
    final selected = pdf.highlights
        .where((h) => h.id == _selectedHighlightId)
        .firstOrNull;
    if (selected == null) return null;
    return _highlightTypeToToolType(selected.type);
  }

  ToolType _panelTool(PdfItem? pdf) {
    if (_tool != ToolType.select) return _tool;
    return _selectedAnnotationTool(pdf) ?? _tool;
  }

  String? _selectedShapeAuthor(PdfItem? pdf, AppProvider app) {
    if (_selectedHighlightId == null || pdf == null) return null;
    final selected = pdf.highlights
        .where((h) => h.id == _selectedHighlightId)
        .firstOrNull;
    final author = selected?.createdBy?.trim();
    if (author != null && author.isNotEmpty) {
      final username = app.currentUser?.username.trim();
      final displayName = app.currentUser?.displayName.trim();
      if (username != null &&
          username.isNotEmpty &&
          displayName != null &&
          displayName.isNotEmpty &&
          author == username) {
        return displayName;
      }
      return author;
    }

    // Legacy fallback: old local highlights may not carry createdBy metadata.
    final fallback = app.currentUser?.displayName.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  String? _selectedCommentAuthor(PdfItem? pdf, AppProvider app) {
    final commentId = app.activeEditingCommentId;
    if (commentId == null || pdf == null) return null;
    final selected = pdf.comments
        .where((comment) => comment.id == commentId)
        .firstOrNull;
    final author = selected?.createdBy?.trim();
    if (author == null || author.isEmpty) return null;

    final username = app.currentUser?.username.trim();
    final displayName = app.currentUser?.displayName.trim();
    if (username != null &&
        username.isNotEmpty &&
        displayName != null &&
        displayName.isNotEmpty &&
        author == username) {
      return displayName;
    }

    return author;
  }

  bool _isTypingInTextField() {
    try {
      final focused = FocusManager.instance.primaryFocus;
      final context = focused?.context;
      if (context == null || !context.mounted) return false;

      if (context.widget is EditableText) return true;
      if (context.findAncestorWidgetOfExactType<EditableText>() != null) {
        return true;
      }

      final renderObject = context.findRenderObject();
      if (renderObject == null) return false;
      final renderType = renderObject.runtimeType.toString();
      return renderType.toLowerCase().contains('editable');
    } catch (e) {
      // Safety: in case of "Looking up a deactivated widget's ancestor is unsafe"
      // or other transient errors during context lookup.
      return false;
    }
  }

  void _runShortcut(VoidCallback action, {bool ignoreTyping = true}) {
    // By default, run shortcuts even when typing (ignoreTyping=true)
    // Some single-letter shortcuts (H, E, P, T) should NOT run when typing
    if (!ignoreTyping && _isTypingInTextField()) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    // PERFORMANCE: Use read instead of watch to prevent full rebuilds
    // Only rebuild when the active PDFs or split mode changes using Selector.
    final (
      pdf: pdf,
      secondaryPdf: secondaryPdf,
      isSplitMode: isSplitMode,
      currentTool: _,
      isDarkMode: isDarkMode,
    ) = context
        .select<
          AppProvider,
          ({
            PdfItem? pdf,
            PdfItem? secondaryPdf,
            bool isSplitMode,
            ToolType currentTool,
            bool isDarkMode,
          })
        >(
          (app) => (
            pdf: app.activePdf,
            secondaryPdf: app.secondaryPdf,
            isSplitMode: app.isSplitMode,
            currentTool: app.currentTool,
            isDarkMode: app.isDarkMode,
          ),
        );
    final app = context.read<AppProvider>();

    final primaryController = _syncViewerController(
      controller: _pdfController,
      pdf: pdf,
      isSecondary: false,
    );
    final secondaryController = _syncViewerController(
      controller: _secondaryPdfController,
      pdf: secondaryPdf,
      isSecondary: true,
    );

    final selectedAnnotationTool = _selectedAnnotationTool(pdf);
    final selectedShapeAuthor = _selectedShapeAuthor(pdf, app);
    final selectedCommentAuthor = _selectedCommentAuthor(pdf, app);
    final panelTool = _panelTool(pdf);

    // Strict Controller Cycle Management
    if (pdf != null) {
      if (_currentPdfId == null) {
        // First load
        _currentPdfId = pdf.id;
        _lastModified = pdf.lastModified;
        if (app.currentSessionCode != null && pdf.fileHash != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncNow();
          });
        }
      } else if (_currentPdfId != pdf.id || _lastModified != pdf.lastModified) {
        // Detected change or modification - FORCE RESET
        _pdfController.removeListener(_onControllerChanged);
        // _pdfController.dispose(); // Not available in pdfrx controller
        _pdfController = PdfViewerController();
        _pdfController.addListener(_onControllerChanged);
        _currentPdfId = pdf.id;
        _lastModified = pdf.lastModified;
        // Optionally reset processing lock to be safe
        _isProcessing = false;
        _textSearcher = null;
        _isSearchVisible = false;
        _textSelection = null;
        _isTextSelectionMenuVisible = false;
        if (app.currentSessionCode != null && pdf.fileHash != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncNow();
          });
        }
      }
    }

    return AnimatedBuilder(
      animation: FocusManager.instance,
      builder: (context, _) {
        final isTypingNow = _isTypingInTextField();
        // Only disable shortcuts if no PDF or editing comment
        // Allow shortcuts even when typing - individual shortcuts can override this
        final shortcutsDisabled = _editingCommentId != null || pdf == null;

        return CallbackShortcuts(
          bindings: shortcutsDisabled
              ? <ShortcutActivator, VoidCallback>{}
              : {
                  const SingleActivator(LogicalKeyboardKey.keyH): () =>
                      _runShortcut(() => _activateTool(ToolType.highlight), ignoreTyping: false),
                  const SingleActivator(LogicalKeyboardKey.keyE): () =>
                      _runShortcut(() => _activateTool(ToolType.eraser), ignoreTyping: false),
                  const SingleActivator(LogicalKeyboardKey.keyP): () =>
                      _runShortcut(() => _activateTool(ToolType.pen), ignoreTyping: false),
                  const SingleActivator(LogicalKeyboardKey.keyT): () =>
                      _runShortcut(() => _activateTool(ToolType.text), ignoreTyping: false),
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      _runShortcut(() => _activateTool(ToolType.cursor), ignoreTyping: true),
                  const SingleActivator(LogicalKeyboardKey.keyV): () =>
                      _runShortcut(() => _activateTool(ToolType.cursor), ignoreTyping: true),
                  const SingleActivator(
                    LogicalKeyboardKey.keyP,
                    control: true,
                  ): () =>
                      _runShortcut(() => _showPrintDialog(pdf), ignoreTyping: true),
                  const SingleActivator(
                    LogicalKeyboardKey.keyF,
                    control: true,
                  ): () => _runShortcut(() {
                    setState(() {
                      if (_textSearcher != null) _isSearchVisible = true;
                    });
                  }, ignoreTyping: true),
                  const SingleActivator(
                    LogicalKeyboardKey.keyL,
                    control: true,
                  ): () => _runShortcut(() {
                    app.toggleSidebar();
                    _forcePdfRelayout();
                  }, ignoreTyping: true),
                  const SingleActivator(
                    LogicalKeyboardKey.keyR,
                    control: true,
                  ): () => _runShortcut(() {
                    setState(() => _isRightPanelOpen = !_isRightPanelOpen);
                    _forcePdfRelayout();
                  }, ignoreTyping: true),
                  // Ctrl+S -> Manual sync
                  const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ): () =>
                      _runShortcut(() => _syncNow(), ignoreTyping: true),
                  // Ctrl+= â†’ Zoom in
                  const SingleActivator(
                    LogicalKeyboardKey.equal,
                    control: true,
                  ): () =>
                      _runShortcut(() => _pdfController.zoomUp(), ignoreTyping: true),
                  // Ctrl+- â†’ Zoom out
                  const SingleActivator(
                    LogicalKeyboardKey.minus,
                    control: true,
                  ): () =>
                      _runShortcut(() => _pdfController.zoomDown(), ignoreTyping: true),
                  // Ctrl+Z â†’ Undo (Windows/Linux)
                  const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    control: true,
                  ): () =>
                      _runShortcut(() => _handleUndo(app, _editingCommentId)),
                  // Cmd+Z â†’ Undo (macOS)
                  const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                  ): () =>
                      _runShortcut(() => _handleUndo(app, _editingCommentId)),
                  // Ctrl+Y â†’ Redo (Windows/Linux)
                  const SingleActivator(
                    LogicalKeyboardKey.keyY,
                    control: true,
                  ): () =>
                      _runShortcut(() => _handleRedo(app, _editingCommentId)),
                  // Ctrl+Shift+Z â†’ Redo (Windows/Linux)
                  const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    control: true,
                    shift: true,
                  ): () =>
                      _runShortcut(() => _handleRedo(app, _editingCommentId)),
                  // Cmd+Shift+Z â†’ Redo (macOS)
                  const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                    shift: true,
                  ): () =>
                      _runShortcut(() => _handleRedo(app, _editingCommentId)),
                },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                // 1. Toolbar (Top)
                StudyFlowToolbar(
                  activeTool: _tool,
                  selectedAnnotationTool: selectedAnnotationTool,
                  selectedShapeAuthor: selectedShapeAuthor,
                  selectedCommentAuthor: selectedCommentAuthor,
                  isRightPanelOpen: _isRightPanelOpen,
                  isSplitMode: isSplitMode,
                  isShapesPaletteVisible: _isShapesPaletteVisible,
                  isDarkMode: isDarkMode,
                  isSearchVisible: _isSearchVisible,
                  isSyncing: app.isSyncing,
                  activePdf: pdf,
                  pdfController: primaryController,
                  onToggleShapesPalette: () {
                    setState(() {
                      _isShapesPaletteVisible = !_isShapesPaletteVisible;
                    });
                  },
                  onToolChanged: (t) {
                    _activateTool(t);
                  },
                  onToggleRightPanel: () {
                    setState(() {
                      _isRightPanelOpen = !_isRightPanelOpen;
                      if (!_isRightPanelOpen) {
                        _isPointerOverAiChat = false;
                      }
                    });
                    _forcePdfRelayout();
                  },
                  onToggleSplitMode: () {
                    app.toggleSplitMode();
                    _forcePdfRelayout();
                  },
                  onToggleSettings: () {
                    setState(() {
                      _isSettingsMode = !_isSettingsMode;
                      if (_isSettingsMode) {
                        _isRightPanelOpen = true;
                      }
                    });
                    _forcePdfRelayout();
                  },
                  onToggleSearch: () {
                    setState(() {
                      _isSearchVisible = !_isSearchVisible;
                      if (_isSearchVisible) {
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _searchFocusNode.requestFocus();
                        });
                      }
                    });
                  },
                  onSyncPressed: _syncNow,
                  onAddBookmark: (pdf) => _showAddBookmarkDialog(pdf),
                ),
                // 2. Main Content Area (Viewer + Right Panel)
                Expanded(
                  child: Row(
                    children: [
                      // Viewer Area
                      Expanded(
                        child: _isPrintingMode
                            ? Container(
                                color: const Color(0xFFE2E8F0),
                                child: _buildPrintLoadingScreen(),
                              )
                            : RepaintBoundary(
                                child: Stack(
                                  children: [
                                    // Background & PDF View
                                    Container(
                                      // Always keep the PDF paper/background light
                                      color: const Color(0xFFE2E8F0),
                                      child: pdf == null
                                          ? _buildNoFilePlaceholder()
                                          : isSplitMode && secondaryPdf != null
                                          ? Row(
                                              children: [
                                                Expanded(
                                                  child: _buildPdfViewerCore(
                                                    pdf,
                                                    primaryController,
                                                    showOverlays: true,
                                                  ),
                                                ),
                                                Container(
                                                  width: 1,
                                                  color: isDarkMode
                                                      ? const Color(0xFF334155)
                                                      : const Color(0xFFE2E8F0),
                                                ),
                                                Expanded(
                                                  child: _buildPdfViewerCore(
                                                    secondaryPdf,
                                                    secondaryController,
                                                    showOverlays: false,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : _buildPdfViewerCore(
                                              pdf,
                                              primaryController,
                                              showOverlays: true,
                                            ),
                                    ),

                                    // Search Bar Overlay
                                    if (_isSearchVisible && pdf != null)
                                      Positioned(
                                        top: 80,
                                        right: 16,
                                        child: Card(
                                          elevation: 4,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 200,
                                                  child: TextField(
                                                    autofocus: true,
                                                    contextMenuBuilder:
                                                        (
                                                          context,
                                                          editableTextState,
                                                        ) {
                                                          return const SizedBox.shrink();
                                                        },
                                                    decoration:
                                                        const InputDecoration(
                                                          hintText: 'بحث...',
                                                          border:
                                                              InputBorder.none,
                                                          isDense: true,
                                                        ),
                                                    onChanged: (val) {
                                                      _textSearcher
                                                          ?.startTextSearch(
                                                            val,
                                                          );
                                                    },
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    LucideIcons.chevronUp,
                                                  ),
                                                  onPressed: () => _textSearcher
                                                      ?.goToPrevMatch(),
                                                  tooltip: 'السابق',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    LucideIcons.chevronDown,
                                                  ),
                                                  onPressed: () => _textSearcher
                                                      ?.goToNextMatch(),
                                                  tooltip: 'التالي',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    LucideIcons.x,
                                                  ),
                                                  onPressed: () {
                                                    _textSearcher
                                                        ?.resetTextSearch();
                                                    setState(
                                                      () => _isSearchVisible =
                                                          false,
                                                    );
                                                  },
                                                  tooltip: 'إغلاق',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                    if (_isShapesPaletteVisible)
                                      Positioned(
                                        left: 20,
                                        bottom: 50,
                                        child: TapRegion(
                                          onTapOutside: (_) {
                                            // Only auto-dismiss when in cursor mode.
                                            // When a shape tool is active the user is
                                            // likely drawing, so keep the palette visible.
                                            if (mounted &&
                                                _tool != ToolType.arrow &&
                                                _tool != ToolType.rectangle &&
                                                _tool != ToolType.circle &&
                                                _tool != ToolType.pen &&
                                                _tool != ToolType.highlight) {
                                              setState(() {
                                                _isShapesPaletteVisible = false;
                                              });
                                            }
                                          },
                                          child: Material(
                                            elevation: 4,
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isDarkMode
                                                    ? const Color(0xFF1E293B)
                                                    : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: isDarkMode
                                                      ? const Color(0xFF334155)
                                                      : const Color(0xFFE2E8F0),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: 'مستطيل',
                                                    icon: const Icon(
                                                      LucideIcons.square,
                                                    ),
                                                    color:
                                                        _tool ==
                                                            ToolType.rectangle
                                                        ? const Color(
                                                            0xFF3B82F6,
                                                          )
                                                        : (isDarkMode
                                                              ? const Color(
                                                                  0xFF94A3B8,
                                                                )
                                                              : const Color(
                                                                  0xFF64748B,
                                                                )),
                                                    onPressed: () {
                                                      setState(() {
                                                        _activateTool(
                                                          ToolType.rectangle,
                                                        );
                                                      });
                                                    },
                                                  ),
                                                  IconButton(
                                                    tooltip: 'دائرة',
                                                    icon: const Icon(
                                                      LucideIcons.circle,
                                                    ),
                                                    color:
                                                        _tool == ToolType.circle
                                                        ? const Color(
                                                            0xFF3B82F6,
                                                          )
                                                        : (isDarkMode
                                                              ? const Color(
                                                                  0xFF94A3B8,
                                                                )
                                                              : const Color(
                                                                  0xFF64748B,
                                                                )),
                                                    onPressed: () {
                                                      setState(() {
                                                        _activateTool(
                                                          ToolType.circle,
                                                        );
                                                      });
                                                    },
                                                  ),
                                                  IconButton(
                                                    tooltip: 'سهم',
                                                    icon: const Icon(
                                                      LucideIcons.arrowUpRight,
                                                    ),
                                                    color:
                                                        _tool == ToolType.arrow
                                                        ? const Color(
                                                            0xFF3B82F6,
                                                          )
                                                        : (isDarkMode
                                                              ? const Color(
                                                                  0xFF94A3B8,
                                                                )
                                                              : const Color(
                                                                  0xFF64748B,
                                                                )),
                                                    onPressed: () {
                                                      setState(() {
                                                        _activateTool(
                                                          ToolType.arrow,
                                                        );
                                                      });
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    // Text Selection Menu
                                    if (_isTextSelectionMenuVisible &&
                                        _textSelection != null)
                                      Positioned(
                                        bottom: 32,
                                        left: 20,
                                        right: 20,
                                        child: Center(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(
                                                sigmaX: 12,
                                                sigmaY: 12,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isDarkMode
                                                      ? Colors.black54
                                                      : Colors.white70,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: isDarkMode
                                                        ? Colors.white10
                                                        : Colors.black12,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        LucideIcons.copy,
                                                        size: 20,
                                                      ),
                                                      onPressed: () async {
                                                        final text =
                                                            await _textSelection!
                                                                .getSelectedText();
                                                        await Clipboard.setData(
                                                          ClipboardData(
                                                            text: text,
                                                          ),
                                                        );
                                                        _clearCurrentTextSelection();
                                                      },
                                                      tooltip: 'نسخ',
                                                    ),
                                                    IconButton(
                                                      icon: _isTranslating
                                                          ? const SizedBox(
                                                              width: 20,
                                                              height: 20,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                            )
                                                          : const Icon(
                                                              LucideIcons
                                                                  .languages,
                                                              size: 20,
                                                            ),
                                                      onPressed:
                                                          _handleTranslate,
                                                      tooltip: 'ترجمة',
                                                    ),
                                                    Container(
                                                      width: 1,
                                                      height: 24,
                                                      color: isDarkMode
                                                          ? Colors.white10
                                                          : Colors.black12,
                                                      margin:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                          ),
                                                    ),
                                                    ...[
                                                      const Color(0xFFFBEA7A),
                                                      const Color(0xFFA4D376),
                                                      const Color(0xFF84C0F2),
                                                      const Color(0xFFF59EB9),
                                                      const Color(0xFFC9A6D8),
                                                    ].map(
                                                      (c) => GestureDetector(
                                                        onTap: () =>
                                                            _addTextHighlight(
                                                              c,
                                                            ),
                                                        child: Container(
                                                          width: 24,
                                                          height: 24,
                                                          margin:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                              ),
                                                          decoration:
                                                              BoxDecoration(
                                                                color: c,
                                                                shape: BoxShape
                                                                    .circle,
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .white24,
                                                                  width: 2,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      width: 1,
                                                      height: 24,
                                                      color: isDarkMode
                                                          ? Colors.white10
                                                          : Colors.black12,
                                                      margin:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                          ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        LucideIcons.x,
                                                        size: 20,
                                                      ),
                                                      onPressed: () =>
                                                          _clearCurrentTextSelection(),
                                                      tooltip: 'إغلاق',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    // Floating Translation Result UI
                                    if (_translatedText != null)
                                      Positioned(
                                        bottom: 110,
                                        left: 20,
                                        right: 20,
                                        child: Center(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(
                                                sigmaX: 10,
                                                sigmaY: 10,
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  16,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isDarkMode
                                                      ? Colors.black54
                                                      : Colors.white70,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: isDarkMode
                                                        ? Colors.white10
                                                        : Colors.black12,
                                                  ),
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      _translatedText!,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: isDarkMode
                                                            ? Colors.white
                                                            : Colors.black,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    IconButton(
                                                      icon: const Icon(
                                                        LucideIcons.x,
                                                        size: 16,
                                                      ),
                                                      onPressed: () => setState(
                                                        () => _translatedText =
                                                            null,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    // Vertical Slider
                                    if (primaryController.isReady &&
                                        primaryController.pages.length > 1)
                                      Positioned(
                                        right: 12,
                                        top: 100,
                                        bottom: 100,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.04,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: RotatedBox(
                                            quarterTurns: 1,
                                            child: SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 4,
                                                thumbShape:
                                                    const RoundSliderThumbShape(
                                                      enabledThumbRadius: 6,
                                                    ),
                                                overlayShape:
                                                    const RoundSliderOverlayShape(
                                                      overlayRadius: 14,
                                                    ),
                                                activeTrackColor: const Color(
                                                  0xFF94A3B8,
                                                ),
                                                inactiveTrackColor:
                                                    Colors.transparent,
                                                thumbColor: const Color(
                                                  0xFF64748B,
                                                ),
                                              ),
                                              child: ListenableBuilder(
                                                listenable: primaryController,
                                                builder: (context, _) {
                                                  final int pageCount =
                                                      primaryController
                                                          .pages
                                                          .length;
                                                  if (pageCount < 1)
                                                    return const SizedBox.shrink();

                                                  final double min = 1.0;
                                                  final double max = pageCount
                                                      .toDouble()
                                                      .clamp(
                                                        min,
                                                        double.infinity,
                                                      );

                                                  bool isDragging = false;
                                                  double dragValue = min;

                                                  return StatefulBuilder(
                                                    builder: (context, setLocalState) {
                                                      final int currentPage =
                                                          primaryController
                                                              .pageNumber ??
                                                          1;
                                                      final double
                                                      controllerVal =
                                                          (pageCount -
                                                                  currentPage +
                                                                  1)
                                                              .toDouble()
                                                              .clamp(min, max);
                                                      final double
                                                      displayValue = isDragging
                                                          ? dragValue
                                                          : controllerVal;

                                                      return Slider(
                                                        min: min,
                                                        max: max,
                                                        divisions: pageCount > 1
                                                            ? pageCount - 1
                                                            : null,
                                                        value: displayValue
                                                            .clamp(min, max),
                                                        onChangeStart: (val) {
                                                          setLocalState(() {
                                                            isDragging = true;
                                                            dragValue = val;
                                                          });
                                                        },
                                                        onChanged: (val) {
                                                          setLocalState(() {
                                                            dragValue = val;
                                                          });
                                                          int page =
                                                              (pageCount -
                                                                      val +
                                                                      1)
                                                                  .round()
                                                                  .clamp(
                                                                    1,
                                                                    pageCount,
                                                                  );
                                                          if (page !=
                                                              currentPage) {
                                                            primaryController
                                                                .goToPage(
                                                                  pageNumber:
                                                                      page,
                                                                );
                                                          }
                                                        },
                                                        onChangeEnd: (val) {
                                                          setLocalState(() {
                                                            isDragging = false;
                                                          });
                                                          int page =
                                                              (pageCount -
                                                                      val +
                                                                      1)
                                                                  .round()
                                                                  .clamp(
                                                                    1,
                                                                    pageCount,
                                                                  );
                                                          primaryController
                                                              .goToPage(
                                                                pageNumber:
                                                                    page,
                                                              );
                                                        },
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    // Text Formatting Toolbar (Shows when editing or adding text)
                                    if ((_tool == ToolType.text ||
                                        _editingCommentId != null))
                                      Positioned(
                                        bottom: 32,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: TextFormattingToolbar(
                                            fontSize: _fontSize,
                                            isLatex: _isLatex,
                                            showBorder: _showBorder,
                                            isDarkMode: isDarkMode,
                                            onIncreaseFont: () {
                                              setState(() {
                                                _fontSize = (_fontSize + 1)
                                                    .clamp(8.0, 72.0);
                                              });
                                              _updateCurrentEditingText();
                                            },
                                            onDecreaseFont: () {
                                              setState(() {
                                                _fontSize = (_fontSize - 1)
                                                    .clamp(8.0, 72.0);
                                              });
                                              _updateCurrentEditingText();
                                            },
                                            onToggleLatex: (val) {
                                              setState(() {
                                                _isLatex = val;
                                              });
                                              _updateCurrentEditingText();
                                            },
                                            onToggleBorder: (val) {
                                              setState(() {
                                                _showBorder = val;
                                              });
                                              _updateCurrentEditingText();
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),

                      // 3. Right Panel (Side-by-Side)
                      if (_isRightPanelOpen)
                        StudyFlowRightPanel(
                          isSettingsMode: _isSettingsMode,
                          activeTool: panelTool,
                          activeColor: _colorForTool(panelTool),
                          strokeWidth: _toolStrokeWidths[panelTool] ?? 2.0,
                          fontSize: _fontSize,
                          fontFamily: _textFontFamily,
                          fontOptions: const [
                            'Segoe UI',
                            'Times New Roman',
                            'Tahoma',
                            'Arial',
                            'Noto Naskh Arabic',
                            'Noto Sans Arabic',
                            'Amiri',
                          ],
                          isBold: _isBold,
                          activeTabIndex: _rightPanelTabIndex,
                          isDarkMode: isDarkMode,
                          activePdf: pdf,
                          pdfController: primaryController,
                          selectedHighlightId: _selectedHighlightId,
                          onToolChanged: (t) => _activateTool(t),
                          onColorChanged: _onColorChanged,
                          onStrokeWidthChanged: _onStrokeWidthChanged,
                          onFontSizeChanged: (v) {
                            setState(() => _fontSize = v);
                            if (_tool == ToolType.text)
                              _updateCurrentEditingText();
                          },
                          onFontFamilyChanged: (family) {
                            setState(() => _textFontFamily = family);
                            if (_tool == ToolType.text)
                              _updateCurrentEditingText();
                          },
                          onBoldChanged: (v) {
                            setState(() => _isBold = v);
                            if (_tool == ToolType.text)
                              _updateCurrentEditingText();
                          },
                          isLatex: _isLatex,
                          onLatexChanged: (v) {
                            setState(() => _isLatex = v);
                            if (_tool == ToolType.text)
                              _updateCurrentEditingText();
                          },
                          showBorder: _showBorder,
                          borderColor: _borderColor,
                          bgColor: panelTool == ToolType.text
                              ? _textBgColor
                              : _shapeFillColor,
                          onShowBorderChanged: (v) {
                            setState(() => _showBorder = v);
                            if (_tool == ToolType.text)
                              _updateCurrentEditingText();
                          },
                          onBorderColorChanged: (c) {
                            setState(() => _borderColor = c);
                            if (_tool == ToolType.text)
                              _updateCurrentEditingText();
                          },
                          onBgColorChanged: (c) {
                            setState(() {
                              if (_tool == ToolType.text) {
                                _textBgColor = c;
                                _updateCurrentEditingText();
                              } else if (_tool == ToolType.rectangle ||
                                  _tool == ToolType.circle) {
                                _shapeFillColor = c;
                              }
                            });
                          },
                          onTabChanged: (i) =>
                              setState(() => _rightPanelTabIndex = i),
                          onAiChatHoverChanged: _setAiChatPointerHover,
                          onAddPage: (pdf) => _addPage(pdf),
                          onDeletePage: (pdf) => _deleteCurrentPage(pdf),
                          onPrint: (pdf) => _showPrintDialog(pdf),
                          onToggleDarkMode: () => app.toggleDarkMode(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPdfViewerCore(
    PdfItem pdf,
    PdfViewerController controller, {
    required bool showOverlays,
  }) {
    final app = context.read<AppProvider>();
    return Listener(
      // Auto-switch to Hand tool when the user scrolls while a drawing tool
      // is active, so pdfrx handles navigation naturally.
      onPointerSignal: (pointerSignal) {
        if (!showOverlays || _isPointerOverAiChat) return;
        if (pointerSignal is PointerScrollEvent && _tool != ToolType.cursor) {
          _activateTool(ToolType.cursor);
        }
      },
      // Windows/macOS touchpads emit pan/zoom pointer events for two-finger
      // scrolling. Handle them the same way as mouse wheel scrolling.
      onPointerPanZoomStart: (_) {
        if (!showOverlays || _isPointerOverAiChat) return;
        if (_tool != ToolType.cursor) {
          _activateTool(ToolType.cursor);
        }
      },
      onPointerPanZoomUpdate: (_) {
        if (!showOverlays || _isPointerOverAiChat) return;
        if (_tool != ToolType.cursor) {
          _activateTool(ToolType.cursor);
        }
      },
      child: PdfViewer.file(
        pdf.path,
        key: ValueKey(
          '${pdf.path}_${controller.hashCode}_${_needsReload ? DateTime.now().millisecondsSinceEpoch : 'stable'}',
        ),
        controller: controller,
        params: PdfViewerParams(
          maxImageBytesCachedOnMemory: 100 * 1024 * 1024,
          maxScale: 4.0,
          minScale: 0.5,
          scrollByMouseWheel: _isPointerOverAiChat ? 0.0 : 0.8,
          pageOverlaysBuilder: (context, pageRect, page) {
            return [
              RepaintBoundary(
                child: _buildPageOverlay(context, pageRect, page, pdf),
              ),
            ];
          },
          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
              const SizedBox.shrink(),
          enableKeyboardNavigation:
              showOverlays && _editingCommentId == null && !_isSearchVisible,
          textSelectionParams: showOverlays
              ? PdfTextSelectionParams(
                  onTextSelectionChange: (selection) {
                    _handleTextSelectionChange(selection);
                  },
                )
              : null,
          onInteractionStart: showOverlays
              ? (details) {
                  app.cancelDebouncedSync();
                }
              : null,
          onInteractionUpdate: showOverlays
              ? (details) {
                  // Auto-switch to Hand tool during multi-touch gestures
                  if (_tool != ToolType.cursor &&
                      (details.scale != 1.0 || details.pointerCount > 1)) {
                    _activateTool(ToolType.cursor);
                  }
                }
              : null,
          onInteractionEnd: showOverlays
              ? (details) {
                  // Trigger bidirectional sync after pan/zoom ends (with debounce in AppProvider)
                  if (_tool == ToolType.cursor &&
                      app.currentSessionCode != null) {
                    app.triggerDebouncedSync(silent: true);
                  }
                }
              : null,
          onViewerReady: (document, viewerController) {
            if (mounted && showOverlays) {
              setState(() {
                _isProcessing = false;
                _textSearcher ??= PdfTextSearcher(viewerController)
                  ..addListener(_onControllerChanged);
              });
              _requestAutoFit(
                delay: const Duration(milliseconds: 120),
                force: true,
              );
            }
          },
          onPageChanged: (page) {
            final currentPage = page ?? _lastReportedPage;

            _lastReportedPage = currentPage;

            if (_scrollDebounce?.isActive ?? false) {
              _scrollDebounce!.cancel();
            }

            _scrollDebounce = Timer(const Duration(milliseconds: 300), () {
              if (mounted) {
                context.read<AppProvider>().updatePdfScroll(
                  pdf.id,
                  pageNumber: currentPage,
                );
              }
            });

            _schedulePostScrollMaintenance();
          },
        ),
        initialPageNumber: pdf.lastPage ?? 1,
      ),
    );
  }

  Widget _buildNoFilePlaceholder() {
    return Builder(builder: (ctx) => _buildDashboard(ctx));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Formatting Floating Toolbar
// ─────────────────────────────────────────────────────────────────────────────
class TextFormattingToolbar extends StatelessWidget {
  final double fontSize;
  final bool isLatex;
  final bool showBorder;
  final bool isDarkMode;
  final VoidCallback onIncreaseFont;
  final VoidCallback onDecreaseFont;
  final ValueChanged<bool> onToggleLatex;
  final ValueChanged<bool> onToggleBorder;

  const TextFormattingToolbar({
    super.key,
    required this.fontSize,
    required this.isLatex,
    required this.showBorder,
    required this.isDarkMode,
    required this.onIncreaseFont,
    required this.onDecreaseFont,
    required this.onToggleLatex,
    required this.onToggleBorder,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDarkMode
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final iconColor = isDarkMode
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final activeColor = const Color(0xFF3B82F6);

    return TapRegion(
      groupId: 'text_editing_region',
      child: Material(
        elevation: 6,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(LucideIcons.minus, size: 20, color: iconColor),
                  onPressed: onDecreaseFont,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'تصغير الخط',
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    fontSize.toInt().toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(LucideIcons.plus, size: 20, color: iconColor),
                  onPressed: onIncreaseFont,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'تكبير الخط',
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: borderColor,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                ),
                IconButton(
                  icon: Icon(
                    Icons.functions,
                    size: 22,
                    color: isLatex ? activeColor : iconColor,
                  ),
                  onPressed: () => onToggleLatex(!isLatex),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'معادلة رياضية (LaTeX)',
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: borderColor,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                ),
                IconButton(
                  icon: Icon(
                    showBorder ? Icons.border_outer : Icons.border_clear,
                    size: 22,
                    color: showBorder ? activeColor : iconColor,
                  ),
                  onPressed: () => onToggleBorder(!showBorder),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'إظهار/إخفاء الإطار',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
