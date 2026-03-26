import 'package:pdfrx/pdfrx.dart' hide PdfDocument;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import '../providers/app_state.dart';
import '../models/models.dart';
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
  int? _lastModified;
  String? _currentPdfId;
  // Hard isolation mode: fully unmount PdfViewer during print pipeline.
  bool _isPrintingMode = false;

  bool _isRightPanelOpen = false;
  bool _isShapesPaletteVisible = false;
  bool _isSettingsMode = false;
  int _rightPanelTabIndex = 0; // 0: Tools, 1: AI, 2: Translate

  ToolType _tool =
      ToolType.cursor; // 'cursor', 'highlight', 'eraser', 'pen', 'comment'

  // â”€â”€ Per-tool colors: changing one never affects another â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Color _penColor = const Color(0xFF000000);
  Color _highlightColor = const Color(0xFFFFFF00);
  Color _shapeStrokeColor = const Color(0xFF000000); // arrow/rect/circle
  Color _textColor = const Color(0xFF000000);
  String _textFontFamily = 'Segoe UI';

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
  int _lastTimestamp = 0;
  int _lastReportedPage = 0;
  int _pagesSinceLastFlush = 0;
  int _lastMemoryTrimAt = 0;
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

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    // MEMORY FIX: Removed blind setState(() {}).
    // Firing setState on every scroll pixel causes a 1.5GB native memory leak.
    // If specific UI elements (like the slider) need to update, they should use
    // AnimatedBuilder or ValueListenableBuilder tied directly to the controller.
  }

  @override
  void dispose() {
    _pdfController.removeListener(_onControllerChanged);
    _scrollDebounce?.cancel();
    _scrollMaintenanceDebounce?.cancel();
    _autoFitDebounce?.cancel();
    _searchFocusNode.dispose(); // Dispose node
    _textSearcher?.dispose();
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

  void _activateTool(ToolType nextTool) {
    setState(() {
      _tool = nextTool;
      _isSettingsMode = false;

      // Leaving selection mode should clear selected shape visuals/state.
      if (nextTool != ToolType.select) {
        _selectedHighlightId = null;
        _endShapeTransform();
        _shapeHoverCursor = SystemMouseCursors.basic;
      }
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

      // Keep this conservative to prioritize smoothness over aggressive trimming.
      _maybeTrimWindowsMemory(minIntervalMs: 6000);
      _pagesSinceLastFlush = 0;
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

  bool _isTypingInTextField() {
    final focused = FocusManager.instance.primaryFocus;
    final context = focused?.context;
    if (context == null) return false;

    if (context.widget is EditableText) return true;
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return true;
    }

    final renderType = context.findRenderObject()?.runtimeType.toString() ?? '';
    return renderType.toLowerCase().contains('editable');
  }

  void _runShortcut(VoidCallback action) {
    if (_isTypingInTextField()) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    // PERFORMANCE: Use read instead of watch to prevent full rebuilds
    // Only rebuild when activePdf changes using Selector
    final app = context.read<AppProvider>();
    final pdf = context.select<AppProvider, PdfItem?>((app) => app.activePdf);
    final selectedAnnotationTool = _selectedAnnotationTool(pdf);
    final panelTool = _panelTool(pdf);
    final isDarkMode = context.select<AppProvider, bool>(
      (app) => app.isDarkMode,
    );

    // Strict Controller Cycle Management
    if (pdf != null) {
      if (_currentPdfId == null) {
        // First load
        _currentPdfId = pdf.id;
        _lastModified = pdf.lastModified;
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
      }
    }

    return AnimatedBuilder(
      animation: FocusManager.instance,
      builder: (context, _) {
        final isTypingNow = _isTypingInTextField();
        final shortcutsDisabled =
            _editingCommentId != null || pdf == null || isTypingNow;

        return CallbackShortcuts(
          bindings: shortcutsDisabled
              ? <ShortcutActivator, VoidCallback>{}
              : {
                  const SingleActivator(LogicalKeyboardKey.keyH): () =>
                      _runShortcut(() => _activateTool(ToolType.highlight)),
                  const SingleActivator(LogicalKeyboardKey.keyE): () =>
                      _runShortcut(() => _activateTool(ToolType.eraser)),
                  const SingleActivator(LogicalKeyboardKey.keyP): () =>
                      _runShortcut(() => _activateTool(ToolType.pen)),
                  const SingleActivator(LogicalKeyboardKey.keyT): () =>
                      _runShortcut(() => _activateTool(ToolType.text)),
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      _runShortcut(() => _activateTool(ToolType.cursor)),
                  const SingleActivator(LogicalKeyboardKey.keyV): () =>
                      _runShortcut(() => _activateTool(ToolType.cursor)),
                  const SingleActivator(
                    LogicalKeyboardKey.keyP,
                    control: true,
                  ): () =>
                      _runShortcut(() => _showPrintDialog(pdf)),
                  const SingleActivator(
                    LogicalKeyboardKey.keyF,
                    control: true,
                  ): () => _runShortcut(() {
                    setState(() {
                      if (_textSearcher != null) _isSearchVisible = true;
                    });
                  }),
                  const SingleActivator(
                    LogicalKeyboardKey.keyL,
                    control: true,
                  ): () => _runShortcut(() {
                    app.toggleSidebar();
                    _forcePdfRelayout();
                  }),
                  const SingleActivator(
                    LogicalKeyboardKey.keyR,
                    control: true,
                  ): () => _runShortcut(() {
                    setState(() => _isRightPanelOpen = !_isRightPanelOpen);
                    _forcePdfRelayout();
                  }),
                  // Ctrl+S â†’ Bookmark current page
                  const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ): () =>
                      _runShortcut(() => _showAddBookmarkDialog(pdf)),
                  // Ctrl+= â†’ Zoom in
                  const SingleActivator(
                    LogicalKeyboardKey.equal,
                    control: true,
                  ): () =>
                      _runShortcut(() => _pdfController.zoomUp()),
                  // Ctrl+- â†’ Zoom out
                  const SingleActivator(
                    LogicalKeyboardKey.minus,
                    control: true,
                  ): () =>
                      _runShortcut(() => _pdfController.zoomDown()),
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
                  isRightPanelOpen: _isRightPanelOpen,
                  isShapesPaletteVisible: _isShapesPaletteVisible,
                  isDarkMode: isDarkMode,
                  isSearchVisible: _isSearchVisible,
                  activePdf: pdf,
                  pdfController: _pdfController,
                  onToggleShapesPalette: () {
                    setState(() {
                      _isShapesPaletteVisible = !_isShapesPaletteVisible;
                    });
                  },
                  onToolChanged: (t) {
                    _activateTool(t);
                  },
                  onToggleRightPanel: () {
                    setState(() => _isRightPanelOpen = !_isRightPanelOpen);
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
                            : Stack(
                                children: [
                                  // Background & PDF View
                                  Container(
                                    // Always keep the PDF paper/background light
                                    color: const Color(0xFFE2E8F0),
                                    child: pdf == null
                                        ? _buildNoFilePlaceholder()
                                        : _buildPdfViewerCore(pdf),
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
                                                  decoration:
                                                      const InputDecoration(
                                                        hintText: 'بحث...',
                                                        border:
                                                            InputBorder.none,
                                                        isDense: true,
                                                      ),
                                                  onChanged: (val) {
                                                    _textSearcher
                                                        ?.startTextSearch(val);
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
                                                icon:
                                                    const Icon(LucideIcons.x),
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
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isDarkMode
                                            ? const Color(0xFF1E293B)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
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
                                            color: _tool == ToolType.rectangle
                                                ? const Color(0xFF3B82F6)
                                                : (isDarkMode
                                                      ? const Color(0xFF94A3B8)
                                                      : const Color(
                                                          0xFF64748B,
                                                        )),
                                            onPressed: () {
                                              setState(() {
                                                _tool = ToolType.rectangle;
                                              });
                                            },
                                          ),
                                          IconButton(
                                            tooltip: 'دائرة',
                                            icon: const Icon(
                                              LucideIcons.circle,
                                            ),
                                            color: _tool == ToolType.circle
                                                ? const Color(0xFF3B82F6)
                                                : (isDarkMode
                                                      ? const Color(0xFF94A3B8)
                                                      : const Color(
                                                          0xFF64748B,
                                                        )),
                                            onPressed: () {
                                              setState(() {
                                                _tool = ToolType.circle;
                                              });
                                            },
                                          ),
                                          IconButton(
                                            tooltip: 'سهم',
                                            icon: const Icon(
                                              LucideIcons.arrowUpRight,
                                            ),
                                            color: _tool == ToolType.arrow
                                                ? const Color(0xFF3B82F6)
                                                : (isDarkMode
                                                      ? const Color(0xFF94A3B8)
                                                      : const Color(
                                                          0xFF64748B,
                                                        )),
                                            onPressed: () {
                                              setState(() {
                                                _tool = ToolType.arrow;
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
                                left: 0,
                                right: 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap:
                                      () {}, // Absorb taps — stop bleed-through to pdfrx
                                  child: Center(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.1,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ...[
                                            const Color(0xFFFEF08A), // Yellow
                                            const Color(0xFFBBF7D0), // Green
                                            const Color(0xFFBFDBFE), // Blue
                                            const Color(0xFFFBCFE8), // Pink
                                            const Color(0xFFDDD6FE), // Purple
                                          ].map(
                                            (c) => GestureDetector(
                                              onTap: () => _addTextHighlight(c),
                                              child: Container(
                                                width: 24,
                                                height: 24,
                                                margin: const EdgeInsets.only(
                                                  right: 12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: c,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFE2E8F0,
                                                    ),
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 1,
                                            height: 24,
                                            color: const Color(0xFFE2E8F0),
                                            margin: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              LucideIcons.x,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              _clearCurrentTextSelection();
                                            },
                                            tooltip: 'مسح التحديد',
                                            color: const Color(0xFF64748B),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Vertical Slider
                            if (_pdfController.isReady &&
                                _pdfController.pages.length > 1)
                              Positioned(
                                right: 12,
                                top: 100,
                                bottom: 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: RotatedBox(
                                    quarterTurns: 1,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 14,
                                            ),
                                        activeTrackColor: const Color(
                                          0xFF94A3B8,
                                        ),
                                        inactiveTrackColor: Colors.transparent,
                                        thumbColor: const Color(0xFF64748B),
                                      ),
                                      child: Slider(
                                        min: 1.0,
                                        max: _pdfController.pages.length
                                            .toDouble(),
                                        value:
                                            (_pdfController.pageNumber
                                                        ?.toDouble() ??
                                                    1.0)
                                                .clamp(
                                                  1.0,
                                                  _pdfController.pages.length
                                                      .toDouble(),
                                                ),
                                        onChanged: (val) {
                                          setState(() {});
                                          _pdfController.goToPage(
                                            pageNumber: val.toInt(),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                                ],
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
                          pdfController: _pdfController,
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

  Widget _buildPdfViewerCore(PdfItem pdf) {
    return Listener(
      // Auto-switch to Hand tool when the user scrolls while a drawing tool
      // is active, so pdfrx handles navigation naturally.
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent && _tool != ToolType.cursor) {
          setState(() => _tool = ToolType.cursor);
        }
      },
      // Windows/macOS touchpads emit pan/zoom pointer events for two-finger
      // scrolling. Handle them the same way as mouse wheel scrolling.
      onPointerPanZoomStart: (_) {
        if (_tool != ToolType.cursor) {
          setState(() => _tool = ToolType.cursor);
        }
      },
      onPointerPanZoomUpdate: (_) {
        if (_tool != ToolType.cursor) {
          setState(() => _tool = ToolType.cursor);
        }
      },
      child: PdfViewer.file(
        pdf.path,
        key: ValueKey(
          '${pdf.path}_${_needsReload ? DateTime.now().millisecondsSinceEpoch : 'stable'}',
        ),
        controller: _pdfController,
        params: PdfViewerParams(
          maxImageBytesCachedOnMemory: 40 * 1024 * 1024,
          maxScale: 4.0,
          minScale: 0.5,
          scrollByMouseWheel: 0.8,
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
              _editingCommentId == null && !_isSearchVisible,
          textSelectionParams: PdfTextSelectionParams(
            onTextSelectionChange: (selection) {
              _handleTextSelectionChange(selection);
            },
          ),
          onViewerReady: (document, controller) {
            if (mounted) {
              setState(() {
                _isProcessing = false;
                _textSearcher ??= PdfTextSearcher(_pdfController)
                  ..addListener(_onControllerChanged);
              });
              _requestAutoFit(
                delay: const Duration(milliseconds: 120),
                force: true,
              );
            }
          },
          onPageChanged: (page) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final timeDiff = now - _lastTimestamp;
            final currentPage = page ?? _lastReportedPage;
            final int pagesPassed = (currentPage - _lastReportedPage).abs();

            if (pagesPassed > 0 && timeDiff > 0) {
              _pagesSinceLastFlush += pagesPassed;
            }

            _lastTimestamp = now;
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
