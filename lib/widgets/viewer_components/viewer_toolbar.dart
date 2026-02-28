import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';

class StudyFlowToolbar extends StatefulWidget {
  final ToolType activeTool;
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
  final TextEditingController _pageInputController = TextEditingController();

  @override
  void dispose() {
    _pageInputController.dispose();
    super.dispose();
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
    final barBorder = widget.isDarkMode
        ? const Color(0xFF334155)
        : scheme.outlineVariant;
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

    return TextFieldTapRegion(
      child: Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: barBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ─── LEFT: Sidebar + Page Counter + Zoom ───────────────
          Row(
            children: [
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
                  tooltip: 'Toggle Sidebar (Ctrl+L)',
                  iconMuted: iconMuted,
                ),
              if (isMobile || app.isSidebarCollapsed) const SizedBox(width: 8),

              // Page Counter
              if (pdf != null)
                _isEditingPage
                    ? SizedBox(
                        width: 50,
                        height: 30,
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: chipBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.pdfController.isReady
                                ? '${widget.pdfController.pageNumber} / ${widget.pdfController.pages.length}'
                                : 'Loading...',
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
                      onTap: () => widget.pdfController.zoomDown(),
                      tooltip: 'Zoom Out',
                      iconMuted: iconMuted,
                    ),
                    _buildToolButton(
                      icon: LucideIcons.zoomIn,
                      isActive: false,
                      onTap: () => widget.pdfController.zoomUp(),
                      tooltip: 'Zoom In',
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
                    tooltip: 'Search (Ctrl+F)',
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
                    tooltip: 'Add Bookmark',
                    iconMuted: iconMuted,
                  ),
                  const SizedBox(width: 8),

                  // ─── Divider ──
                  Container(width: 1, height: 28, color: barBorder),
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
                          tooltip: 'Hand / Scroll (Esc)',
                          iconMuted: iconMuted,
                        ),
                        const SizedBox(width: 2),
                        _buildToolButton(
                          icon: LucideIcons.mousePointer2,
                          isActive: [
                            ToolType.select,
                            ToolType.arrow,
                            ToolType.rectangle,
                            ToolType.circle,
                          ].contains(widget.activeTool),
                          onTap: () {
                            widget.onToolChanged(ToolType.select);
                            if (!widget.isRightPanelOpen) {
                              widget.onToggleRightPanel();
                            }
                          },
                          tooltip: 'Select',
                          iconMuted: iconMuted,
                        ),
                        const SizedBox(width: 2),
                        _buildToolButton(
                          icon: LucideIcons.shapes,
                          isActive: widget.isShapesPaletteVisible,
                          onTap: widget.onToggleShapesPalette,
                          tooltip: 'Shapes',
                          iconMuted: iconMuted,
                        ),
                        const SizedBox(width: 2),
                        _buildToolButton(
                          icon: LucideIcons.highlighter,
                          isActive: widget.activeTool == ToolType.highlight,
                          onTap: () => widget.onToolChanged(ToolType.highlight),
                          tooltip: 'Highlight (H)',
                          activeColor: const Color(0xFFEAB308),
                          iconMuted: iconMuted,
                        ),
                        const SizedBox(width: 2),
                        _buildToolButton(
                          icon: LucideIcons.penTool,
                          isActive: widget.activeTool == ToolType.pen,
                          onTap: () => widget.onToolChanged(ToolType.pen),
                          tooltip: 'Pen (P)',
                          iconMuted: iconMuted,
                        ),
                        const SizedBox(width: 2),
                        _buildToolButton(
                          icon: LucideIcons.type,
                          isActive: widget.activeTool == ToolType.text,
                          onTap: () => widget.onToolChanged(ToolType.text),
                          tooltip: 'Text (T)',
                          iconMuted: iconMuted,
                        ),
                        const SizedBox(width: 2),
                        _buildToolButton(
                          icon: LucideIcons.eraser,
                          isActive: widget.activeTool == ToolType.eraser,
                          onTap: () => widget.onToolChanged(ToolType.eraser),
                          tooltip: 'Eraser (E)',
                          activeColor: const Color(0xFFEF4444),
                          iconMuted: iconMuted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // ─── Divider ──
                  Container(width: 1, height: 28, color: barBorder),
                  const SizedBox(width: 8),

                  // Close File
                  _buildToolButton(
                    icon: LucideIcons.x,
                    isActive: false,
                    onTap: () => app.closeActivePdf(),
                    tooltip: 'Close File',
                    iconMuted: iconMuted,
                  ),
                  const SizedBox(width: 4),

                  // Settings
                  _buildToolButton(
                    icon: LucideIcons.settings,
                    isActive: false,
                    onTap: widget.onToggleSettings,
                    tooltip: 'Document Settings',
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
                    tooltip: 'Toggle Properties Panel (Ctrl+R)',
                    iconMuted: iconMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),    ),    );
  }
}
