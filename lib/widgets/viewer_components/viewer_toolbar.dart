import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';

class StudyFlowToolbar extends StatefulWidget {
  final ToolType activeTool;
  final bool isRightPanelOpen;
  final bool isDarkMode;
  final bool isSearchVisible;
  final PdfItem? activePdf;
  final PdfViewerController pdfController;
  final ValueChanged<ToolType> onToolChanged;
  final VoidCallback onToggleRightPanel;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onToggleSearch;
  final Function(PdfItem) onPrint;
  final Function(PdfItem) onAddPage;
  final Function(PdfItem) onDeletePage;
  final Function(PdfItem) onAddBookmark;

  const StudyFlowToolbar({
    super.key,
    required this.activeTool,
    required this.isRightPanelOpen,
    required this.isDarkMode,
    required this.isSearchVisible,
    required this.activePdf,
    required this.pdfController,
    required this.onToolChanged,
    required this.onToggleRightPanel,
    required this.onToggleDarkMode,
    required this.onToggleSearch,
    required this.onPrint,
    required this.onAddPage,
    required this.onDeletePage,
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>(); // Access AppProvider for sidebar
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
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          bottom: BorderSide(
            color: barBorder,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (isMobile)
                IconButton(
                  icon: Icon(
                    LucideIcons.menu,
                    color: iconMuted,
                  ),
                  onPressed: () => app.toggleMobile(),
                )
              else if (app.isSidebarCollapsed)
                IconButton(
                  icon: Icon(
                    LucideIcons.panelLeftOpen,
                    color: iconMuted,
                  ),
                  onPressed: () {
                    app.toggleSidebar();
                  },
                  tooltip: 'Toggle Sidebar (Ctrl+L)',
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
                              borderSide: BorderSide(
                                color: inputBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: inputBorder,
                              ),
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
                            color: const Color(
                              0xFF1E293B,
                            ), // Fixed Dark: Slate 800
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

              const SizedBox(width: 12),

              // Zoom Controls
              Container(
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        LucideIcons.zoomOut,
                        size: 18,
                        color: iconMuted,
                      ),
                      onPressed: () => widget.pdfController.zoomDown(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        LucideIcons.zoomIn,
                        size: 18,
                        color: iconMuted,
                      ),
                      onPressed: () => widget.pdfController.zoomUp(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  // Search Button
                  Container(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: const Icon(LucideIcons.search, size: 20),
                      onPressed: widget.onToggleSearch,
                      tooltip: 'Search (Ctrl+F)',
                      color: widget.isSearchVisible
                          ? const Color(0xFF3B82F6)
                          : iconMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Bookmark Button
                  Container(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: const Icon(LucideIcons.bookmark, size: 20),
                      onPressed: () {
                        if (pdf != null && widget.pdfController.isReady) {
                          widget.onAddBookmark(pdf);
                        }
                      },
                      tooltip: 'Add Bookmark',
                      color: iconMuted,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Tools
                  Container(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToolBtn(
                          icon: LucideIcons.mousePointer2,
                          label: 'Read',
                          isActive: [
                            ToolType.cursor,
                            ToolType.arrow,
                            ToolType.rectangle,
                            ToolType.circle,
                          ].contains(widget.activeTool),
                          onPressed: () {
                            widget.onToolChanged(ToolType.cursor);
                            if (!widget.isRightPanelOpen) {
                              widget.onToggleRightPanel();
                            }
                          },
                          shortcut: 'Esc',
                        ),
                        _ToolBtn(
                          icon: LucideIcons.highlighter,
                          label: 'Highlight',
                          isActive: widget.activeTool == ToolType.highlight,
                          onPressed: () =>
                              widget.onToolChanged(ToolType.highlight),
                          shortcut: 'H',
                        ),
                        _ToolBtn(
                          icon: LucideIcons.penTool,
                          label: 'Pen',
                          isActive: widget.activeTool == ToolType.pen,
                          onPressed: () => widget.onToolChanged(ToolType.pen),
                          shortcut: 'P',
                        ),
                        _ToolBtn(
                          icon: LucideIcons.type,
                          label: 'Text',
                          isActive: widget.activeTool == ToolType.text,
                          onPressed: () => widget.onToolChanged(ToolType.text),
                          shortcut: 'T',
                        ),
                        _ToolBtn(
                          icon: LucideIcons.eraser,
                          label: 'Eraser',
                          isActive: widget.activeTool == ToolType.eraser,
                          onPressed: () =>
                              widget.onToolChanged(ToolType.eraser),
                          shortcut: 'E',
                        ),
                      ],
                    ),
                  ),
                  if (pdf != null) const SizedBox(width: 12),
                  // Printer & Dark Mode
                  Container(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.printer, size: 20),
                          onPressed: pdf != null
                              ? () => widget.onPrint(pdf)
                              : null,
                          tooltip: 'Print (Ctrl+P)',
                          color: iconMuted,
                        ),
                        IconButton(
                          icon: Icon(
                            widget.isDarkMode
                                ? LucideIcons.sun
                                : LucideIcons.moon,
                            size: 20,
                          ),
                          onPressed: widget.onToggleDarkMode,
                          tooltip: 'Toggle Dark Mode',
                          color: widget.isDarkMode
                              ? const Color(0xFFEAB308)
                              : iconMuted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Edit Pages
                  Container(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.filePlus, size: 20),
                          onPressed: pdf == null
                              ? null
                              : () => widget.onAddPage(pdf),
                          tooltip: 'Add Page',
                          color: iconMuted,
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.fileMinus, size: 20),
                          onPressed: pdf == null
                              ? null
                              : () => widget.onDeletePage(pdf),
                          tooltip: 'Delete Current Page',
                          color: const Color(0xFFDC2626),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Close File
                  Container(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => app.closeActivePdf(),
                      tooltip: 'Close File',
                      color: iconMuted,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Right Panel Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: Icon(
                        widget.isRightPanelOpen
                            ? LucideIcons.panelRightClose
                            : LucideIcons.panelRightOpen,
                        size: 20,
                      ),
                      onPressed: widget.onToggleRightPanel,
                      tooltip: 'Toggle Properties Panel (Ctrl+R)',
                      color: widget.isRightPanelOpen
                          ? const Color(0xFF3B82F6)
                          : iconMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;
  final String? shortcut;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context) {
    final iconMuted = Theme.of(context).colorScheme.onSurfaceVariant;
    Color activeColor = const Color(0xFF3B82F6); // Fixed Blue 500
    if (label == 'Highlight')
      activeColor = const Color(0xFFEAB308); // Fixed Yellow 500
    if (label == 'Eraser')
      activeColor = const Color(0xFFEF4444); // Fixed Red 500
    if (label == 'Pen')
      activeColor = const Color(0xFFF8FAFC); // Fixed Pen White
    if (label == 'Note')
      activeColor = const Color(0xFF8B5CF6); // Fixed Purple 500

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive
              ? Border.all(color: Colors.white.withOpacity(0.1))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? activeColor
                  : iconMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? activeColor
                    : iconMuted,
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(
                    0.2,
                  ), // Darker background for shortcut
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  shortcut!,
                  style: TextStyle(
                    fontSize: 10,
                    color: iconMuted,
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
