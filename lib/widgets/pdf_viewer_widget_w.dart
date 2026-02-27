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
  // _isDarkMode removed
  bool _isPreparingPrint =
      false; // CRITICAL: Controls unmount during native print

  bool _isRightPanelOpen = false;
  bool _isShapesPaletteVisible = false;
  bool _isSettingsMode = false;
  int _rightPanelTabIndex = 0; // 0: Tools, 1: AI, 2: Translate

  // â”€â”€â”€ Smart Dynamic Threshold Constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const double _kSpeedThreshold = 0.1; // pages per millisecond
  static const int _kSlowThreshold = 25; // trim every 25 pages when slow
  static const int _kFastThreshold = 15; // trim every 15 pages when fast

  ToolType _tool =
      ToolType.cursor; // 'cursor', 'highlight', 'eraser', 'pen', 'comment'

  // â”€â”€ Per-tool colors: changing one never affects another â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Color _penColor = const Color(0xFF000000);
  Color _highlightColor = const Color(0xFFFFFF00);
  Color _shapeStrokeColor = const Color(0xFF000000); // arrow/rect/circle
  Color _textColor = const Color(0xFF000000);

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
  int _activePointerCount = 0; // Tracks simultaneous touches to block drawing on 2+ fingers

  // Current drawing state
  List<Offset>? _currentPath;
  int _currentPage = -1;
  bool _isProcessing = false; // Processing lock
  Timer? _scrollDebounce;
  int _lastTimestamp = 0;
  int _lastReportedPage = 0;
  int _pagesSinceLastFlush = 0;

  String? _editingCommentId;

  // Hard Reload Tracking
  bool _needsReload = false;
  int _targetPageAfterReload = 1;
  // double _targetZoomAfterReload = 1.0; // Unused

  final FocusNode _searchFocusNode = FocusNode(); // NEW: Focus node for search
  PdfTextSearcher? _textSearcher;
  bool _isSearchVisible = false;
  PdfTextSelection? _textSelection;
  bool _suppressTextSelection = false; // Suppress zombie refire after clearing selection
  String? _selectedHighlightId; // NEW: Track selected shape

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
      debugPrint('âŒ¨ï¸  Undo: Search box active, proceeding with global undo');
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

  @override
  Widget build(BuildContext context) {
    // PERFORMANCE: Use read instead of watch to prevent full rebuilds
    // Only rebuild when activePdf changes using Selector
    final app = context.read<AppProvider>();
    final pdf = context.select<AppProvider, PdfItem?>((app) => app.activePdf);
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
      }
    }

    return CallbackShortcuts(
      bindings: _editingCommentId != null || pdf == null
          ? <ShortcutActivator, VoidCallback>{}
          : {
              const SingleActivator(LogicalKeyboardKey.keyH): () =>
                  setState(() {
                    _tool = ToolType.highlight;
                    _isSettingsMode = false;
                  }),
              const SingleActivator(LogicalKeyboardKey.keyE): () =>
                  setState(() {
                    _tool = ToolType.eraser;
                    _isSettingsMode = false;
                  }),
              const SingleActivator(LogicalKeyboardKey.keyP): () =>
                  setState(() {
                    _tool = ToolType.pen;
                    _isSettingsMode = false;
                  }),
              const SingleActivator(LogicalKeyboardKey.keyT): () =>
                  setState(() {
                    _tool = ToolType.text;
                    _isSettingsMode = false;
                  }),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  setState(() {
                    _tool = ToolType.cursor;
                    _isSettingsMode = false;
                  }),
              const SingleActivator(LogicalKeyboardKey.keyV): () =>
                  setState(() {
                    _tool = ToolType.cursor;
                    _isSettingsMode = false;
                  }),
              const SingleActivator(
                LogicalKeyboardKey.keyP,
                control: true,
              ): () =>
                  _showPrintDialog(pdf),
              const SingleActivator(
                LogicalKeyboardKey.keyF,
                control: true,
              ): () => setState(() {
                if (_textSearcher != null) _isSearchVisible = true;
              }),
              const SingleActivator(
                LogicalKeyboardKey.keyL,
                control: true,
              ): () {
                app.toggleSidebar();
                _forcePdfRelayout();
              },
              const SingleActivator(
                LogicalKeyboardKey.keyR,
                control: true,
              ): () {
                setState(() => _isRightPanelOpen = !_isRightPanelOpen);
                _forcePdfRelayout();
              },
              // Ctrl+S â†’ Bookmark current page
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () =>
                  _showAddBookmarkDialog(pdf),
              // Ctrl+= â†’ Zoom in
              const SingleActivator(
                LogicalKeyboardKey.equal,
                control: true,
              ): () =>
                  _pdfController.zoomUp(),
              // Ctrl+- â†’ Zoom out
              const SingleActivator(
                LogicalKeyboardKey.minus,
                control: true,
              ): () =>
                  _pdfController.zoomDown(),
              // Ctrl+Z â†’ Undo (Windows/Linux)
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
              ): () =>
                  _handleUndo(app, _editingCommentId),
              // Cmd+Z â†’ Undo (macOS)
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
                  _handleUndo(app, _editingCommentId),
              // Ctrl+Y â†’ Redo (Windows/Linux)
              const SingleActivator(
                LogicalKeyboardKey.keyY,
                control: true,
              ): () =>
                  _handleRedo(app, _editingCommentId),
              // Ctrl+Shift+Z â†’ Redo (Windows/Linux)
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
                shift: true,
              ): () =>
                  _handleRedo(app, _editingCommentId),
              // Cmd+Shift+Z â†’ Redo (macOS)
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ): () =>
                  _handleRedo(app, _editingCommentId),
            },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            // 1. Toolbar (Top)
            StudyFlowToolbar(
              activeTool: _tool,
              isRightPanelOpen: _isRightPanelOpen,
              isShapesPaletteVisible: _isShapesPaletteVisible,
              isDarkMode: isDarkMode,
              isSearchVisible: _isSearchVisible,
              activePdf: pdf,
              pdfController: _pdfController,
              onToggleShapesPalette: () {
                setState(() {
                  _isShapesPaletteVisible = !_isShapesPaletteVisible;
                  // When opening the palette, deselect any active shape tool so
                  // the toolbar button doesn't remain falsely highlighted.
                  if (_isShapesPaletteVisible &&
                      (_tool == ToolType.arrow ||
                          _tool == ToolType.rectangle ||
                          _tool == ToolType.circle)) {
                    _tool = ToolType.cursor;
                  }
                });
              },
              onToolChanged: (t) {
                setState(() {
                  _tool = t;
                  _isSettingsMode = false;
                });
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
                    child: Stack(
                      children: [
                        // Background & PDF View
                        Container(
                          // Always keep the PDF paper/background light
                          color: const Color(0xFFE2E8F0),
                          child: pdf == null
                              ? _buildNoFilePlaceholder()
                              : Stack(
                                  children: [
                                    // 1. Keep the PDF in the tree but pause rendering during printing
                                    Offstage(
                                      offstage: _isPreparingPrint,
                                      child: _buildPdfViewerCore(pdf),
                                    ),

                                    // 2. Show the loading overlay on top when printing
                                    if (_isPreparingPrint)
                                      Positioned.fill(
                                        child: Container(
                                          color: const Color(
                                            0xFFE2E8F0,
                                          ).withValues(alpha: 0.9),
                                          child: _buildPrintLoadingScreen(),
                                        ),
                                      ),
                                  ],
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
                                        decoration: const InputDecoration(
                                          hintText: 'Find...',
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                        onChanged: (val) {
                                          _textSearcher?.startTextSearch(val);
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.chevronUp),
                                      onPressed: () =>
                                          _textSearcher?.goToPrevMatch(),
                                      tooltip: 'Previous',
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.chevronDown),
                                      onPressed: () =>
                                          _textSearcher?.goToNextMatch(),
                                      tooltip: 'Next',
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.x),
                                      onPressed: () {
                                        _textSearcher?.resetTextSearch();
                                        setState(
                                          () => _isSearchVisible = false,
                                        );
                                      },
                                      tooltip: 'Close',
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
                                        tooltip: 'Rectangle',
                                        icon: const Icon(LucideIcons.square),
                                        color: _tool == ToolType.rectangle
                                            ? const Color(0xFF3B82F6)
                                            : (isDarkMode
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B)),
                                        onPressed: () {
                                          setState(() {
                                            _tool = ToolType.rectangle;

                                          });
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Circle',
                                        icon: const Icon(LucideIcons.circle),
                                        color: _tool == ToolType.circle
                                            ? const Color(0xFF3B82F6)
                                            : (isDarkMode
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B)),
                                        onPressed: () {
                                          setState(() {
                                            _tool = ToolType.circle;
                                          });
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Arrow',
                                        icon: const Icon(
                                          LucideIcons.arrowUpRight,
                                        ),
                                        color: _tool == ToolType.arrow
                                            ? const Color(0xFF3B82F6)
                                            : (isDarkMode
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B)),
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
                        if (_textSelection != null)
                          Positioned(
                            bottom: 32,
                            left: 0,
                            right: 0,
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
                                              color: const Color(0xFFE2E8F0),
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
                                      margin: const EdgeInsets.only(right: 8),
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.x, size: 20),
                                      onPressed: () async {
                                        final sel = _textSelection;
                                        if (mounted) setState(() {
                                          _textSelection = null;
                                          _suppressTextSelection = true;
                                        });
                                        if (sel is PdfTextSelectionDelegate) {
                                          await sel.clearTextSelection();
                                        }
                                        if (mounted) setState(() => _suppressTextSelection = false);
                                      },
                                      tooltip: 'Clear Selection',
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
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                    activeTrackColor: const Color(0xFF94A3B8),
                                    inactiveTrackColor: Colors.transparent,
                                    thumbColor: const Color(0xFF64748B),
                                  ),
                                  child: Slider(
                                    min: 1.0,
                                    max: _pdfController.pages.length.toDouble(),
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
                      activeTool: _tool,
                      activeColor: _currentColor,
                      strokeWidth: _currentStrokeWidth,
                      fontSize: _fontSize,
                      isBold: _isBold,
                      activeTabIndex: _rightPanelTabIndex,
                      isDarkMode: isDarkMode,
                      activePdf: pdf,
                      pdfController: _pdfController,
                      selectedHighlightId: _selectedHighlightId,
                      onToolChanged: (t) => setState(() {
                        _tool = t;
                        _isSettingsMode = false;
                      }),
                      onColorChanged: _onColorChanged,
                      onStrokeWidthChanged: _onStrokeWidthChanged,
                      onFontSizeChanged: (v) {
                        setState(() => _fontSize = v);
                        if (_tool == ToolType.text) _updateCurrentEditingText();
                      },
                      onBoldChanged: (v) {
                        setState(() => _isBold = v);
                        if (_tool == ToolType.text) _updateCurrentEditingText();
                      },
                      isLatex: _isLatex,
                      onLatexChanged: (v) {
                        setState(() => _isLatex = v);
                        if (_tool == ToolType.text) _updateCurrentEditingText();
                      },
                      showBorder: _showBorder,
                      borderColor: _borderColor,
                      bgColor: _tool == ToolType.text
                          ? _textBgColor
                          : _shapeFillColor,
                      onShowBorderChanged: (v) {
                        setState(() => _showBorder = v);
                        if (_tool == ToolType.text) _updateCurrentEditingText();
                      },
                      onBorderColorChanged: (c) {
                        setState(() => _borderColor = c);
                        if (_tool == ToolType.text) _updateCurrentEditingText();
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
  }

  Widget _buildPdfViewerCore(PdfItem pdf) {
    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent && _tool != ToolType.cursor) {
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
          maxImageBytesCachedOnMemory: 10 * 1024 * 1024,
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
              if (!mounted) return;
              if (_suppressTextSelection && selection != null) return;
              setState(() {
                _textSelection = selection;
              });
            },
          ),
          onViewerReady: (document, controller) {
            if (mounted) {
              setState(() {
                _isProcessing = false;
                _textSearcher ??= PdfTextSearcher(_pdfController)
                  ..addListener(_onControllerChanged);
              });
            }
          },
          onPageChanged: (page) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final timeDiff = now - _lastTimestamp;
            final currentPage = page ?? _lastReportedPage;
            final int pagesPassed = (currentPage - _lastReportedPage).abs();

            if (pagesPassed > 0 && timeDiff > 0) {
              _pagesSinceLastFlush += pagesPassed;

              final scrollSpeed = pagesPassed / timeDiff;
              final dynamicThreshold = scrollSpeed > _kSpeedThreshold
                  ? _kFastThreshold
                  : _kSlowThreshold;

              if (_pagesSinceLastFlush >= dynamicThreshold) {
                try {
                  // ignore: avoid_dynamic_calls
                  (_pdfController as dynamic).clearImageCache?.call();
                } catch (_) {}

                _trimWindowsMemory();
                _pagesSinceLastFlush = 0;
                debugPrint(
                  'ðŸ§  Smart trim | speed: ${scrollSpeed.toStringAsFixed(4)} pages/ms'
                  ' | threshold: $dynamicThreshold',
                );
              }
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
                  pageNumber: page,
                );
                setState(() {});

                Future.delayed(const Duration(milliseconds: 100), () {
                  try {
                    // ignore: avoid_dynamic_calls
                    (_pdfController as dynamic).clearImageCache?.call();
                  } catch (_) {}
                  _trimWindowsMemory();
                  _pagesSinceLastFlush = 0;
                });
              }
            });
          },
        ),
        initialPageNumber: pdf.lastPage ?? 1,
      ),
    );
  }

  Widget _buildNoFilePlaceholder() {
    return _buildDashboard(context);
  }
}