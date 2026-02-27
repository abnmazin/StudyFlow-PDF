import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';

/// Which color slot the picker is editing.
enum _ColorTarget { stroke, bg, border }

class StudyFlowRightPanel extends StatelessWidget {
  final bool isSettingsMode;
  final ToolType activeTool;
  final Color activeColor;
  final double strokeWidth;
  final double fontSize;
  final bool isBold;
  final bool isLatex;
  final bool showBorder;
  final Color borderColor;
  final Color bgColor;
  final int activeTabIndex;
  final bool isDarkMode;
  final PdfItem? activePdf;
  final PdfViewerController pdfController;
  final String? selectedHighlightId; // NEW: know if a shape is selected
  final VoidCallback?
  onColorPickerOpening; // NEW: freeze selection before dialog
  final VoidCallback?
  onColorPickerClosed; // NEW: restore selection after dialog
  final ValueChanged<ToolType> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<bool> onBoldChanged;
  final ValueChanged<bool> onLatexChanged;
  final ValueChanged<bool> onShowBorderChanged;
  final ValueChanged<Color> onBorderColorChanged;
  final ValueChanged<Color> onBgColorChanged;
  final ValueChanged<int> onTabChanged;
  final Function(PdfItem) onAddPage;
  final Function(PdfItem) onDeletePage;
  final Function(PdfItem) onPrint;
  final VoidCallback onToggleDarkMode;

  const StudyFlowRightPanel({
    super.key,
    required this.isSettingsMode,
    required this.activeTool,
    required this.activeColor,
    required this.strokeWidth,
    required this.fontSize,
    required this.isBold,
    required this.isLatex,
    required this.showBorder,
    required this.borderColor,
    required this.bgColor,
    required this.activeTabIndex,
    required this.isDarkMode,
    required this.activePdf,
    required this.pdfController,
    this.selectedHighlightId,
    this.onColorPickerOpening,
    this.onColorPickerClosed,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onFontSizeChanged,
    required this.onBoldChanged,
    required this.onLatexChanged,
    required this.onShowBorderChanged,
    required this.onBorderColorChanged,
    required this.onBgColorChanged,
    required this.onTabChanged,
    required this.onAddPage,
    required this.onDeletePage,
    required this.onPrint,
    required this.onToggleDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isGlobalEditing = appProvider.activeEditingCommentId != null;
    final isTextEditing = isGlobalEditing && activeTool == ToolType.text;
    final editingStyles = isGlobalEditing
        ? appProvider.getEditingStyles(appProvider.activeEditingCommentId!)
        : null;

    // Resolve Effective Styles (Editing > Default)
    // We use 'num' for fontSize to strictly handle int/double safety
    final effectiveFontSize =
        (isTextEditing && editingStyles?['fontSize'] != null)
        ? (editingStyles!['fontSize'] as num).toDouble()
        : fontSize;

    // Color is managed per tool below
    final effectiveColor = (isTextEditing && editingStyles?['color'] != null)
        ? Color(editingStyles!['color'])
        : activeColor;

    final effectiveIsBold = (isTextEditing && editingStyles?['isBold'] != null)
        ? (editingStyles!['isBold'] as bool)
        : isBold;

    final effectiveIsLatex =
        (isTextEditing && editingStyles?['isLatex'] != null)
        ? (editingStyles!['isLatex'] as bool)
        : isLatex;

    final effectiveShowBorder =
        (isTextEditing && editingStyles?['showBorder'] != null)
        ? (editingStyles!['showBorder'] as bool)
        : showBorder;

    final effectiveBorderColor =
        (isTextEditing && editingStyles?['borderColor'] != null)
        ? Color(editingStyles!['borderColor'])
        : borderColor;

    final effectiveBgColor =
        (isTextEditing && editingStyles?['bgColor'] != null)
        ? Color(editingStyles!['bgColor'])
        : bgColor;

    final scheme = Theme.of(context).colorScheme;
    final panelBg = isDarkMode ? const Color(0xFF0F172A) : scheme.surface;
    final panelBorder = isDarkMode
        ? const Color(0xFF334155)
        : scheme.outlineVariant;
    final headerBg = isDarkMode ? const Color(0xFF1E293B) : scheme.surface;
    final headerBorder = isDarkMode
        ? const Color(0xFF334155)
        : scheme.outlineVariant;
    final surfaceAlt = isDarkMode
        ? const Color(0xFF1E293B)
        : scheme.surfaceContainerHighest;
    final textPrimary = isDarkMode ? Colors.white : scheme.onSurface;
    final textMuted = isDarkMode
        ? const Color(0xFF94A3B8)
        : scheme.onSurfaceVariant;

    return Container(
      width: 320, // Wider for Chat UI
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(left: BorderSide(color: panelBorder, width: 1.5)),
      ),
      child: isSettingsMode
          ? _buildSettingsView(
              context,
              panelBg,
              panelBorder,
              headerBg,
              headerBorder,
              surfaceAlt,
              textPrimary,
              textMuted,
            )
          : Column(
              children: [
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
                                  color: textMuted,
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
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
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
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildShapeSelectorBtn(
                                    context,
                                    LucideIcons.mousePointer2,
                                    ToolType.cursor,
                                    'Pointer',
                                  ),
                                  _buildShapeSelectorBtn(
                                    context,
                                    LucideIcons.arrowUpRight,
                                    ToolType.arrow,
                                    'Arrow',
                                  ),
                                  _buildShapeSelectorBtn(
                                    context,
                                    LucideIcons.square,
                                    ToolType.rectangle,
                                    'Rectangle',
                                  ),
                                  _buildShapeSelectorBtn(
                                    context,
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
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
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
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 16,
                                          ),
                                      activeTrackColor: const Color(0xFF3B82F6),
                                      inactiveTrackColor: panelBorder,
                                      thumbColor: const Color(0xFF2563EB),
                                    ),
                                    child: Slider(
                                      value: effectiveFontSize,
                                      min: 10.0,
                                      max: 48.0,
                                      onChanged: (val) {
                                        if (isTextEditing) {
                                          final id = appProvider
                                              .activeEditingCommentId;
                                          if (id != null) {
                                            appProvider.updateEditingStyle(
                                              commentId: id,
                                              fontSize: val,
                                            );
                                            return;
                                          }
                                        }
                                        onFontSizeChanged(val);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Bold',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: textMuted,
                                    ),
                                  ),
                                  ExcludeFocus(
                                    child: Switch(
                                      value: effectiveIsBold,
                                      onChanged: (val) {
                                        if (isTextEditing) {
                                          final id = appProvider
                                              .activeEditingCommentId;
                                          if (id != null) {
                                            appProvider.updateEditingStyle(
                                              commentId: id,
                                              isBold: val,
                                            );
                                            return;
                                          }
                                        }
                                        onBoldChanged(val);
                                      },
                                      activeTrackColor: const Color(0xFF3B82F6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // NEW: LaTeX Mode Toggle
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.sigma,
                                        size: 18,
                                        color: textMuted,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'LaTeX Mode',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ExcludeFocus(
                                    child: Switch(
                                      value: effectiveIsLatex,
                                      onChanged: (val) {
                                        if (isTextEditing) {
                                          final id = appProvider
                                              .activeEditingCommentId;
                                          if (id != null) {
                                            appProvider.updateEditingStyle(
                                              commentId: id,
                                              isLatex: val,
                                            );
                                            return;
                                          }
                                        }
                                        onLatexChanged(val);
                                      },
                                      activeTrackColor: const Color(0xFF3B82F6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // ─── Show Border Toggle ───────────────────────────
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.square,
                                        size: 18,
                                        color: textMuted,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Show Border',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ExcludeFocus(
                                    child: Switch(
                                      value: effectiveShowBorder,
                                      onChanged: (val) {
                                        if (isTextEditing) {
                                          final id = appProvider
                                              .activeEditingCommentId;
                                          if (id != null) {
                                            appProvider.updateEditingStyle(
                                              commentId: id,
                                              showBorder: val,
                                            );
                                            return;
                                          }
                                        }
                                        onShowBorderChanged(val);
                                      },
                                      activeTrackColor: const Color(0xFF3B82F6),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // ─── Border Colour Picker (text only, if border ON) ──
                            if (activeTool == ToolType.text &&
                                effectiveShowBorder) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Border Color',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildColorPickerButton(
                                context,
                                effectiveBorderColor,
                                (color) {
                                  if (isTextEditing) {
                                    final id =
                                        appProvider.activeEditingCommentId;
                                    if (id != null) {
                                      appProvider.updateEditingStyle(
                                        commentId: id,
                                        borderColor: color,
                                      );
                                      return;
                                    }
                                  }
                                  onBorderColorChanged(color);
                                },
                                colorTarget: _ColorTarget.border,
                              ),
                            ],

                            // ─── Background Colour (text + rect + circle only) ────
                            if ([
                              ToolType.text,
                              ToolType.rectangle,
                              ToolType.circle,
                            ].contains(activeTool)) ...[
                              const SizedBox(height: 24),
                              Text(
                                activeTool == ToolType.text
                                    ? 'Background Color'
                                    : 'Fill Color',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildColorPickerButton(
                                context,
                                effectiveBgColor,
                                (color) {
                                  if (isTextEditing) {
                                    final id =
                                        appProvider.activeEditingCommentId;
                                    if (id != null) {
                                      appProvider.updateEditingStyle(
                                        commentId: id,
                                        bgColor: color,
                                      );
                                      return;
                                    }
                                  }
                                  onBgColorChanged(color);
                                },
                                allowTransparent: true,
                                colorTarget: _ColorTarget.bg,
                              ),
                              const SizedBox(height: 24),
                            ],

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
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: textMuted,
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
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 16,
                                            ),
                                        activeTrackColor: const Color(
                                          0xFF3B82F6,
                                        ),
                                        inactiveTrackColor: panelBorder,
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
                                activeTool == ToolType.text
                                    ? 'Text Color'
                                    : activeTool == ToolType.highlight
                                    ? 'Highlight Color'
                                    : 'Stroke Color',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildColorPickerButton(
                                context,
                                effectiveColor,
                                (color) {
                                  if (isTextEditing) {
                                    final id =
                                        appProvider.activeEditingCommentId;
                                    if (id != null) {
                                      appProvider.updateEditingStyle(
                                        commentId: id,
                                        color: color,
                                      );
                                      return;
                                    }
                                  }
                                  onColorChanged(color);
                                },
                                colorTarget: _ColorTarget.stroke,
                              ),
                            ] else if (!activeTool.toString().contains(
                                  'cursor',
                                ) &&
                                !activeTool.toString().contains('arrow') &&
                                !activeTool.toString().contains('rectangle') &&
                                !activeTool.toString().contains('circle'))
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 32),
                                  child: Text(
                                    'No properties available\nfor this tool',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: textMuted),
                                  ),
                                ),
                              ),

                            // Bookmarks Section (Preserved)
                            const SizedBox(height: 32),
                            Divider(color: panelBorder),
                            const SizedBox(height: 16),
                            Text(
                              'Bookmarks',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (activePdf != null &&
                                activePdf!.bookmarks.isNotEmpty)
                              ...activePdf!.bookmarks.map((bookmark) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: panelBorder),
                                  ),
                                  color: surfaceAlt,
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
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  'Page ${bookmark.page}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: textMuted,
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
                                    style: TextStyle(color: textMuted),
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

  Widget _buildSettingsView(
    BuildContext context,
    Color panelBg,
    Color panelBorder,
    Color headerBg,
    Color headerBorder,
    Color surfaceAlt,
    Color textPrimary,
    Color textMuted,
  ) {
    return Column(
      children: [
        // --- HEADER ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(bottom: BorderSide(color: headerBorder)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.settings, size: 20, color: textPrimary),
              const SizedBox(width: 8),
              Text(
                'Document Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ),

        // --- CONTENT ---
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activePdf != null) ...[
                  _buildSettingsCard(
                    context,
                    surfaceAlt,
                    panelBorder,
                    textPrimary,
                    textMuted,
                    [
                      _buildSettingsTile(
                        icon: LucideIcons.filePlus,
                        label: 'Add Blank Page',
                        onTap: () => onAddPage(activePdf!),
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                      ),
                      _buildSettingsDivider(panelBorder),
                      _buildSettingsTile(
                        icon: LucideIcons.fileMinus,
                        label: 'Delete Current Page',
                        onTap: () => onDeletePage(activePdf!),
                        isDanger: true,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSettingsCard(
                    context,
                    surfaceAlt,
                    panelBorder,
                    textPrimary,
                    textMuted,
                    [
                      _buildSettingsTile(
                        icon: LucideIcons.printer,
                        label: 'Print Document',
                        onTap: () => onPrint(activePdf!),
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                _buildSettingsCard(
                  context,
                  surfaceAlt,
                  panelBorder,
                  textPrimary,
                  textMuted,
                  [
                    _buildSettingsTile(
                      icon: isDarkMode ? LucideIcons.sun : LucideIcons.moon,
                      label: isDarkMode ? 'Light Mode' : 'Dark Mode',
                      onTap: onToggleDarkMode,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
    List<Widget> children,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: panelBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDanger = false,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final color = isDanger ? const Color(0xFFDC2626) : textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(LucideIcons.chevronRight, size: 16, color: textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsDivider(Color panelBorder) {
    return Divider(height: 1, thickness: 1, color: panelBorder, indent: 48);
  }

  // Helper method for shape selector buttons in right panel
  Widget _buildShapeSelectorBtn(
    BuildContext context,
    IconData icon,
    ToolType toolValue,
    String tooltip,
  ) {
    final isSelected = activeTool == toolValue;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onToolChanged(toolValue),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode
                      ? const Color(0xFF312E81)
                      : scheme.primaryContainer)
                : (isDarkMode
                      ? const Color(0xFF1E293B)
                      : scheme.surfaceContainerHigh),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? (isDarkMode ? const Color(0xFF818CF8) : scheme.primary)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected
                ? (isDarkMode ? const Color(0xFF818CF8) : scheme.primary)
                : (isDarkMode
                      ? const Color(0xFF94A3B8)
                      : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  // Helper method to show color picker dialog
  Future<void> _showColorPicker(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color> onColorChanged, {
    bool allowTransparent = false,
    _ColorTarget colorTarget = _ColorTarget.stroke,
  }) async {
    Color pickerColor = currentColor;
    final scheme = Theme.of(context).colorScheme;
    final dialogBg = isDarkMode ? const Color(0xFF1E293B) : scheme.surface;
    final dialogText = isDarkMode ? Colors.white : scheme.onSurface;
    final neutralBtnBg = isDarkMode
        ? const Color(0xFF64748B)
        : scheme.surfaceContainerHigh;

    // Cache the comment ID BEFORE dialog steals focus
    final appProvider = context.read<AppProvider>();
    appProvider.cacheTargetIdForColor(
      appProvider.activeEditingCommentId ?? selectedHighlightId,
    );

    // Freeze selection before dialog
    onColorPickerOpening?.call();

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: dialogBg,
          title: Text('Pick a Color', style: TextStyle(color: dialogText)),
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
                  enableAlpha: allowTransparent,
                  labelTypes: const [],
                  pickerAreaBorderRadius: const BorderRadius.all(
                    Radius.circular(8),
                  ),
                ),
                if (allowTransparent) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: neutralBtnBg,
                    ),
                    icon: const Icon(LucideIcons.eyeOff, size: 18),
                    label: const Text('No Background (Transparent)'),
                    onPressed: () {
                      onColorChanged(Colors.transparent);
                      switch (colorTarget) {
                        case _ColorTarget.bg:
                          appProvider.applyColorToCachedComment(
                            bgColor: Colors.transparent,
                          );
                        case _ColorTarget.border:
                          appProvider.applyColorToCachedComment(
                            borderColor: Colors.transparent,
                          );
                        case _ColorTarget.stroke:
                          appProvider.applyColorToCachedComment(
                            color: Colors.transparent,
                          );
                      }
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
              ),
              child: Text('Select', style: TextStyle(color: Colors.white)),
              onPressed: () {
                onColorChanged(pickerColor);
                // Apply to cached comment (works even after focus loss)
                switch (colorTarget) {
                  case _ColorTarget.stroke:
                    appProvider.applyColorToCachedComment(color: pickerColor);
                  case _ColorTarget.bg:
                    appProvider.applyColorToCachedComment(bgColor: pickerColor);
                  case _ColorTarget.border:
                    appProvider.applyColorToCachedComment(
                      borderColor: pickerColor,
                    );
                }
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );

    // Restore selection + clear cached id
    onColorPickerClosed?.call();
    appProvider.clearCachedTargetId();
  }

  // Helper widget to build color picker button
  Widget _buildColorPickerButton(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color> onColorChanged, {
    bool allowTransparent = false,
    _ColorTarget colorTarget = _ColorTarget.stroke,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final buttonBg = isDarkMode
        ? const Color(0xFF1E293B)
        : scheme.surfaceContainerHigh;
    final buttonBorder = isDarkMode
        ? const Color(0xFF334155)
        : scheme.outlineVariant;
    final iconMuted = isDarkMode
        ? const Color(0xFF94A3B8)
        : scheme.onSurfaceVariant;
    return InkWell(
      onTap: () => _showColorPicker(
        context,
        currentColor,
        onColorChanged,
        allowTransparent: allowTransparent,
        colorTarget: colorTarget,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: buttonBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: buttonBorder, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: currentColor == Colors.transparent ? null : currentColor,
                shape: BoxShape.circle,
                border: Border.all(color: iconMuted, width: 2),
              ),
              child: currentColor == Colors.transparent
                  ? Icon(LucideIcons.eyeOff, size: 16, color: iconMuted)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                currentColor == Colors.transparent
                    ? 'No background'
                    : 'Tap to pick color',
                style: TextStyle(color: iconMuted, fontSize: 14),
              ),
            ),
            Icon(LucideIcons.palette, color: iconMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
