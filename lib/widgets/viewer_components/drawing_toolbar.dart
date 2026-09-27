import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/models.dart';

class DrawingToolbar extends StatelessWidget {
  final ToolType activeTool;
  final ValueChanged<ToolType> onToolChanged;
  final Color activeColor;
  final double strokeWidth;
  final Color? fillColor;
  final bool showFill;
  final bool isDarkMode;
  final int colorPaletteIndex;
  final VoidCallback? onTogglePalette;
  final VoidCallback? onDeleteSelected;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<Color>? onFillColorChanged;
  final VoidCallback? onToggleFill;

  const DrawingToolbar({
    super.key,
    required this.activeTool,
    required this.onToolChanged,
    required this.activeColor,
    required this.strokeWidth,
    this.fillColor,
    this.showFill = false,
    required this.isDarkMode,
    this.colorPaletteIndex = 0,
    this.onTogglePalette,
    this.onDeleteSelected,
    required this.onStrokeWidthChanged,
    required this.onColorChanged,
    this.onFillColorChanged,
    this.onToggleFill,
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
    final activeBlue = const Color(0xFF3B82F6);
    final activeRed = const Color(0xFFEF4444);

    return TapRegion(
      groupId: 'drawing_toolbar_region',
      child: Material(
        elevation: 6,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolChip(
                  icon: LucideIcons.arrowUpRight,
                  label: 'سهم',
                  tool: ToolType.arrow,
                  iconColor: iconColor,
                ),
                const SizedBox(width: 6),
                _buildToolChip(
                  icon: LucideIcons.square,
                  label: 'مستطيل',
                  tool: ToolType.rectangle,
                  iconColor: iconColor,
                ),
                const SizedBox(width: 6),
                _buildToolChip(
                  icon: LucideIcons.circle,
                  label: 'دائرة',
                  tool: ToolType.circle,
                  iconColor: iconColor,
                ),
                const SizedBox(width: 6),
                const SizedBox(width: 10),
                Container(width: 1, height: 28, color: borderColor),
                const SizedBox(width: 10),
                Icon(LucideIcons.minus, size: 16, color: iconColor),
                SizedBox(
                  width: 120,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      activeTrackColor: activeBlue,
                      inactiveTrackColor: iconColor.withOpacity(0.2),
                      thumbColor: activeBlue,
                    ),
                    child: Slider(
                      // Only shapes reach this toolbar, so the pen/highlighter
                      // width range no longer applies here.
                      value: strokeWidth.clamp(1.0, 12.0),
                      min: 1.0,
                      max: 12.0,
                      divisions: 11,
                      onChanged: onStrokeWidthChanged,
                    ),
                  ),
                ),
                Icon(LucideIcons.plus, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Text(
                  strokeWidth.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 10),
                Container(width: 1, height: 28, color: borderColor),
                const SizedBox(width: 10),
                _buildColorPills(),
                if (showFill && onFillColorChanged != null) ...[
                  const SizedBox(width: 10),
                  Container(width: 1, height: 28, color: borderColor),
                  const SizedBox(width: 10),
                  _buildFillControl(iconColor),
                ],
                if (activeTool == ToolType.select && onDeleteSelected != null) ...[
                  const SizedBox(width: 10),
                  Container(width: 1, height: 28, color: borderColor),
                  const SizedBox(width: 10),
                  _buildActionButton(
                    icon: LucideIcons.trash2,
                    label: 'حذف المحدد',
                    color: activeRed,
                    onTap: onDeleteSelected,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolChip({
    required IconData icon,
    required String label,
    required ToolType tool,
    required Color iconColor,
  }) {
    final isActive = activeTool == tool;
    final bg = isActive ? const Color(0xFF3B82F6).withOpacity(0.14) : Colors.transparent;
    final fg = isActive ? const Color(0xFF3B82F6) : iconColor;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => onToolChanged(tool),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? const Color(0xFF3B82F6).withOpacity(0.35) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorPills() {
    final basicColors = const [
      Color(0xFFFFFFFF),
      Color(0xFF000000),
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
    ];
    final extendedColors = const [
      Color(0xFFFFFFFF),
      Color(0xFF78716C),
      Color(0xFFEC4899),
      Color(0xFFFBBF24),
      Color(0xFF84CC16),
      Color(0xFF06B6D4),
      Color(0xFF6366F1),
    ];

    // Only the three shapes live here, so the highlighter's pastel palettes
    // and the eraser's empty palette moved to ViewerSideRail.
    final colors =
        colorPaletteIndex == 0 ? basicColors : extendedColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...colors.map((color) {
          final selected = color.value == activeColor.value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onColorChanged(color),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white.withOpacity(0.0),
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 5)]
                      : null,
                ),
              ),
            ),
          );
        }),
        if (onTogglePalette != null) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onTogglePalette,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: colorPaletteIndex == 0
                    ? const Color(0xFFA78BFA)
                    : const Color(0xFF34D399),
                shape: BoxShape.circle,
              ),
              child: Icon(
                colorPaletteIndex == 0
                    ? LucideIcons.chevronDown
                    : LucideIcons.chevronUp,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFillControl(Color iconColor) {
    final currentFill = fillColor ?? Colors.transparent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('تعبئة', style: TextStyle(fontSize: 12, color: iconColor)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onToggleFill,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: currentFill,
              shape: BoxShape.circle,
              border: Border.all(color: iconColor),
            ),
            child: fillColor == null || fillColor == Colors.transparent
                ? Icon(LucideIcons.x, size: 12, color: iconColor)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}