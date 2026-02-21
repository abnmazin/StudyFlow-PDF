import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';

class StudyFlowRightPanel extends StatelessWidget {
  final ToolType activeTool;
  final Color activeColor;
  final double strokeWidth;
  final double fontSize;
  final bool isBold;
  final bool isLatex; // NEW: LaTeX mode flag
  final bool showBorder;
  final Color borderColor;
  final Color bgColor;
  final int activeTabIndex;
  final bool isDarkMode;
  final PdfItem? activePdf;
  final PdfViewerController pdfController;
  final ValueChanged<ToolType> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<bool> onBoldChanged;
  final ValueChanged<bool> onLatexChanged; // NEW
  final ValueChanged<bool> onShowBorderChanged;
  final ValueChanged<Color> onBorderColorChanged;
  final ValueChanged<Color> onBgColorChanged;
  final ValueChanged<int> onTabChanged;

  const StudyFlowRightPanel({
    super.key,
    required this.activeTool,
    required this.activeColor,
    required this.strokeWidth,
    required this.fontSize,
    required this.isBold,
    required this.isLatex, // NEW
    required this.showBorder,
    required this.borderColor,
    required this.bgColor,
    required this.activeTabIndex,
    required this.isDarkMode,
    required this.activePdf,
    required this.pdfController,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onFontSizeChanged,
    required this.onBoldChanged,
    required this.onLatexChanged, // NEW
    required this.onShowBorderChanged,
    required this.onBorderColorChanged,
    required this.onBgColorChanged,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isGlobalEditing = appProvider.activeEditingCommentId != null;
    final editingStyles = isGlobalEditing
        ? appProvider.getEditingStyles(appProvider.activeEditingCommentId!)
        : null;

    // Resolve Effective Styles (Editing > Default)
    // We use 'num' for fontSize to strictly handle int/double safety
    final effectiveFontSize =
        (isGlobalEditing && editingStyles?['fontSize'] != null)
        ? (editingStyles!['fontSize'] as num).toDouble()
        : fontSize;

    // Color is managed per tool below
    final effectiveColor = (isGlobalEditing && editingStyles?['color'] != null)
        ? Color(editingStyles!['color'])
        : activeColor;

    final effectiveIsBold =
        (isGlobalEditing && editingStyles?['isBold'] != null)
        ? (editingStyles!['isBold'] as bool)
        : isBold;

    final effectiveIsLatex =
        (isGlobalEditing && editingStyles?['isLatex'] != null)
        ? (editingStyles!['isLatex'] as bool)
        : isLatex;

    final effectiveShowBorder =
        (isGlobalEditing && editingStyles?['showBorder'] != null)
        ? (editingStyles!['showBorder'] as bool)
        : showBorder;

    final effectiveBorderColor =
        (isGlobalEditing && editingStyles?['borderColor'] != null)
        ? Color(editingStyles!['borderColor'])
        : borderColor;

    final effectiveBgColor =
        (isGlobalEditing && editingStyles?['bgColor'] != null)
        ? Color(editingStyles!['bgColor'])
        : bgColor;

    return Container(
      width: 320, // Wider for Chat UI
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Fixed Dark: Slate 900
        border: Border(
          left: BorderSide(
            color: Color(0xFF334155), // Fixed Dark: Slate 700
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        children: [
          // --- TAB BAR ---
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B), // Fixed Dark: Slate 800
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF334155), // Fixed Dark: Slate 700
                ),
              ),
            ),
            child: Row(
              children: [
                _buildPanelTab(0, LucideIcons.settings, 'Tools'),
              ],
            ),
          ),

          // --- TAB CONTENT ---
          Expanded(
            child: IndexedStack(
              index: activeTabIndex,
              children: [
                // TAB 0: TOOLS (Legacy Logic Preserved)
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dynamic Title
                      Row(
                        children: [
                          Icon(
                            [
                                  ToolType.cursor,
                                  ToolType.arrow,
                                  ToolType.rectangle,
                                  ToolType.circle,
                                ].contains(activeTool)
                                ? LucideIcons.mousePointer2
                                : activeTool == ToolType.pen
                                ? LucideIcons.penTool
                                : activeTool == ToolType.highlight
                                ? LucideIcons.highlighter
                                : activeTool == ToolType.text
                                ? LucideIcons.type
                                : LucideIcons.settings,
                            size: 20,
                            color: const Color(
                              0xFF94A3B8,
                            ), // Fixed Dark: Slate 400
                          ),
                          const SizedBox(width: 8),
                          Text(
                            [
                                  ToolType.cursor,
                                  ToolType.arrow,
                                  ToolType.rectangle,
                                  ToolType.circle,
                                ].contains(activeTool)
                                ? 'Read & Shapes'
                                : '${activeTool.name[0].toUpperCase()}${activeTool.name.substring(1)} Properties',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white, // Fixed Dark: White
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // SHAPE SELECTOR (For Read/Cursor Mode)
                      if ([
                        ToolType.cursor,
                        ToolType.arrow,
                        ToolType.rectangle,
                        ToolType.circle,
                      ].contains(activeTool)) ...[
                        Text(
                          'Tool Mode',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8), // Fixed Dark: Slate 400
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildShapeSelectorBtn(
                              LucideIcons.mousePointer2,
                              ToolType.cursor,
                              'Pointer',
                            ),
                            _buildShapeSelectorBtn(
                              LucideIcons.arrowUpRight,
                              ToolType.arrow,
                              'Arrow',
                            ),
                            _buildShapeSelectorBtn(
                              LucideIcons.square,
                              ToolType.rectangle,
                              'Rectangle',
                            ),
                            _buildShapeSelectorBtn(
                              LucideIcons.circle,
                              ToolType.circle,
                              'Circle',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Text Tool Properties (Preserved)
                      if (activeTool == ToolType.text) ...[
                        Text(
                          'Font Size',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8), // Fixed Dark: Slate 400
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ExcludeFocus(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                                activeTrackColor: const Color(0xFF3B82F6),
                                inactiveTrackColor: const Color(
                                  0xFF334155,
                                ), // Fixed Dark: Slate 700
                                thumbColor: const Color(0xFF2563EB),
                              ),
                              child: Slider(
                                value: effectiveFontSize,
                                min: 10.0,
                                max: 48.0,
                                onChanged: (val) {
                                  if (isGlobalEditing) {
                                    appProvider.updateEditingStyle(
                                      commentId:
                                          appProvider.activeEditingCommentId!,
                                      fontSize: val,
                                    );
                                  } else {
                                    onFontSizeChanged(val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Bold',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(
                                  0xFF94A3B8,
                                ), // Fixed Dark: Slate 400
                              ),
                            ),
                            ExcludeFocus(
                              child: Switch(
                                value: effectiveIsBold,
                                onChanged: (val) {
                                  if (isGlobalEditing) {
                                    appProvider.updateEditingStyle(
                                      commentId:
                                          appProvider.activeEditingCommentId!,
                                      isBold: val,
                                    );
                                  } else {
                                    onBoldChanged(val);
                                  }
                                },
                                activeTrackColor: const Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // NEW: LaTeX Mode Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.sigma,
                                  size: 18,
                                  color: const Color(
                                    0xFF94A3B8,
                                  ), // Fixed Dark: Slate 400
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'LaTeX Mode',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(
                                      0xFF94A3B8,
                                    ), // Fixed Dark: Slate 400
                                  ),
                                ),
                              ],
                            ),
                            ExcludeFocus(
                              child: Switch(
                                value: effectiveIsLatex,
                                onChanged: (val) {
                                  if (isGlobalEditing) {
                                    appProvider.updateEditingStyle(
                                      commentId:
                                          appProvider.activeEditingCommentId!,
                                      isLatex: val,
                                    );
                                  } else {
                                    onLatexChanged(val);
                                  }
                                },
                                activeTrackColor: const Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ─── Show Border Toggle ───────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.square,
                                  size: 18,
                                  color: const Color(
                                    0xFF94A3B8,
                                  ), // Fixed Dark: Slate 400
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Show Border',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(
                                      0xFF94A3B8,
                                    ), // Fixed Dark: Slate 400
                                  ),
                                ),
                              ],
                            ),
                            ExcludeFocus(
                              child: Switch(
                                value: effectiveShowBorder,
                                onChanged: (val) {
                                  if (isGlobalEditing) {
                                    appProvider.updateEditingStyle(
                                      commentId:
                                          appProvider.activeEditingCommentId!,
                                      showBorder: val,
                                    );
                                  } else {
                                    onShowBorderChanged(val);
                                  }
                                },
                                activeTrackColor: const Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // ─── Border Colour Picker (only if border is ON) ──
                      if (effectiveShowBorder) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Border Color',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8), // Fixed Dark: Slate 400
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildColorPickerButton(
                          context,
                          effectiveBorderColor,
                          (color) {
                            if (isGlobalEditing) {
                              appProvider.updateEditingStyle(
                                commentId: appProvider.activeEditingCommentId!,
                                borderColor: color,
                              );
                            } else {
                              onBorderColorChanged(color);
                            }
                          },
                        ),
                      ],

                      // ─── Background Colour Picker ─────────────────────
                      const SizedBox(height: 24),
                      Text(
                        'Background Color',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8), // Fixed Dark: Slate 400
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildColorPickerButton(
                        context,
                        effectiveBgColor,
                        (color) {
                          if (isGlobalEditing) {
                            appProvider.updateEditingStyle(
                              commentId: appProvider.activeEditingCommentId!,
                              bgColor: color,
                            );
                          } else {
                            onBgColorChanged(color);
                          }
                        },
                        allowTransparent: true,  // Allow transparent for backgrounds
                      ),
                      const SizedBox(height: 24),

                      // Stroke Width & Color (Preserved)
                      if ([
                        ToolType.highlight,
                        ToolType.pen,
                        ToolType.text,
                        ToolType.arrow,
                        ToolType.rectangle,
                        ToolType.circle,
                      ].contains(activeTool)) ...[
                        if (activeTool != ToolType.text) ...[
                          Text(
                            'Stroke Width',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8), // Fixed Dark: Slate 400
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ExcludeFocus(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                  activeTrackColor: const Color(0xFF3B82F6),
                                  inactiveTrackColor: const Color(
                                    0xFF334155,
                                  ), // Fixed Dark: Slate 700
                                  thumbColor: const Color(0xFF2563EB),
                                ),
                                child: Slider(
                                  value: strokeWidth,
                                  min: 1.0,
                                  max: 20.0,
                                  onChanged: onStrokeWidthChanged,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        Text(
                          'Color',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8), // Fixed Dark: Slate 400
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildColorPickerButton(
                          context,
                          effectiveColor,
                          (color) {
                            if (isGlobalEditing) {
                              appProvider.updateEditingStyle(
                                commentId: appProvider.activeEditingCommentId!,
                                color: color,
                              );
                            } else {
                              onColorChanged(color);
                            }
                          },
                        ),
                      ] else if (!activeTool.toString().contains('cursor') &&
                          !activeTool.toString().contains('arrow') &&
                          !activeTool.toString().contains('rectangle') &&
                          !activeTool.toString().contains('circle'))
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: Text(
                              'No properties available\nfor this tool',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(
                                  0xFF94A3B8,
                                ), // Fixed Dark: Slate 400
                              ),
                            ),
                          ),
                        ),

                      // Bookmarks Section (Preserved)
                      const SizedBox(height: 32),
                      const Divider(color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 16),
                      Text(
                        'Bookmarks',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white, // Fixed Dark: White
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (activePdf != null && activePdf!.bookmarks.isNotEmpty)
                        ...activePdf!.bookmarks.map((bookmark) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(
                                color: Color(
                                  0xFF334155,
                                ), // Fixed Dark: Slate 700
                              ),
                            ),
                            color: const Color(
                              0xFF1E293B,
                            ), // Fixed Dark: Slate 800
                            child: InkWell(
                              onTap: () {
                                if (pdfController.isReady) {
                                  pdfController.goToPage(
                                    pageNumber: bookmark.page,
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.bookmark,
                                      size: 16,
                                      color: Color(0xFF3B82F6),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            bookmark.name,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors
                                                  .white, // Fixed Dark: White
                                            ),
                                          ),
                                          Text(
                                            'Page ${bookmark.page}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(
                                                0xFF94A3B8,
                                              ), // Fixed Dark: Slate 400
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        LucideIcons.trash2,
                                        size: 16,
                                        color: Color(0xFFDC2626),
                                      ),
                                      onPressed: () {
                                        context
                                            .read<AppProvider>()
                                            .deleteBookmark(
                                              activePdf!.id,
                                              bookmark.id,
                                            );
                                      },
                                      tooltip: 'Delete Bookmark',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        })
                      else
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              'No bookmarks yet',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(
                                  0xFF94A3B8,
                                ), // Fixed Dark: Slate 400
                              ),
                            ),
                          ),
                        ),


                    ],
                  ),
                ),


              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelTab(int index, IconData icon, String label) {
    final isActive = activeTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF334155) // Fixed Dark: Slate 700
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isActive ? const Color(0xFF6366F1) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF94A3B8), // Fixed Dark: Slate 400
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? const Color(0xFF6366F1)
                      : const Color(0xFF64748B), // Fixed Dark: Slate 500
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method for shape selector buttons in right panel
  Widget _buildShapeSelectorBtn(
    IconData icon,
    ToolType toolValue,
    String tooltip,
  ) {
    final isSelected = activeTool == toolValue;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onToolChanged(toolValue),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF312E81) // Fixed Dark: Indigo 900
                : const Color(0xFF1E293B), // Fixed Dark: Slate 800
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF818CF8) // Indigo 400
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected
                ? const Color(0xFF818CF8) // Fixed Dark: Indigo 400
                : const Color(0xFF94A3B8), // Fixed Dark: Slate 400
          ),
        ),
      ),
    );
  }



  // Helper method to show color picker dialog
  Future<void> _showColorPicker(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color> onColorChanged,
    {bool allowTransparent = false}  // Allow transparent option for backgrounds
  ) async {
    Color pickerColor = currentColor;
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B), // Slate 800
          title: const Text(
            'Pick a Color',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorPicker(
                  pickerColor: pickerColor == Colors.transparent 
                      ? Colors.white 
                      : pickerColor,
                  onColorChanged: (Color color) {
                    pickerColor = color;
                  },
                  pickerAreaHeightPercent: 0.8,
                  displayThumbColor: true,
                  enableAlpha: false,
                  labelTypes: const [],
                  pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                if (allowTransparent) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF64748B),
                    ),
                    icon: const Icon(LucideIcons.eyeOff, size: 18),
                    label: const Text('No Background (Transparent)'),
                    onPressed: () {
                      onColorChanged(Colors.transparent);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
              ),
              child: const Text('Select'),
              onPressed: () {
                onColorChanged(pickerColor);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Helper widget to build color picker button
  Widget _buildColorPickerButton(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color> onColorChanged,
    {bool allowTransparent = false}
  ) {
    return InkWell(
      onTap: () => _showColorPicker(
        context, 
        currentColor, 
        onColorChanged,
        allowTransparent: allowTransparent,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B), // Slate 800
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF334155), // Slate 700
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: currentColor == Colors.transparent 
                    ? null
                    : currentColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF94A3B8),
                  width: 2,
                ),
              ),
              child: currentColor == Colors.transparent
                  ? const Icon(
                      LucideIcons.eyeOff,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                currentColor == Colors.transparent 
                    ? 'No background'
                    : 'Tap to pick color',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(
              LucideIcons.palette,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
