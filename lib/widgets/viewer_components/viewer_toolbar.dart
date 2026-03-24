import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';

class StudyFlowToolbar extends StatefulWidget {
  final ToolType activeTool;
  final ToolType? selectedAnnotationTool;
  final bool isRightPanelOpen;
  final bool isShapesPaletteVisible;
  final bool isDarkMode;
  final bool isSearchVisible;
  final PdfItem? activePdf;
  final PdfViewerController pdfController;
  final ValueChanged<ToolType> onToolChanged;
  final VoidCallback onToggleShapesPalette;
  final VoidCallback onToggleRightPanel;
  final VoidCallback onToggleSettings;
  final VoidCallback onToggleSearch;
  final Function(PdfItem) onAddBookmark;

  const StudyFlowToolbar({
    super.key,
    required this.activeTool,
    this.selectedAnnotationTool,
    required this.isRightPanelOpen,
    required this.isShapesPaletteVisible,
    required this.isDarkMode,
    required this.isSearchVisible,
    required this.activePdf,
    required this.pdfController,
    required this.onToolChanged,
    required this.onToggleShapesPalette,
    required this.onToggleRightPanel,
    required this.onToggleSettings,
    required this.onToggleSearch,
    required this.onAddBookmark,
  });

  @override
  State<StudyFlowToolbar> createState() => _StudyFlowToolbarState();
}

class _StudyFlowToolbarState extends State<StudyFlowToolbar> {
  bool _isEditingPage = false;
  bool _isEditingZoom = false;
  final TextEditingController _pageInputController = TextEditingController();
  final TextEditingController _zoomInputController = TextEditingController();
  int? _lastShownPage;
  int _lastShownPageCount = 0;
  int _lastShownZoomPercent = -1;

  static const double _kManualZoomStepFactor = 1.10;
  static const double _kZoomUpperBound = 4.0;

  @override
  void initState() {
    super.initState();
    widget.pdfController.addListener(_onPdfControllerChanged);
    _refreshToolbarSnapshot();
  }

  @override
  void didUpdateWidget(covariant StudyFlowToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfController != widget.pdfController) {
      oldWidget.pdfController.removeListener(_onPdfControllerChanged);
      widget.pdfController.addListener(_onPdfControllerChanged);
      _refreshToolbarSnapshot();
    }
  }

  void _onPdfControllerChanged() {
    if (!mounted || _isEditingZoom) return;
    final changed = _refreshToolbarSnapshot();
    if (!changed) return;
    setState(() {});
  }

  bool _refreshToolbarSnapshot() {
    final bool ready = widget.pdfController.isReady;
    final int? page = ready ? widget.pdfController.pageNumber : null;
    final int pageCount = ready ? widget.pdfController.pages.length : 0;
    final int zoomPercent = ready ? (_currentZoomRatio() * 100).round() : 100;

    final changed =
        page != _lastShownPage ||
        pageCount != _lastShownPageCount ||
        zoomPercent != _lastShownZoomPercent;

    _lastShownPage = page;
    _lastShownPageCount = pageCount;
    _lastShownZoomPercent = zoomPercent;
    return changed;
  }

  @override
  void dispose() {
    widget.pdfController.removeListener(_onPdfControllerChanged);
    _pageInputController.dispose();
    _zoomInputController.dispose();
    super.dispose();
  }

  double _currentZoomRatio() {
    if (!widget.pdfController.isReady) return 1.0;
    final value = widget.pdfController.currentZoom;
    if (!value.isFinite || value <= 0) return 1.0;
    return value;
  }

  String _currentZoomLabel() {
    return '${(_currentZoomRatio() * 100).round()}%';
  }

  Future<void> _applyZoom(double targetZoom) async {
    if (!widget.pdfController.isReady) return;
    final minZoom = widget.pdfController.minScale;
    final clamped = targetZoom.clamp(minZoom, _kZoomUpperBound).toDouble();
    await widget.pdfController.setZoom(
      widget.pdfController.centerPosition,
      clamped,
      duration: const Duration(milliseconds: 120),
    );
    if (mounted && !_isEditingZoom) {
      setState(() {});
    }
  }

  Future<void> _stepZoom(bool zoomIn) async {
    final current = _currentZoomRatio();
    final next = zoomIn
        ? current * _kManualZoomStepFactor
        : current / _kManualZoomStepFactor;
    await _applyZoom(next);
  }

  Future<void> _submitZoomText(String raw) async {
    final normalized = raw.replaceAll('%', '').trim();
    final value = double.tryParse(normalized);
    if (value == null || value <= 0) {
      setState(() => _isEditingZoom = false);
      return;
    }
    await _applyZoom(value / 100.0);
    if (mounted) {
      setState(() => _isEditingZoom = false);
    }
  }

  // ─── UNIFIED BUTTON BUILDER ───────────────────────────────────────
  Widget _buildToolButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    String? tooltip,
    Color? activeColor,
    required Color iconMuted,
  }) {
    final effectiveActiveColor = activeColor ?? const Color(0xFF3B82F6);
    final bgColor = isActive
        ? effectiveActiveColor.withOpacity(0.15)
        : Colors.transparent;
    final fgColor = isActive ? effectiveActiveColor : iconMuted;

    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 22, color: fgColor),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isMobile = MediaQuery.of(context).size.width < 768;
    final pdf = widget.activePdf;

    final scheme = Theme.of(context).colorScheme;
    final barBg = widget.isDarkMode ? const Color(0xFF0F172A) : scheme.surface;
    final separatorColor = widget.isDarkMode
        ? Colors.white.withOpacity(0.1)
        : Colors.black.withOpacity(0.05);
    final chipBg = widget.isDarkMode
        ? const Color(0xFF1E293B)
        : scheme.surfaceContainerHigh;
    final textPrimary = widget.isDarkMode ? Colors.white : scheme.onSurface;
    final iconMuted = widget.isDarkMode
        ? const Color(0xFF94A3B8)
        : scheme.onSurfaceVariant;
    final inputBorder = widget.isDarkMode
        ? const Color(0xFF334155)
        : scheme.outlineVariant;
    final selectedShapeType = widget.selectedAnnotationTool;
    final hasSelectedShape =
        widget.activeTool == ToolType.select && selectedShapeType != null;
    final isSelectedShapeTool =
        hasSelectedShape &&
        [
          ToolType.arrow,
          ToolType.rectangle,
          ToolType.circle,
        ].contains(selectedShapeType);
    final isSelectedHighlightTool =
        hasSelectedShape && selectedShapeType == ToolType.highlight;

    return TextFieldTapRegion(
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: barBg,
          border: Border(bottom: BorderSide(color: separatorColor, width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ─── LEFT: Sidebar + Page Counter + Zoom ───────────────
            Row(
              children: [
                const SizedBox(width: 2),
                if (isMobile)
                  _buildToolButton(
                    icon: LucideIcons.menu,
                    isActive: false,
                    onTap: () => app.toggleMobile(),
                    iconMuted: iconMuted,
                  )
                else if (app.isSidebarCollapsed)
                  _buildToolButton(
                    icon: LucideIcons.panelLeftOpen,
                    isActive: false,
                    onTap: () => app.toggleSidebar(),
                    tooltip: 'إظهار/إخفاء القائمة الجانبية (Ctrl+L)',
                    iconMuted: iconMuted,
                  ),
                if (isMobile || app.isSidebarCollapsed)
                  const SizedBox(width: 8),

                // Page Counter
                if (pdf != null)
                  _isEditingPage
                      ? SizedBox(
                          width: 84,
                          height: 40,
                          child: TextField(
                            controller: _pageInputController,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textPrimary,
                            ),
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: inputBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: inputBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ),
                            onSubmitted: (val) {
                              final int? page = int.tryParse(val);
                              if (page != null &&
                                  page >= 1 &&
                                  page <= widget.pdfController.pages.length) {
                                widget.pdfController.goToPage(pageNumber: page);
                              }
                              setState(() => _isEditingPage = false);
                            },
                            onTapOutside: (_) =>
                                setState(() => _isEditingPage = false),
                          ),
                        )
                      : InkWell(
                          onTap: () {
                            setState(() {
                              _isEditingPage = true;
                              _pageInputController.text =
                                  (widget.pdfController.pageNumber ?? 1)
                                      .toString();
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.pdfController.isReady
                                  ? '${widget.pdfController.pageNumber} / ${widget.pdfController.pages.length}'
                                  : 'جارٍ التحميل...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ),

                const SizedBox(width: 8),

                // Zoom Controls
                Container(
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    children: [
                      _buildToolButton(
                        icon: LucideIcons.zoomOut,
                        isActive: false,
                        onTap: () => _stepZoom(false),
                        tooltip: 'تصغير',
                        iconMuted: iconMuted,
                      ),
                      const SizedBox(width: 4),
                      _isEditingZoom
                          ? SizedBox(
                              width: 72,
                              height: 36,
                              child: TextField(
                                controller: _zoomInputController,
                                autofocus: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: inputBorder),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: inputBorder),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(8),
                                    ),
                                    borderSide: BorderSide(
                                      color: Color(0xFF3B82F6),
                                    ),
                                  ),
                                ),
                                onSubmitted: _submitZoomText,
                                onTapOutside: (_) =>
                                    _submitZoomText(_zoomInputController.text),
                              ),
                            )
                          : InkWell(
                              onTap: () {
                                setState(() {
                                  _isEditingZoom = true;
                                  _zoomInputController.text =
                                      (_currentZoomRatio() * 100)
                                          .toStringAsFixed(0);
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 72,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: barBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: inputBorder),
                                ),
                                child: Text(
                                  _currentZoomLabel(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(width: 4),
                      _buildToolButton(
                        icon: LucideIcons.zoomIn,
                        isActive: false,
                        onTap: () => _stepZoom(true),
                        tooltip: 'تكبير',
                        iconMuted: iconMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ─── RIGHT: Tools + Utility Buttons ────────────────────
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    // Search
                    _buildToolButton(
                      icon: LucideIcons.search,
                      isActive: widget.isSearchVisible,
                      onTap: widget.onToggleSearch,
                      tooltip: 'بحث (Ctrl+F)',
                      iconMuted: iconMuted,
                    ),
                    const SizedBox(width: 4),

                    // Bookmark
                    _buildToolButton(
                      icon: LucideIcons.bookmark,
                      isActive: false,
                      onTap: () {
                        if (pdf != null && widget.pdfController.isReady) {
                          widget.onAddBookmark(pdf);
                        }
                      },
                      tooltip: 'إضافة علامة مرجعية',
                      iconMuted: iconMuted,
                    ),
                    const SizedBox(width: 8),

                    // ─── Divider ──
                    Container(width: 1, height: 28, color: separatorColor),
                    const SizedBox(width: 8),

                    // ─── Drawing Tools Group ──
                    Container(
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildToolButton(
                            icon: LucideIcons.hand,
                            isActive: widget.activeTool == ToolType.cursor,
                            onTap: () {
                              widget.onToolChanged(ToolType.cursor);
                            },
                            tooltip: 'تحريك/تمرير (Esc)',
                            iconMuted: iconMuted,
                          ),
                          const SizedBox(width: 2),
                          _buildToolButton(
                            icon: LucideIcons.mousePointer2,
                            isActive: widget.activeTool == ToolType.select,
                            onTap: () {
                              // Selection mode: move/select items without opening shape UI.
                              widget.onToolChanged(ToolType.select);
                            },
                            tooltip: 'تحديد / تحريك العناصر',
                            iconMuted: iconMuted,
                          ),
                          const SizedBox(width: 2),
                          _buildToolButton(
                            icon: LucideIcons.shapes,
                            isActive:
                                widget.isShapesPaletteVisible ||
                                [
                                  ToolType.arrow,
                                  ToolType.rectangle,
                                  ToolType.circle,
                                ].contains(widget.activeTool) ||
                                isSelectedShapeTool,
                            onTap: () {
                              // Keep selection in select mode while opening shape controls.
                              if (!isSelectedShapeTool) {
                                widget.onToolChanged(ToolType.arrow);
                              }
                              if (!widget.isRightPanelOpen) {
                                widget.onToggleRightPanel();
                              }
                              if (!widget.isShapesPaletteVisible) {
                                widget.onToggleShapesPalette();
                              }
                            },
                            tooltip: 'أدوات الأشكال',
                            iconMuted: iconMuted,
                          ),
                          const SizedBox(width: 2),
                          _buildToolButton(
                            icon: LucideIcons.highlighter,
                            isActive:
                                widget.activeTool == ToolType.highlight ||
                                isSelectedHighlightTool,
                            onTap: () {
                              // Keep selection in select mode while opening highlight controls.
                              if (!isSelectedHighlightTool) {
                                widget.onToolChanged(ToolType.highlight);
                              }
                              if (!widget.isRightPanelOpen) {
                                widget.onToggleRightPanel();
                              }
                            },
                            tooltip: 'هايلايت (H)',
                            activeColor: const Color(0xFFEAB308),
                            iconMuted: iconMuted,
                          ),
                          const SizedBox(width: 2),
                          _buildToolButton(
                            icon: LucideIcons.penTool,
                            isActive: widget.activeTool == ToolType.pen,
                            onTap: () => widget.onToolChanged(ToolType.pen),
                            tooltip: 'قلم (P)',
                            iconMuted: iconMuted,
                          ),
                          const SizedBox(width: 2),
                          _buildToolButton(
                            icon: LucideIcons.type,
                            isActive: widget.activeTool == ToolType.text,
                            onTap: () => widget.onToolChanged(ToolType.text),
                            tooltip: 'نص (T)',
                            iconMuted: iconMuted,
                          ),
                          const SizedBox(width: 2),
                          _buildToolButton(
                            icon: LucideIcons.eraser,
                            isActive: widget.activeTool == ToolType.eraser,
                            onTap: () => widget.onToolChanged(ToolType.eraser),
                            tooltip: 'ممحاة (E)',
                            activeColor: const Color(0xFFEF4444),
                            iconMuted: iconMuted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 170),

                    // ─── Divider ──
                    Container(width: 1, height: 28, color: separatorColor),
                    const SizedBox(width: 8),

                    // Close File
                    _buildToolButton(
                      icon: LucideIcons.x,
                      isActive: false,
                      onTap: () => app.closeActivePdf(),
                      tooltip: 'إغلاق الملف',
                      iconMuted: iconMuted,
                    ),
                    const SizedBox(width: 4),

                    // Settings
                    _buildToolButton(
                      icon: LucideIcons.settings,
                      isActive: false,
                      onTap: widget.onToggleSettings,
                      tooltip: 'إعدادات المستند',
                      iconMuted: iconMuted,
                    ),
                    const SizedBox(width: 4),

                    // Right Panel Toggle
                    _buildToolButton(
                      icon: widget.isRightPanelOpen
                          ? LucideIcons.panelRightClose
                          : LucideIcons.panelRightOpen,
                      isActive: widget.isRightPanelOpen,
                      onTap: widget.onToggleRightPanel,
                      tooltip: 'إظهار/إخفاء لوحة الخصائص (Ctrl+R)',
                      iconMuted: iconMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
