import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/models.dart';
import '../../utils/responsive_utils.dart';
import 'viewer_toolbar.dart';

/// Slim vertical tool rail pinned to the right edge of the viewer.
///
/// It is always mounted: closing the right panel slides that panel away to the
/// right edge, and this rail drifts left with it instead of disappearing. The
/// rail never animates on its own — the movement is inherited from the
/// animated width of its sibling, which is what keeps the two in step.
///
/// Tools that need settings (pen, highlighter, eraser) own them here, in a
/// block that only appears while such a tool is active. The floating toolbar
/// was left to the three geometric shapes alone, so the two surfaces never
/// show the same tool twice.
///
/// The rail only exists on tablet and desktop. Phones keep the keyboard
/// shortcuts and the right panel's tools tab, which is a deliberate trade:
/// 56px of a phone screen is not worth spending on a permanently visible rail.
class ViewerSideRail extends StatelessWidget {
  const ViewerSideRail({
    super.key,
    required this.isDarkMode,
    required this.activeTool,
    required this.isSearchVisible,
    required this.isFloatingToolbarOpen,
    required this.floatingToolbarSelectedTool,
    required this.activePdf,
    required this.pdfController,
    required this.onToggleSearch,
    required this.onToolChanged,
    required this.onFloatingToolbarToggle,
    required this.onAddBookmark,
    required this.strokeWidth,
    required this.onStrokeWidthChanged,
    required this.penColor,
    required this.highlightColor,
    required this.onColorChanged,
    required this.colorPaletteIndex,
    required this.onTogglePalette,
    required this.onUndo,
    required this.onRedo,
  });

  final bool isDarkMode;
  final ToolType activeTool;
  final bool isSearchVisible;
  final bool isFloatingToolbarOpen;
  final ToolType? floatingToolbarSelectedTool;
  final PdfItem? activePdf;
  final PdfViewerController pdfController;
  final VoidCallback onToggleSearch;
  final ValueChanged<ToolType> onToolChanged;
  final ValueChanged<ToolType?>? onFloatingToolbarToggle;
  final Function(PdfItem) onAddBookmark;

  // Settings for the tools that live in the rail, so they no longer depend on
  // the floating toolbar being open.
  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthChanged;
  final Color penColor;
  final Color highlightColor;
  final ValueChanged<Color> onColorChanged;
  final int colorPaletteIndex;
  final VoidCallback? onTogglePalette;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  static const Color _activeColor = Color(0xFF3B82F6);

  /// True when the rail is worth the horizontal space it takes from the page
  /// area. Phones are excluded on purpose.
  static bool shouldShow(double width) =>
      ResponsiveBreakpoints.isTablet(width) ||
      ResponsiveBreakpoints.isDesktop(width);

  /// Width range of the tools that live in the rail. The highlighter takes a
  /// much wider stroke than the pen, and these match the bounds the drawing
  /// toolbar used to enforce.
  static const double _penMinWidth = 1.0;
  static const double _penMaxWidth = 12.0;
  static const double _highlightMinWidth = 1.0;
  static const double _highlightMaxWidth = 30.0;

  static const List<Color> _penColors = [
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
  ];

  static const List<Color> _penColorsExtended = [
    Color(0xFFFFFFFF),
    Color(0xFF78716C),
    Color(0xFFEC4899),
    Color(0xFFFBBF24),
    Color(0xFF84CC16),
    Color(0xFF06B6D4),
    Color(0xFF6366F1),
  ];

  static const List<Color> _highlightColors = [
    Color(0xFFFFFFFF),
    Color(0xFFFBEA7A),
    Color(0xFFA4D376),
    Color(0xFF84C0F2),
    Color(0xFFF59EB9),
    Color(0xFFC9A6D8),
  ];

  static const List<Color> _highlightColorsExtended = [
    Color(0xFFFFFFFF),
    Color(0xFFFBD38D),
    Color(0xFFA7F3D0),
    Color(0xFFBAE6FD),
    Color(0xFFFECDD3),
    Color(0xFFDDD6FE),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Same palette as the top bar, so the two read as one surface.
    final barBg = isDarkMode ? const Color(0xFF0F172A) : scheme.surface;
    final separatorColor = isDarkMode
        ? Colors.white.withOpacity(0.1)
        : Colors.black.withOpacity(0.05);
    final iconMuted =
        isDarkMode ? const Color(0xFF94A3B8) : scheme.onSurfaceVariant;

    final showToolSettings = activeTool == ToolType.pen ||
        activeTool == ToolType.highlight ||
        activeTool == ToolType.eraser;

    return Container(
      width: 56,
      // The rail is a full-height strip on the right edge. The parent Row uses
      // the default centre cross-alignment, so the height has to be claimed
      // explicitly; the incoming maxHeight is finite and clamps this to it.
      height: double.infinity,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(left: BorderSide(color: separatorColor, width: 1)),
      ),
      // The tool settings block makes this column far taller than a short
      // window, so it scrolls rather than overflowing.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _RailButton(
              icon: LucideIcons.search,
              isActive: isSearchVisible,
              iconMuted: iconMuted,
              tooltip: 'بحث (Ctrl+F)',
              onTap: onToggleSearch,
            ),

            const SizedBox(height: 8),
            _RailDivider(color: separatorColor),

            _RailButton(
              icon: LucideIcons.hand,
              isActive: activeTool == ToolType.cursor,
              iconMuted: iconMuted,
              tooltip: 'تحريك/تمرير (Esc)',
              onTap: () => onToolChanged(ToolType.cursor),
            ),
            _RailButton(
              icon: LucideIcons.mousePointer2,
              isActive: activeTool == ToolType.select,
              iconMuted: iconMuted,
              tooltip: 'تحديد / تحريك العناصر',
              onTap: () => onToolChanged(ToolType.select),
            ),
            _RailButton(
              icon: LucideIcons.type,
              isActive: activeTool == ToolType.text,
              iconMuted: iconMuted,
              tooltip: 'نص (Ctrl+T)',
              onTap: () => onToolChanged(ToolType.text),
            ),
            _RailButton(
              icon: LucideIcons.penTool,
              isActive: activeTool == ToolType.pen,
              iconMuted: iconMuted,
              tooltip: 'قلم (Ctrl+P)',
              onTap: () => onToolChanged(ToolType.pen),
            ),
            _RailButton(
              icon: LucideIcons.highlighter,
              isActive: activeTool == ToolType.highlight,
              iconMuted: iconMuted,
              tooltip: 'تظليل (Ctrl+H)',
              onTap: () => onToolChanged(ToolType.highlight),
            ),
            _RailButton(
              icon: LucideIcons.eraser,
              isActive: activeTool == ToolType.eraser,
              iconMuted: iconMuted,
              tooltip: 'ممحاة (Ctrl+E)',
              onTap: () => onToolChanged(ToolType.eraser),
            ),
            _RailButton(
              key: const ValueKey('rail_tool_selector_btn'),
              icon: floatingToolbarSelectedTool != null
                  ? StudyFlowToolbar.iconForTool(floatingToolbarSelectedTool!)
                  : LucideIcons.shapes,
              isActive: isFloatingToolbarOpen,
              iconMuted: iconMuted,
              tooltip: 'أشكال هندسية',
              onTap: () {
                if (isFloatingToolbarOpen) {
                  // Same toggle-off contract as the old top-bar button: hide
                  // the floating toolbar and fall back to the hand tool.
                  onFloatingToolbarToggle?.call(null);
                  onToolChanged(ToolType.cursor);
                } else {
                  // Reopen on the last shape used, so the toolbar never opens
                  // holding a tool it no longer has a chip for.
                  final shape =
                      floatingToolbarSelectedTool ?? ToolType.rectangle;
                  onFloatingToolbarToggle?.call(shape);
                  onToolChanged(shape);
                }
              },
            ),

            if (showToolSettings) ...[
              const SizedBox(height: 8),
              _RailDivider(color: separatorColor),
              _buildToolSettings(context, iconMuted),
            ],

            const SizedBox(height: 8),
            _RailDivider(color: separatorColor),

            _RailButton(
              icon: LucideIcons.bookmark,
              isActive: false,
              iconMuted: iconMuted,
              tooltip: 'حفظ كعلامة مرجعية',
              onTap: () {
                if (activePdf != null && pdfController.isReady) {
                  onAddBookmark(activePdf!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'تم حفظ الصفحة كعلامة مرجعية',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      duration: Duration(seconds: 2),
                      backgroundColor: _activeColor,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Settings for the rail's own tools: stroke width and colours for the pen
  /// and the highlighter, undo/redo for the eraser.
  Widget _buildToolSettings(BuildContext context, Color iconMuted) {
    if (activeTool == ToolType.eraser) {
      // The eraser has neither a colour nor a width, so history is all it
      // needs.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailButton(
            icon: LucideIcons.undo2,
            isActive: false,
            iconMuted: iconMuted,
            tooltip: 'تراجع',
            onTap: () => onUndo?.call(),
          ),
          _RailButton(
            icon: LucideIcons.redo2,
            isActive: false,
            iconMuted: iconMuted,
            tooltip: 'تقدم',
            onTap: () => onRedo?.call(),
          ),
        ],
      );
    }

    final isHighlight = activeTool == ToolType.highlight;
    final minWidth =
        isHighlight ? _highlightMinWidth : _penMinWidth;
    final maxWidth =
        isHighlight ? _highlightMaxWidth : _penMaxWidth;
    final activeColor = isHighlight ? highlightColor : penColor;
    final colors = colorPaletteIndex == 0
        ? (isHighlight ? _highlightColors : _penColors)
        : (isHighlight ? _highlightColorsExtended : _penColorsExtended);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'سماكة الخط',
          child: RotatedBox(
            quarterTurns: 1,
            child: SizedBox(
              width: 110,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: _activeColor,
                  inactiveTrackColor: iconMuted.withOpacity(0.2),
                  thumbColor: _activeColor,
                ),
                child: Slider(
                  value: strokeWidth.clamp(minWidth, maxWidth),
                  min: minWidth,
                  max: maxWidth,
                  divisions: (maxWidth - minWidth).round(),
                  onChanged: onStrokeWidthChanged,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strokeWidth.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: iconMuted,
          ),
        ),
        const SizedBox(height: 8),
        ...colors.map(
          (color) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: GestureDetector(
              onTap: () => onColorChanged(color),
              child: Tooltip(
                message: 'لون ${color.toARGB32().toRadixString(16)}',
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: activeColor.value == color.value
                          ? Colors.white
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: activeColor.value == color.value
                        ? [
                            BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onTogglePalette != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onTogglePalette,
            child: Tooltip(
              message: colorPaletteIndex == 0 ? 'ألوان إضافية' : 'ألوان أساسية',
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFFA78BFA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 28, height: 1, color: color);
  }
}

/// Mirrors the top bar's tool button so a tool looks identical wherever it
/// lives: 40x40, a 15% active tint, and the same icon size.
class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.icon,
    required this.isActive,
    required this.iconMuted,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool isActive;
  final Color iconMuted;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fgColor = isActive ? ViewerSideRail._activeColor : iconMuted;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? ViewerSideRail._activeColor.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 22, color: fgColor),
        ),
      ),
    );
  }
}
