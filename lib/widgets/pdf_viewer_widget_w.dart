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

  // ─── Smart Dynamic Threshold Constants ────────────────────────────────────
  static const double _kSpeedThreshold = 0.1; // pages per millisecond
  static const int _kSlowThreshold = 25; // trim every 25 pages when slow
  static const int _kFastThreshold = 15; // trim every 15 pages when fast

  ToolType _tool =
      ToolType.cursor; // 'cursor', 'highlight', 'eraser', 'pen', 'comment'

  // ── Per-tool colors: changing one never affects another ──────────────────
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

  double _strokeWidth = 5.0;
  double _fontSize = 14.0;
  bool _isBold = false;
  bool _isLatex = false; // NEW: LaTeX annotation mode
  bool _showBorder = true;
  Color _borderColor = const Color(0xFF000000); // Black border by default
  Color _textBgColor = Colors.transparent;
  Color _shapeFillColor = Colors.transparent;
  // _activePointerCount removed - using native onScale gesture

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

  // ─── UNDO HANDLER: Global Ctrl+Z / Cmd+Z ──────────────────────────────────
  /// Handles undo action with smart detection of text field focus.
  /// If a text field is currently focused (like DraggableTextWidget),
  /// we don't override the native text undo. Otherwise, we undo the last
  /// annotation (highlight or comment).
  void _handleUndo(AppProvider app, String? editingCommentId) {
    // Check if actively editing a comment (in text field)
    // If so, let the text field handle undo natively
    if (editingCommentId != null) {
      debugPrint('⌨️  Undo: Text editor active, skipping global undo');
      return;
    }

    // Check if search box is visible and might have focus
    if (_isSearchVisible) {
      debugPrint('⌨️  Undo: Search box active, proceeding with global undo');
    }

    // Execute global undo
    debugPrint('🔙 Undo: Reverting last annotation...');
    app.undoLastAction();
  }

  void _handleRedo(AppProvider app, String? editingCommentId) {
    if (editingCommentId != null) {
      debugPrint('⌨️  Redo: Text editor active, skipping global redo');
      return;
    }

    debugPrint('↪️ Redo: Reapplying last annotation...');
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
              // Ctrl+S → Bookmark current page
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () =>
                  _showAddBookmarkDialog(pdf),
              // Ctrl+= → Zoom in
              const SingleActivator(
                LogicalKeyboardKey.equal,
                control: true,
              ): () =>
                  _pdfController.zoomUp(),
              // Ctrl+- → Zoom out
              const SingleActivator(
                LogicalKeyboardKey.minus,
                control: true,
              ): () =>
                  _pdfController.zoomDown(),
              // Ctrl+Z → Undo (Windows/Linux)
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
              ): () =>
                  _handleUndo(app, _editingCommentId),
              // Cmd+Z → Undo (macOS)
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
                  _handleUndo(app, _editingCommentId),
              // Ctrl+Y → Redo (Windows/Linux)
              const SingleActivator(
                LogicalKeyboardKey.keyY,
                control: true,
              ): () =>
                  _handleRedo(app, _editingCommentId),
              // Ctrl+Shift+Z → Redo (Windows/Linux)
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
                shift: true,
              ): () =>
                  _handleRedo(app, _editingCommentId),
              // Cmd+Shift+Z → Redo (macOS)
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
              onAddBookmark: _showAddBookmarkDialog,
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
                                            _isShapesPaletteVisible = false;
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
                                            _isShapesPaletteVisible = false;
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
                                            _isShapesPaletteVisible = false;
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
                                        if (_textSelection
                                            is PdfTextSelectionDelegate) {
                                          await (_textSelection
                                                  as PdfTextSelectionDelegate)
                                              .clearTextSelection();
                                        }
                                        if (mounted) {
                                          setState(() => _textSelection = null);
                                        }
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
                      strokeWidth: _strokeWidth,
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
                      onAddPage: _addPage,
                      onDeletePage: _deleteCurrentPage,
                      onPrint: _showPrintDialog,
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
                  '🧠 Smart trim | speed: ${scrollSpeed.toStringAsFixed(4)} pages/ms'
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
    return _buildDashboard();
  }

  // ─── DASHBOARD ─────────────────────────────────────────────────────────────

  Widget _buildDashboard() {
    final app = context.watch<AppProvider>();
    final isDarkMode = context.select<AppProvider, bool>(
      (app) => app.isDarkMode,
    );

    // Use FutureBuilder for async recent docs
    return Container(
      color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: FutureBuilder<List<PdfDocument>>(
        future: context.read<FileManagerService>().getRecentDocuments(limit: 6),
        builder: (context, snapshot) {
          final recentDocs = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeHeader(app),
                const SizedBox(height: 32),
                _buildQuickActionsGrid(context, isDarkMode),
                const SizedBox(height: 48),
                _buildRecentDocumentsSection(recentDocs, isDarkMode),
                const SizedBox(height: 48),
                _buildStatisticsSection(app),
                const SizedBox(height: 48),
                _buildTipsSection(isDarkMode),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWelcomeHeader(AppProvider app) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to StudyFlow',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: app.isDarkMode ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start your smart learning journey with advanced PDF tools',
              style: TextStyle(
                fontSize: 16,
                color: app.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: app.isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.bookOpen,
                size: 20,
                color: Color(0xFF3B82F6),
              ),
              const SizedBox(width: 8),
              Text(
                '${app.totalPdfs} Books • ${app.totalHighlights} Highlights',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: app.isDarkMode
                      ? Colors.white
                      : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context, bool isDarkMode) {
    final actions = [
      {
        'icon': LucideIcons.upload,
        'label': 'Upload PDF',
        'color': 0xFF3B82F6,
        'action': () {
          // Upload to current active class or default
          final app = context.read<AppProvider>();
          final targetClassId =
              app.activeClassId ??
              (app.classes.isNotEmpty ? app.classes.first.id : '');
          if (targetClassId.isNotEmpty) {
            app.uploadPdf(targetClassId);
          }
        },
      },
      {
        'icon': LucideIcons.combine,
        'label': 'Merge PDFs',
        'color': 0xFF8B5CF6, // Purple
        'action': () => showDialog(
          context: context,
          builder: (context) => const MergePdfDialog(),
        ),
      },
      {
        'icon': LucideIcons.image,
        'label': 'Images to PDF',
        'color': 0xFF10B981, // Green
        'action': () => showDialog(
          context: context,
          builder: (context) => const ImagesToPdfDialog(),
        ),
      },
      {
        'icon': LucideIcons.folderPlus,
        'label': 'New Folder',
        'color': 0xFFF59E0B, // Amber (shifted color)
        'action': () => _showCreateFolderDialog(context),
      },
      {
        'icon': LucideIcons.scanLine,
        'label': 'Scan',
        'color': 0xFFEC4899, // Pink
        'action': () => _showTopSnack('Scanning coming soon!'),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.5,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            final colorVal = action['color'] as int;
            final icon = action['icon'] as IconData;
            final label = action['label'] as String;
            final cb = action['action'] as VoidCallback;

            return InkWell(
              onTap: cb,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(colorVal).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Color(colorVal), size: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode
                            ? Colors.grey[300]
                            : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecentDocumentsSection(
    List<PdfDocument> recentDocs,
    bool isDarkMode,
  ) {
    if (recentDocs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          children: [
            Icon(
              LucideIcons.fileText,
              size: 48,
              color: isDarkMode ? Colors.grey[600] : Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No recently opened books',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start by uploading a new book to study',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Books',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2.5, // Wider cards
          ),
          itemCount: recentDocs.length,
          itemBuilder: (context, index) {
            final doc = recentDocs[index];
            return _buildDocumentCard(doc, isDarkMode);
          },
        ),
      ],
    );
  }

  Widget _buildDocumentCard(PdfDocument doc, bool isDarkMode) {
    return InkWell(
      onTap: () {
        // Open PDF via AppProvider
        context.read<AppProvider>().setActivePdf(doc.uuid);
        // Also set active class if tracked
        if (doc.classId != null) {
          context.read<AppProvider>().setActiveClass(doc.classId!);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF334155)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: doc.thumbnailPath != null
                    ? Image.file(File(doc.thumbnailPath!), fit: BoxFit.cover)
                    : Icon(
                        LucideIcons.fileText,
                        size: 24,
                        color: Colors.grey[400],
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    doc.originalPath
                        .split(Platform.pathSeparator)
                        .last, // Name fallback
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.bookmark,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Page ${doc.lastPage}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.highlighter,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${doc.annotationCount}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsSection(AppProvider app) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            LucideIcons.bookOpen,
            app.totalPdfs.toString(),
            'Total Books',
          ),
          _buildStatItem(
            LucideIcons.highlighter,
            app.totalHighlights.toString(),
            'Highlights',
          ),
          _buildStatItem(
            LucideIcons.messageSquare,
            app.totalComments.toString(),
            'Comments',
          ),
          _buildStatItem(
            LucideIcons.clock,
            'N/A',
            'Reading Time',
          ), // Placeholder
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildTipsSection(bool isDarkMode) {
    final tips = [
      'Use Ctrl+F for Search',
      'Try LaTeX mode for Math',
      'Double tap text to highlight',
      'Right click to annotate',
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.lightbulb,
                color: isDarkMode
                    ? Colors.yellow[700]
                    : const Color(0xFF3B82F6),
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Tips',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : const Color(0xFF1E4ED8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: tips.map((tip) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tip,
                  style: TextStyle(
                    color: isDarkMode
                        ? Colors.grey[300]
                        : const Color(0xFF1E293B),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Folder Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<FileManagerService>().createFolder(
                  name: controller.text,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showTopSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: 20,
          right: 20,
        ),
      ),
    );
  }

  void _addPage(PdfItem pdf) {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Add after current page
    int targetPage = 1;
    if (_pdfController.isReady && _pdfController.pageNumber != null) {
      targetPage = _pdfController.pageNumber!;
    } else {
      targetPage = pdf.lastPage ?? 1;
    }
    context.read<AppProvider>().addPage(pdf.id, insertAtIndex: targetPage);
  }

  void _deleteCurrentPage(PdfItem pdf) {
    if (_isProcessing) return;

    // Secure controller access with strict checks
    int pageToDelete = 1;
    if (_pdfController.isReady && _pdfController.pageNumber != null) {
      pageToDelete = _pdfController.pageNumber!;
    } else {
      pageToDelete = pdf.lastPage ?? 1;
    }

    // Show confirmation
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Page?'),
        content: Text(
          'Are you sure you want to delete page $pageToDelete? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isProcessing = true);
              // Page numbers in controller are 1-based, our API expects 0-based index
              context.read<AppProvider>().deletePage(pdf.id, pageToDelete - 1);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handlePanStart(Offset position, PdfPage page, double scale) {
    if (_tool == ToolType.cursor || _tool == ToolType.text) {
      return; // Text handled by onTapUp
    }
    if (_tool == ToolType.eraser) {
      _eraseAt(position / scale, page.pageNumber);
      return;
    }

    // VECTOR SHAPES: Initialize with start point
    setState(() {
      _currentPath = [position / scale];
      _currentPage = page.pageNumber;
    });
  }

  void _handlePanUpdate(Offset position, PdfPage page, double scale) {
    if (_tool == ToolType.cursor || _tool == ToolType.text) return;
    if (_tool == ToolType.eraser) {
      _eraseAt(position / scale, page.pageNumber);
    } else {
      if (_currentPath != null) {
        setState(() {
          // VECTOR SHAPES: Use 2-point paths (start + current end)
          if (_tool == ToolType.arrow ||
              _tool == ToolType.rectangle ||
              _tool == ToolType.circle) {
            // Replace the end point for shapes
            if (_currentPath!.length == 1) {
              _currentPath!.add(position / scale);
            } else {
              _currentPath![1] = position / scale;
            }
          } else {
            // Freehand drawing: add all points
            _currentPath!.add(position / scale);
          }
        });
      }
    }
  }

  void _handlePanEnd(PdfItem pdf) {
    if ((_tool == ToolType.highlight ||
            _tool == ToolType.pen ||
            _tool == ToolType.arrow ||
            _tool == ToolType.rectangle ||
            _tool == ToolType.circle) &&
        _currentPath != null) {
      // Determine highlight type
      HighlightType type;
      if (_tool == ToolType.pen) {
        type = HighlightType.pen;
      } else if (_tool == ToolType.arrow) {
        type = HighlightType.arrow;
      } else if (_tool == ToolType.rectangle) {
        type = HighlightType.rectangle;
      } else if (_tool == ToolType.circle) {
        type = HighlightType.circle;
      } else {
        type = HighlightType.highlight;
      }

      // Determine background color based on shape type
      // Arrows: no background color (null)
      // Rectangles & Circles: use current background color
      int? bgColorValue;
      if (type == HighlightType.rectangle || type == HighlightType.circle) {
        bgColorValue = _shapeFillColor.value;
      }
      // For arrows, pen, and highlight: bgColorValue remains null

      final highlight = Highlight(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        path: List.from(_currentPath!),
        color: _currentColor,
        page: _currentPage,
        strokeWidth: _strokeWidth,
        type: type,
        backgroundColor: bgColorValue, // Set background color for shapes
      );

      context.read<AppProvider>().addHighlight(pdf.id, highlight);

      setState(() {
        _currentPath = null;
        _currentPage = -1;
      });
    }
  }

  void _eraseAt(Offset pt, int pageNumber) {
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;
    const double hitRadius = 20.0;
    List<Highlight> toRemove = [];

    for (var h in pdf.highlights) {
      if (h.page != pageNumber) continue;
      bool hit = false;

      // إذا كان تظليلاً ذكياً للنصوص
      if (h.type == HighlightType.text && h.rects != null) {
        for (var r in h.rects!) {
          // توسيع منطقة اللمس قليلاً لتسهيل المسح
          if (r.inflate(hitRadius).contains(pt)) {
            hit = true;
            break;
          }
        }
      }
      // إذا كان تظليلاً حراً أو قلماً
      else {
        for (var p in h.path) {
          if ((p - pt).distance < hitRadius) {
            hit = true;
            break;
          }
        }
      }

      if (hit) toRemove.add(h);
    }

    bool removedSomething = false;
    for (var h in toRemove) {
      app.removeHighlight(pdf.id, h);
      removedSomething = true;
    }

    // UI FIX: Force the screen to repaint immediately after erasing
    if (removedSomething && mounted) {
      setState(() {});
    }
  }

  void _addTextAt(Offset pt, int pageNumber) {
    if (_isProcessing) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final comment = PdfComment(
      id: id,
      page: pageNumber,
      position: pt, // Assumed unscaled ID passed from caller
      content: '',
      date: DateTime.now(),
      color: _textColor,
      fontSize: _fontSize,
      isBold: _isBold,
      isLatex: _isLatex, // NEW: carry current LaTeX mode
      showBorder: _showBorder,
      borderColor: _borderColor,
      bgColor: _textBgColor,
    );

    final app = context.read<AppProvider>();
    if (app.activePdf == null) return;

    app.addComment(app.activePdf!.id, comment);

    // CRITICAL: Initialize editing styles for the new comment
    app.startEditing(comment.id, comment);

    setState(() => _editingCommentId = comment.id);
  }

  void _updateCurrentEditingText() {
    if (_editingCommentId == null) return;
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    try {
      final comment = pdf.comments.firstWhere((c) => c.id == _editingCommentId);
      final updatedComment = comment.copyWith(
        color: _textColor,
        fontSize: _fontSize,
        isBold: _isBold,
        isLatex: _isLatex,
        showBorder: _showBorder,
        borderColor: _borderColor,
        bgColor: _textBgColor,
      );
      app.updateComment(pdf.id, comment, updatedComment);
    } catch (e) {
      debugPrint('Error updating comment style: $e');
    }
  }

  void _addTextHighlight(Color color) async {
    final selection = _textSelection;
    if (selection == null) return;

    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    try {
      final ranges = await selection.getSelectedTextRanges();
      final selectionsByPage = <int, List<Rect>>{};

      for (final range in ranges) {
        final pageNumber = range.pageNumber;
        final page = _pdfController
            .document
            .pages[pageNumber - 1]; // Ensure document is loaded

        if (!selectionsByPage.containsKey(pageNumber)) {
          selectionsByPage[pageNumber] = [];
        }

        for (final fragment in range.enumerateFragmentBoundingRects()) {
          final rect = fragment.bounds.toRect(page: page);
          selectionsByPage[pageNumber]!.add(rect);
        }
      }

      for (final entry in selectionsByPage.entries) {
        final highlight = Highlight(
          id: 'hl_${DateTime.now().microsecondsSinceEpoch}',
          path: [], // Empty path for text highlights
          color: color,
          page: entry.key,
          type: HighlightType.text,
          rects: entry.value,
        );
        app.addHighlight(pdf.id, highlight);
      }

      if (selection is PdfTextSelectionDelegate) {
        await selection.clearTextSelection();
      }
      if (mounted) setState(() => _textSelection = null);
    } catch (e) {
      debugPrint('Error adding text highlight: $e');
    }
  }

  Widget _buildPageOverlay(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
    PdfItem pdf,
  ) {
    final scale = pageRect.width / page.width;
    final ignoring = _tool == ToolType.cursor;

    Widget overlay = IgnorePointer(
      ignoring: ignoring,
      child: Stack(
        children: [
          // Highlights & Pen
          CustomPaint(
            size: Size(pageRect.width, pageRect.height),
            painter: HighlightPainter(
              highlights: pdf.highlights
                  .where((h) => h.page == page.pageNumber)
                  .toList(),
              scale: scale,
            ),
          ),

          // Current Drawing
          if (_currentPage == page.pageNumber && _currentPath != null)
            CustomPaint(
              size: Size(pageRect.width, pageRect.height),
              painter: HighlightPainter(
                highlights: [
                  Highlight(
                    id: 'temp_drawing_id',
                    path: _currentPath!,
                    color: _currentColor,
                    page: page.pageNumber,
                    strokeWidth: _strokeWidth,
                    type: _getActiveToolType(),
                  ),
                ],
                scale: scale,
                isCurrent: true,
              ),
            ),

          if (!ignoring)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  // 1. Guard Clause: Prevent spawning new text if we are currently editing one.
                  // Clicking outside should only close the active text (handled by onTapOutside).
                  final appProvider = context.read<AppProvider>();
                  if (appProvider.activeEditingCommentId != null) {
                    return;
                  }

                  // 2. Normal Tool Logic
                  if (_tool == ToolType.cursor) {
                    _handleSelectionTap(
                      details.localPosition,
                      page,
                      pdf,
                      scale,
                    );
                  } else if (_tool == ToolType.text) {
                    // Only create new text if we are NOT currently editing another one
                    _addTextAt(details.localPosition / scale, page.pageNumber);
                  } else {
                    // Clear selection if tapping with a drawing tool
                    if (_selectedHighlightId != null) {
                      setState(() => _selectedHighlightId = null);
                    }
                  }
                },
                onPanStart: (details) {
                  if (_tool == ToolType.cursor &&
                      _selectedHighlightId != null) {
                    // Allow dragging the selected shape
                    return;
                  }
                  if (_tool != ToolType.cursor && _tool != ToolType.text) {
                    _handlePanStart(details.localPosition, page, scale);
                  }
                },
                onPanUpdate: (details) {
                  if (_tool == ToolType.cursor &&
                      _selectedHighlightId != null) {
                    // Execute the drag logic for the selected shape
                    final app = context.read<AppProvider>();
                    final shape = pdf.highlights
                        .where((h) => h.id == _selectedHighlightId)
                        .firstOrNull;
                    if (shape != null) {
                      final delta = details.delta / scale;
                      final newPath = shape.path.map((p) => p + delta).toList();
                      final updated = shape.copyWith(path: newPath);
                      app.removeHighlight(pdf.id, shape);
                      app.addHighlight(pdf.id, updated);
                    }
                    return;
                  }
                  if (_tool != ToolType.cursor && _tool != ToolType.text) {
                    _handlePanUpdate(details.localPosition, page, scale);
                  }
                },
                onPanEnd: (details) {
                  if (_tool != ToolType.cursor && _tool != ToolType.text) {
                    _handlePanEnd(pdf);
                  }
                },
              ),
            ),

          // Text (Comments) - Must be on TOP to receive hits!
          ...pdf.comments.where((c) => c.page == page.pageNumber).map((c) {
            return Positioned(
              left: c.position.dx * scale,
              top: c.position.dy * scale,
              child: DraggableTextWidget(
                commentId: c.id, // NEW: Pass the ID
                content: c.content,
                color: c.color,
                fontSize: c.fontSize,
                isBold: c.isBold,
                isLatex: c.isLatex,
                showBorder: c.showBorder,
                borderColor: c.borderColor,
                bgColor: c.bgColor,
                scale: scale,
                isEditing: c.id == _editingCommentId,
                enableDrag:
                    !(_tool == ToolType.eraser) && (c.id != _editingCommentId),
                onEditComplete: (newText, event) {
                  // This will now be called via the provider's endEditing
                  if (newText.trim().isEmpty) {
                    context.read<AppProvider>().removeComment(pdf.id, c);
                  } else {
                    // The provider's endEditing handles the actual save
                    context.read<AppProvider>().endEditing(c.id, newText);
                  }
                  setState(() => _editingCommentId = null);
                },
                onTap: () {
                  if (_tool == ToolType.text) {
                    // Start editing through provider
                    context.read<AppProvider>().startEditing(c.id, c);
                    setState(() {
                      _editingCommentId = c.id;
                      // Sync local state with provider styles
                      final styles = context
                          .read<AppProvider>()
                          .getEditingStyles(c.id);
                      if (styles != null) {
                        _textColor = Color(styles['color']);
                        _fontSize = styles['fontSize'];
                        _isBold = styles['isBold'];
                        _isLatex = styles['isLatex'];
                        _showBorder = styles['showBorder'];
                        _borderColor = Color(styles['borderColor']);
                        _textBgColor = Color(styles['bgColor']);
                      }
                    });
                  } else if (_tool == ToolType.eraser) {
                    context.read<AppProvider>().removeComment(pdf.id, c);
                  }
                  if (mounted) setState(() {});
                },
                onDragEnd: (offset) {
                  if (_tool == ToolType.text || _tool == ToolType.cursor) {
                    final newPos = c.position + offset / scale;
                    context.read<AppProvider>().updateComment(
                      pdf.id,
                      c,
                      c.copyWith(position: newPos),
                    );
                  }
                },
              ),
            );
          }),
        ],
      ),
    );

    // PERFORMANCE SHIELD: Wrap entire overlay in RepaintBoundary to cache rendering
    return RepaintBoundary(child: overlay);
  }

  // ─── Win32 Memory Trim ─────────────────────────────────────────────────────
  // Calls EmptyWorkingSet via FFI to force Windows to release native heap pages
  // back to the OS. Safe to call from the main thread — it does NOT freeze the UI.
  void _trimWindowsMemory() {
    if (!Platform.isWindows) return;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getCurrentProcess = kernel32
          .lookupFunction<IntPtr Function(), int Function()>(
            'GetCurrentProcess',
          );
      final emptyWorkingSet = kernel32
          .lookupFunction<Bool Function(IntPtr), bool Function(int)>(
            'K32EmptyWorkingSet',
          );
      final handle = getCurrentProcess();
      emptyWorkingSet(handle);
    } catch (e) {
      // Silently ignore — non-critical trim
      debugPrint('Memory trim skipped: $e');
    }
  }

  void _forcePdfRelayout() {
    if (!_pdfController.isReady) return;
    final currentPage = _pdfController.pageNumber ?? 1;
    // VIEWPORT ADAPTER: Wait 300ms for sidebar animation to complete
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _pdfController.isReady) {
        _pdfController.goToPage(pageNumber: currentPage);
      }
    });
  }

  Widget _buildPrintLoadingScreen() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'جاري تجهيز الصفحات للطباعة...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم استئناف العرض تلقائياً بعد الطباعة',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSafePrint(PdfItem pdf, PrintSettings settings) async {
    // Save current state
    final currentPage = _pdfController.pageNumber ?? 1;
    // final currentZoom = _pdfController.zoomLevel ?? 1.0; // unavailable in this version

    // Pause rendering to avoid Thread Collision
    if (mounted) setState(() => _isPreparingPrint = true);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      await PrintService.executePrint(
        pdf.path,
        settings,
        currentPage: currentPage,
        printJobName: pdf.name,
      );
    } catch (e) {
      debugPrint("Print Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print error: $e')));
      }
    } finally {
      if (mounted) {
        // Store state for resurrection
        _targetPageAfterReload = currentPage;
        // _targetZoomAfterReload = currentZoom;
        _needsReload = true;

        // Remove loading screen but DO NOT render old pointers yet
        setState(() => _isPreparingPrint = false);

        // Wait for UI to flush
        await Future.delayed(const Duration(milliseconds: 50));

        // Resurrect the viewer
        if (mounted && _needsReload) {
          _performHardReload(pdf);
        }
      }
    }
  }

  void _performHardReload(PdfItem pdf) {
    // 1. Safely kill old controller to prevent Memory Leaks! (CRITICAL)
    _pdfController.removeListener(_onControllerChanged);
    // _pdfController.dispose(); // Not available in this version of pdfrx

    // 2. Create fresh controller (forces new PDFium initialization)
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onControllerChanged);

    // 3. Reset flag
    _needsReload = false;

    // 4. Trigger rebuild with new Key
    setState(() {});

    // 5. Restore position after the new native view is mounted
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _pdfController.isReady) {
        _pdfController.goToPage(pageNumber: _targetPageAfterReload);
        // _pdfController.zoomLevel = _targetZoomAfterReload;
      }
    });
  }

  void _showPrintDialog(PdfItem pdf) {
    // Resolve total pages: prefer the controller's known count, fall back to 0.
    final totalPages = _pdfController.isReady
        ? _pdfController.pageCount
        : (pdf.lastPage ?? 1);
    final currentPage = _pdfController.pageNumber ?? pdf.lastPage ?? 1;

    showDialog(
      context: context,
      builder: (_) => PrintDialog(
        pdfPath: pdf.path,
        pdfName: pdf.name,
        totalPages: totalPages,
        currentPage: currentPage,
        onPrint: (settings) async {
          await _executeSafePrint(pdf, settings);
        },
      ),
    );
  }

  void _showAddBookmarkDialog(PdfItem pdf) {
    final controller = TextEditingController();
    final currentPage = _pdfController.pageNumber ?? 1;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Bookmark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Page $currentPage',
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Bookmark name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (controller.text.trim().isNotEmpty) {
                  context.read<AppProvider>().addBookmark(
                    pdf.id,
                    controller.text.trim(),
                    currentPage,
                  );
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<AppProvider>().addBookmark(
                  pdf.id,
                  controller.text.trim(),
                  currentPage,
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // --- ADVANCED HIT-TESTING & SELECTION ---

  HighlightType _getActiveToolType() {
    switch (_tool) {
      case ToolType.pen:
        return HighlightType.pen;
      case ToolType.arrow:
        return HighlightType.arrow;
      case ToolType.rectangle:
        return HighlightType.rectangle;
      case ToolType.circle:
        return HighlightType.circle;
      case ToolType.highlight:
        return HighlightType.highlight;
      default:
        return HighlightType.pen;
    }
  }

  void _handleSelectionTap(
    Offset tapPos,
    PdfPage page,
    PdfItem pdf,
    double scale,
  ) {
    final scaledTap = tapPos / scale;
    final shapes = pdf.highlights
        .where((h) => h.page == page.pageNumber)
        .toList();

    Highlight? selectedShape;
    // Iterate in reverse to pick the top-most shape
    for (final shape in shapes.reversed) {
      if (shape.path.length < 2) continue;
      final rect = Rect.fromPoints(
        shape.path.first,
        shape.path.last,
      ).inflate(15.0);
      if (rect.contains(scaledTap)) {
        selectedShape = shape;
        break;
      }
    }

    if (selectedShape != null) {
      final shape = selectedShape;
      setState(() {
        _selectedHighlightId = shape.id;
        _shapeStrokeColor = shape.color;
        _strokeWidth = shape.strokeWidth;
      });
      if (!_isRightPanelOpen) setState(() => _isRightPanelOpen = true);
    } else {
      setState(() => _selectedHighlightId = null);
    }
  }

  void _updateSelectedShapeColor(Color color) {
    if (_selectedHighlightId == null) return;
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    final shape = pdf.highlights
        .where((h) => h.id == _selectedHighlightId)
        .firstOrNull;
    if (shape != null) {
      final updated = shape.copyWith(color: color);
      app.removeHighlight(pdf.id, shape);
      app.addHighlight(pdf.id, updated);
    }
  }

  void _updateSelectedShapeStrokeWidth(double width) {
    if (_selectedHighlightId == null) return;
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    final shape = pdf.highlights
        .where((h) => h.id == _selectedHighlightId)
        .firstOrNull;
    if (shape != null) {
      final updated = shape.copyWith(strokeWidth: width);
      app.removeHighlight(pdf.id, shape);
      app.addHighlight(pdf.id, updated);
    }
  }

  void _onColorChanged(Color color) {
    setState(() {
      if (_tool == ToolType.pen) {
        _penColor = color;
      } else if (_tool == ToolType.highlight) {
        _highlightColor = color;
        _updateSelectedShapeColor(color);
      } else if (_tool == ToolType.text) {
        _textColor = color;
        _updateCurrentEditingText();
      } else {
        _shapeStrokeColor = color;
        _updateSelectedShapeColor(color);
      }
    });
  }

  void _onStrokeWidthChanged(double width) {
    setState(() => _strokeWidth = width);
    _updateSelectedShapeStrokeWidth(width); // Sync with active shape
  }
}
