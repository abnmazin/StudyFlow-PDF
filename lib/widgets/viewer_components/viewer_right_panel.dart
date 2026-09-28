import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../services/sync_service.dart';
import '../../services/mcp_client_service.dart';
import '../../utils/responsive_utils.dart';
import '../mini_apps_menu.dart';
import 'session_cards.dart';
import 'tool_width_limits.dart';
import '../../models/isar_models.dart' hide PdfDocument;

/// Which color slot the picker is editing.
enum _ColorTarget { stroke, bg, border }

const String _aiConversationKeyPrefix = 'ai_chat_conversation_';
final ValueNotifier<int> _aiConversationRevision = ValueNotifier<int>(0);

class StudyFlowRightPanel extends StatelessWidget {
  final bool isSettingsMode;
  final ToolType activeTool;
  final Color activeColor;
  final double strokeWidth;
  final double fontSize;
  final String fontFamily;
  final List<String> fontOptions;
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
  final ValueChanged<String> onFontFamilyChanged;
  final ValueChanged<bool> onBoldChanged;
  final ValueChanged<bool> onLatexChanged;
  final ValueChanged<bool> onShowBorderChanged;
  final ValueChanged<Color> onBorderColorChanged;
  final ValueChanged<Color> onBgColorChanged;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<bool>? onAiChatHoverChanged;
  final Function(PdfItem) onAddPage;
  final Function(PdfItem) onDeletePage;
  final Function(PdfItem) onPrint;
  final VoidCallback onToggleDarkMode;

  /// Drives the slide. The panel stays mounted while closed so the AI chat
  /// keeps its history between openings; only the width animates.
  final bool isOpen;

  const StudyFlowRightPanel({
    super.key,
    required this.isOpen,
    required this.isSettingsMode,
    required this.activeTool,
    required this.activeColor,
    required this.strokeWidth,
    required this.fontSize,
    required this.fontFamily,
    required this.fontOptions,
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
    required this.onFontFamilyChanged,
    required this.onBoldChanged,
    required this.onLatexChanged,
    required this.onShowBorderChanged,
    required this.onBorderColorChanged,
    required this.onBgColorChanged,
    required this.onTabChanged,
    this.onAiChatHoverChanged,
    required this.onAddPage,
    required this.onDeletePage,
    required this.onPrint,
    required this.onToggleDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullWidth = ResponsiveBreakpoints.rightPanelWidth(
      MediaQuery.sizeOf(context).width,
    );
    final edgeBorder = isDarkMode
        ? const Color(0xFF334155)
        : scheme.outlineVariant;

    return ClipRect(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        // Animating the width is what makes the sibling rail drift instead of
        // blinking, and the panel is revealed from the right edge rather than
        // jumping into place.
        width: isOpen ? fullWidth : 0,
        decoration: BoxDecoration(
          // On the animating edge, so the border is drawn for the whole
          // animation and not only once the panel has reached full width.
          border: Border(left: BorderSide(color: edgeBorder, width: 1.5)),
        ),
        child: IgnorePointer(
          // Keeps the collapsed panel from swallowing taps meant for the
          // viewer underneath it.
          ignoring: !isOpen,
          child: OverflowBox(
            alignment: Alignment.centerRight,
            minWidth: fullWidth,
            maxWidth: fullWidth,
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isGlobalEditing = appProvider.activeEditingCommentId != null;
    final isTextEditing = isGlobalEditing && activeTool == ToolType.text;
    final editingStyles = isGlobalEditing
        ? appProvider.getEditingStyles(appProvider.activeEditingCommentId!)
        : null;

    // Resolve Effective Styles (Editing > Default)
    // We use 'num' for fontSize to strictly handle int/double safety
    final effectiveFontSize =
        ((isTextEditing && editingStyles?['fontSize'] != null)
                ? (editingStyles!['fontSize'] as num).toDouble()
                : fontSize)
            .clamp(10.0, 48.0);

    final effectiveFontFamily =
        (isTextEditing && editingStyles?['fontFamily'] != null)
        ? (editingStyles!['fontFamily'] as String)
        : fontFamily;

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

    if (!isSettingsMode && activeTool == ToolType.cursor) {
      return TextFieldTapRegion(
        child: Container(
          decoration: BoxDecoration(
            color: panelBg,
            border: Border(left: BorderSide(color: panelBorder, width: 1.5)),
          ),
          child: _CursorUtilitiesHub(
            isDarkMode: isDarkMode,
            panelBg: panelBg,
            panelBorder: panelBorder,
            surfaceAlt: surfaceAlt,
            textPrimary: textPrimary,
            textMuted: textMuted,
            activePdf: activePdf,
            pdfController: pdfController,
            onAiChatHoverChanged: onAiChatHoverChanged,
            settingsTab: _buildSettingsTabContent(
              context,
              surfaceAlt,
              panelBorder,
              textPrimary,
              textMuted,
            ),
          ),
        ),
      );
    }

    return TextFieldTapRegion(
      child: Container(
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
                                    activeTool == ToolType.cursor
                                        ? LucideIcons.hand
                                        : [
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
                                    activeTool == ToolType.cursor
                                        ? 'تحريك (تمرير)'
                                        : [
                                            ToolType.arrow,
                                            ToolType.rectangle,
                                            ToolType.circle,
                                          ].contains(activeTool)
                                        ? 'أشكال'
                                        : 'إعدادات ${_toolNameAr(activeTool)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // SHAPE SELECTOR
                              if ([
                                ToolType.arrow,
                                ToolType.rectangle,
                                ToolType.circle,
                              ].contains(activeTool)) ...[
                                Text(
                                  'نوع الأداة',
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
                                      LucideIcons.arrowUpRight,
                                      ToolType.arrow,
                                      'سهم',
                                    ),
                                    _buildShapeSelectorBtn(
                                      context,
                                      LucideIcons.square,
                                      ToolType.rectangle,
                                      'مستطيل',
                                    ),
                                    _buildShapeSelectorBtn(
                                      context,
                                      LucideIcons.circle,
                                      ToolType.circle,
                                      'دائرة',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Text Tool Properties (Preserved)
                              if (activeTool == ToolType.text) ...[
                                Text(
                                  'نوع الخط',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value:
                                      fontOptions.contains(effectiveFontFamily)
                                      ? effectiveFontFamily
                                      : fontOptions.first,
                                  isExpanded: true,
                                  dropdownColor: surfaceAlt,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: panelBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: panelBorder,
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(10),
                                      ),
                                      borderSide: BorderSide(
                                        color: Color(0xFF3B82F6),
                                      ),
                                    ),
                                  ),
                                  items: fontOptions
                                      .map(
                                        (font) => DropdownMenuItem<String>(
                                          value: font,
                                          child: Text(
                                            font,
                                            style: TextStyle(
                                              fontFamily: font,
                                              color: textPrimary,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    if (_applyTextStyleToSelection(
                                      context,
                                      fontFamily: value,
                                    ))
                                      return;
                                    onFontFamilyChanged(value);
                                  },
                                ),
                                const SizedBox(height: 24),

                                Text(
                                  'حجم الخط',
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
                                        value: effectiveFontSize,
                                        min: 10.0,
                                        max: 48.0,
                                        onChanged: (val) {
                                          if (_applyTextStyleToSelection(
                                            context,
                                            fontSize: val,
                                          ))
                                            return;
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
                                      'عريض',
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
                                          if (_applyTextStyleToSelection(
                                            context,
                                            isBold: val,
                                          ))
                                            return;
                                          onBoldChanged(val);
                                        },
                                        activeTrackColor: const Color(
                                          0xFF3B82F6,
                                        ),
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
                                          'وضع LaTeX',
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
                                          if (_applyTextStyleToSelection(
                                            context,
                                            isLatex: val,
                                          ))
                                            return;
                                          onLatexChanged(val);
                                        },
                                        activeTrackColor: const Color(
                                          0xFF3B82F6,
                                        ),
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
                                          'إظهار الحدود',
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
                                          if (_applyTextStyleToSelection(
                                            context,
                                            showBorder: val,
                                          ))
                                            return;
                                          onShowBorderChanged(val);
                                        },
                                        activeTrackColor: const Color(
                                          0xFF3B82F6,
                                        ),
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
                                  'لون الحدود',
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
                                    if (_applyTextStyleToSelection(
                                      context,
                                      borderColor: color,
                                    ))
                                      return;
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
                                      ? 'لون الخلفية'
                                      : 'لون التعبئة',
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
                                    if (_applyTextStyleToSelection(
                                      context,
                                      bgColor: color,
                                    ))
                                      return;
                                    onBgColorChanged(color);
                                  },
                                  allowTransparent: true,
                                  colorTarget: _ColorTarget.bg,
                                ),
                                const SizedBox(height: 24),
                              ],

                              if (activeTool == ToolType.eraser) ...[
                                Text(
                                  'تنظيف المستند',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: surfaceAlt,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: panelBorder),
                                  ),
                                  child: Column(
                                    children: [
                                      _buildSettingsTile(
                                        icon: LucideIcons.highlighter,
                                        label: 'مسح كل التظليل',
                                        onTap: () {
                                          if (activePdf == null) return;
                                          _showBulkCleanupDialog(
                                            context,
                                            title: 'مسح كل التظليل؟',
                                            message:
                                                'سيتم حذف كل عناصر الهايلايت في هذا المستند نهائيًا.',
                                            successMessage:
                                                'تم مسح كل التظليل.',
                                            onConfirm: () => context
                                                .read<AppProvider>()
                                                .clearAllHighlightsOnly(
                                                  activePdf!.id,
                                                ),
                                          );
                                        },
                                        isDanger: true,
                                        textPrimary: textPrimary,
                                        textMuted: textMuted,
                                      ),
                                      _buildSettingsDivider(panelBorder),
                                      _buildSettingsTile(
                                        icon: LucideIcons.penTool,
                                        label: 'مسح كل الرسم',
                                        onTap: () {
                                          if (activePdf == null) return;
                                          _showBulkCleanupDialog(
                                            context,
                                            title: 'مسح كل الرسم؟',
                                            message:
                                                'سيتم حذف كل الرسومات (قلم، سهم، مستطيل، دائرة) نهائيًا.',
                                            successMessage: 'تم مسح كل الرسم.',
                                            onConfirm: () => context
                                                .read<AppProvider>()
                                                .clearAllDrawingsOnly(
                                                  activePdf!.id,
                                                ),
                                          );
                                        },
                                        isDanger: true,
                                        textPrimary: textPrimary,
                                        textMuted: textMuted,
                                      ),
                                      _buildSettingsDivider(panelBorder),
                                      _buildSettingsTile(
                                        icon: LucideIcons.bookmark,
                                        label: 'مسح كل المرجعيات',
                                        onTap: () {
                                          if (activePdf == null) return;
                                          _showBulkCleanupDialog(
                                            context,
                                            title: 'مسح كل المرجعيات؟',
                                            message:
                                                'سيتم حذف كل العلامات المرجعية في هذا المستند نهائيًا.',
                                            successMessage:
                                                'تم مسح كل المرجعيات.',
                                            onConfirm: () => context
                                                .read<AppProvider>()
                                                .clearAllBookmarks(
                                                  activePdf!.id,
                                                ),
                                          );
                                        },
                                        isDanger: true,
                                        textPrimary: textPrimary,
                                        textMuted: textMuted,
                                      ),
                                      _buildSettingsDivider(panelBorder),
                                      _buildSettingsTile(
                                        icon: LucideIcons.messageSquare,
                                        label: 'مسح كل الملاحظات',
                                        onTap: () {
                                          if (activePdf == null) return;
                                          _showBulkCleanupDialog(
                                            context,
                                            title: 'مسح كل الملاحظات؟',
                                            message:
                                                'سيتم حذف كل الملاحظات النصية في هذا المستند نهائيًا.',
                                            successMessage:
                                                'تم مسح كل الملاحظات.',
                                            onConfirm: () => context
                                                .read<AppProvider>()
                                                .clearAllComments(
                                                  activePdf!.id,
                                                ),
                                          );
                                        },
                                        isDanger: true,
                                        textPrimary: textPrimary,
                                        textMuted: textMuted,
                                      ),
                                    ],
                                  ),
                                ),
                                if (activePdf != null)
                                  _buildFileTrashSection(
                                    context.read<AppProvider>(),
                                    activePdf!,
                                    surfaceAlt,
                                    panelBorder,
                                    textPrimary,
                                    textMuted,
                                  ),
                                const SizedBox(height: 16),
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
                                    'سماكة الحد',
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
                                          thumbShape:
                                              const RoundSliderThumbShape(
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
                                          // The panel used to cap every tool
                                          // at 20 without clamping, so a
                                          // highlighter the rail had widened to
                                          // 30 asserted here and took the whole
                                          // screen down.
                                          value: ToolWidthLimits.clampFor(
                                            activeTool,
                                            strokeWidth,
                                          ),
                                          min: ToolWidthLimits.min,
                                          max: ToolWidthLimits.maxFor(
                                            activeTool,
                                          ),
                                          divisions:
                                              ToolWidthLimits.divisionsFor(
                                                activeTool,
                                              ),
                                          onChanged: onStrokeWidthChanged,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                Text(
                                  activeTool == ToolType.text
                                      ? 'لون النص'
                                      : activeTool == ToolType.highlight
                                      ? 'لون الهايلايت'
                                      : 'لون الحد',
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
                                    if (_applyTextStyleToSelection(
                                      context,
                                      color: color,
                                    ))
                                      return;
                                    onColorChanged(color);
                                  },
                                  colorTarget: _ColorTarget.stroke,
                                ),
                              ] else if (activeTool != ToolType.eraser &&
                                  !activeTool.toString().contains('cursor') &&
                                  !activeTool.toString().contains('arrow') &&
                                  !activeTool.toString().contains(
                                    'rectangle',
                                  ) &&
                                  !activeTool.toString().contains('circle'))
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 32),
                                    child: Text(
                                      'لا توجد إعدادات متاحة\nلهذه الأداة',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: textMuted),
                                    ),
                                  ),
                                ),

                              if (activeTool == ToolType.cursor) ...[
                                // Bookmarks Section (Hand tool only)
                                const SizedBox(height: 32),
                                Divider(color: panelBorder),
                                const SizedBox(height: 16),
                                Text(
                                  'العلامات المرجعية',
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
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: textPrimary,
                                                      ),
                                                    ),
                                                    Text(
                                                      'الصفحة ${bookmark.page}',
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
                                                tooltip: 'حذف العلامة المرجعية',
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
                                        'لا توجد علامات مرجعية بعد',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: textMuted),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  bool _applyTextStyleToSelection(
    BuildContext context, {
    Color? color,
    double? fontSize,
    bool? isBold,
    bool? isLatex,
    String? fontFamily,
    bool? showBorder,
    Color? borderColor,
    Color? bgColor,
  }) {
    if (activeTool != ToolType.text) return false;

    final app = context.read<AppProvider>();
    final targetId = app.activeEditingCommentId ?? app.lastEditedCommentId;
    if (targetId == null) return false;

    return app.applyTextStyleToTarget(
      commentId: targetId,
      color: color,
      fontSize: fontSize,
      isBold: isBold,
      isLatex: isLatex,
      fontFamily: fontFamily,
      showBorder: showBorder,
      borderColor: borderColor,
      bgColor: bgColor,
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
                'إعدادات المستند',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildSettingsTabContent(
            context,
            surfaceAlt,
            panelBorder,
            textPrimary,
            textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTabContent(
    BuildContext context,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    final app = context.watch<AppProvider>();

    return SingleChildScrollView(
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
                  label: 'إضافة صفحة فارغة',
                  onTap: () => onAddPage(activePdf!),
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                _buildSettingsDivider(panelBorder),
                _buildSettingsTile(
                  icon: LucideIcons.fileMinus,
                  label: 'حذف الصفحة الحالية',
                  onTap: () => onDeletePage(activePdf!),
                  isDanger: true,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                _buildSettingsDivider(panelBorder),
                _buildSettingsTile(
                  icon: LucideIcons.printer,
                  label: 'طباعة المستند',
                  onTap: () => onPrint(activePdf!),
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                _buildSettingsDivider(panelBorder),
                _buildSettingsTile(
                  icon: LucideIcons.bot,
                  label: 'تصفير سجل AI لهذا الملف',
                  onTap: () {
                    if (activePdf == null) return;
                    _showBulkCleanupDialog(
                      context,
                      title: 'تصفير سجل AI؟',
                      message:
                          'سيتم حذف محادثة الذكاء الاصطناعي الخاصة بهذا الملف وإرجاع الرسالة الافتراضية.',
                      successMessage: 'تم تصفير سجل AI لهذا الملف.',
                      onConfirm: () =>
                          _clearAiConversationForPdf(activePdf!.id),
                    );
                  },
                  isDanger: true,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _buildSessionCard(
            context,
            app,
            surfaceAlt,
            panelBorder,
            textPrimary,
            textMuted,
          ),
        ],
      ),
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
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
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

  Future<void> _showBulkCleanupDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String successMessage,
    required VoidCallback onConfirm,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final dialogBg = isDarkMode ? const Color(0xFF1E293B) : scheme.surface;
    final dialogText = isDarkMode ? Colors.white : scheme.onSurface;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: dialogBg,
          title: Text(title, style: TextStyle(color: dialogText)),
          content: Text(message, style: TextStyle(color: dialogText)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (shouldClear == true && context.mounted) {
      onConfirm();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearAiConversationForPdf(String pdfId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_aiConversationKeyPrefix$pdfId');
    _aiConversationRevision.value++;
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
    final shouldApplyCommentStyle = activeTool == ToolType.text;

    // Cache the comment ID BEFORE dialog steals focus
    final appProvider = context.read<AppProvider>();
    if (shouldApplyCommentStyle) {
      appProvider.cacheTargetIdForColor(
        appProvider.activeEditingCommentId ?? selectedHighlightId,
      );
    }

    // Freeze selection before dialog
    onColorPickerOpening?.call();

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: dialogBg,
          title: Text('اختر لونًا', style: TextStyle(color: dialogText)),
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
                    label: const Text('بدون خلفية (شفاف)'),
                    onPressed: () {
                      onColorChanged(Colors.transparent);
                      if (shouldApplyCommentStyle) {
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
                        // Directly update the cached comment/highlight via AppProvider
                        appProvider.applyColorToCachedComment(
                          color: colorTarget == _ColorTarget.stroke
                              ? Colors.transparent
                              : null,
                          bgColor: colorTarget == _ColorTarget.bg
                              ? Colors.transparent
                              : null,
                          borderColor: colorTarget == _ColorTarget.border
                              ? Colors.transparent
                              : null,
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
              child: const Text('إلغاء'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
              ),
              child: Text('اختيار', style: TextStyle(color: Colors.white)),
              onPressed: () {
                onColorChanged(pickerColor);
                if (shouldApplyCommentStyle) {
                  // Apply to cached comment (works even after focus loss)
                  switch (colorTarget) {
                    case _ColorTarget.stroke:
                      appProvider.applyColorToCachedComment(color: pickerColor);
                    case _ColorTarget.bg:
                      appProvider.applyColorToCachedComment(
                        bgColor: pickerColor,
                      );
                    case _ColorTarget.border:
                      appProvider.applyColorToCachedComment(
                        borderColor: pickerColor,
                      );
                  }
                }
                onColorChanged(pickerColor); // Update local state
                if (shouldApplyCommentStyle) {
                  appProvider.applyColorToCachedComment(
                    // Update cached comment/highlight
                    color: colorTarget == _ColorTarget.stroke
                        ? pickerColor
                        : null,
                    bgColor: colorTarget == _ColorTarget.bg
                        ? pickerColor
                        : null,
                    borderColor: colorTarget == _ColorTarget.border
                        ? pickerColor
                        : null,
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
    if (shouldApplyCommentStyle) {
      appProvider.clearCachedTargetId();
    }
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
                    ? 'بدون خلفية'
                    : 'اضغط لاختيار اللون',
                style: TextStyle(color: iconMuted, fontSize: 14),
              ),
            ),
            Icon(LucideIcons.palette, color: iconMuted, size: 20),
          ],
        ),
      ),
    );
  }

  String _toolNameAr(ToolType tool) {
    switch (tool) {
      case ToolType.cursor:
        return 'التحريك';
      case ToolType.select:
        return 'التحديد';
      case ToolType.arrow:
        return 'السهم';
      case ToolType.rectangle:
        return 'المستطيل';
      case ToolType.circle:
        return 'الدائرة';
      case ToolType.highlight:
        return 'الهايلايت';
      case ToolType.pen:
        return 'القلم';
      case ToolType.text:
        return 'النص';
      case ToolType.eraser:
        return 'الممحاة';
    }
  }

  // ──────────────────────────────────────────────────────────────
  // SESSION MANAGEMENT CARD
  // ──────────────────────────────────────────────────────────────

  Widget _buildSessionCard(
    BuildContext context,
    AppProvider app,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    final role = app.currentUser?.role ?? 'member';
    final isPrivileged = app.currentUser?.isLecturer ?? false;

    return Container(
      decoration: BoxDecoration(
        color: surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: panelBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.radio, size: 18, color: textPrimary),
              const SizedBox(width: 8),
              Text(
                'المزامنة / Sync',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (app.currentUser == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(LucideIcons.userX, size: 24, color: textMuted),
                    const SizedBox(height: 8),
                    Text(
                      "يرجى تسجيل الدخول أولاً",
                      style: TextStyle(color: textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (isPrivileged) ...[
            LecturerSessionCard(
              app: app,
              surfaceAlt: surfaceAlt,
              panelBorder: panelBorder,
              textPrimary: textPrimary,
              textMuted: textMuted,
              syncService: SyncService(),
            ),
            if (app.currentSessionCode == null) ...[
              const SizedBox(height: 16),
              Divider(color: panelBorder),
              const SizedBox(height: 16),
              Text(
                'أو الانضمام كعضو:',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              MemberSessionCard(
                app: app,
                surfaceAlt: surfaceAlt,
                panelBorder: panelBorder,
                textPrimary: textPrimary,
                textMuted: textMuted,
                syncService: SyncService(),
              ),
            ],
          ] else
            MemberSessionCard(
              app: app,
              surfaceAlt: surfaceAlt,
              panelBorder: panelBorder,
              textPrimary: textPrimary,
              textMuted: textMuted,
              syncService: SyncService(),
            ),
        ],
      ),
    );
  }

  Widget _buildFileTrashSection(
    AppProvider app,
    PdfItem activePdf,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    return FutureBuilder<List<DeletedAnnotation>>(
      future: app.fileManager.getDeletedAnnotations(),
      builder: (context, snapshot) {
        final allItems = snapshot.data ?? [];
        final items = allItems.where((i) => i.pdfId == activePdf.id).toList();

        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(LucideIcons.trash2, size: 14, color: textMuted),
                const SizedBox(width: 8),
                Text(
                  'المحذوفات مؤخراً (هذا الملف)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: panelBorder),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(color: panelBorder, height: 1),
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final isOwner = app.currentUser?.isLecturer ?? false;
                  final isCreator = item.deletedBy == app.currentUser?.username;

                  // Restore button logic
                  final bool canRestore = (app.currentSessionCode != null)
                      ? isOwner
                      : (isOwner || isCreator);

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: Icon(
                      _getIconForItemType(item.itemType),
                      size: 16,
                      color: textMuted,
                    ),
                    title: Text(
                      _getLabelForItemType(item.itemType),
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'الصفحة ${item.pageNumber} • ${item.deletedBy}',
                      style: TextStyle(color: textMuted, fontSize: 11),
                    ),
                    trailing: canRestore
                        ? IconButton(
                            onPressed: () async {
                              await app.restoreAnnotation(item);
                            },
                            icon: const Icon(LucideIcons.undo2, size: 16),
                            tooltip: 'استعادة',
                            color: Theme.of(context).primaryColor,
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _getIconForItemType(String type) {
    switch (type) {
      case 'comment':
        return LucideIcons.messageSquare;
      case 'math':
        return LucideIcons.sigma;
      case 'drawing':
        return LucideIcons.penTool;
      default:
        return LucideIcons.highlighter;
    }
  }

  String _getLabelForItemType(String type) {
    switch (type) {
      case 'comment':
        return 'ملاحظة نصية';
      case 'math':
        return 'معادلة رياضيّة';
      case 'drawing':
        return 'رسم / شكل';
      default:
        return 'تظليل نص';
    }
  }
}

class _CursorUtilitiesHub extends StatefulWidget {
  final bool isDarkMode;
  final Color panelBg;
  final Color panelBorder;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textMuted;
  final PdfItem? activePdf;
  final PdfViewerController pdfController;
  final ValueChanged<bool>? onAiChatHoverChanged;
  final Widget settingsTab;

  const _CursorUtilitiesHub({
    required this.isDarkMode,
    required this.panelBg,
    required this.panelBorder,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.activePdf,
    required this.pdfController,
    required this.settingsTab,
    this.onAiChatHoverChanged,
  });

  @override
  State<_CursorUtilitiesHub> createState() => _CursorUtilitiesHubState();
}

class _CursorUtilitiesHubState extends State<_CursorUtilitiesHub> {
  @override
  Widget build(BuildContext context) {
    final indicatorColor = const Color(0xFF3B82F6);
    final tabBg = widget.isDarkMode
        ? const Color(0xFF111827)
        : const Color(0xFFE2E8F0);

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: tabBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.panelBorder),
            ),
            child: TabBar(
              indicator: BoxDecoration(
                color: indicatorColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: indicatorColor.withValues(alpha: 0.45),
                ),
              ),
              labelColor: indicatorColor,
              unselectedLabelColor: widget.textMuted,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(
                  icon: Tooltip(
                    message: 'ذكاء اصطناعي',
                    child: Icon(LucideIcons.bot, size: 20),
                  ),
                ),
                Tab(
                  icon: Tooltip(
                    message: 'التطبيقات المصغرة',
                    child: Icon(Icons.grid_view_outlined, size: 20),
                  ),
                ),
                Tab(
                  icon: Tooltip(
                    message: 'صفحات مرجعية',
                    child: Icon(LucideIcons.bookmark, size: 20),
                  ),
                ),
                Tab(
                  icon: Tooltip(
                    message: 'الإعدادات',
                    child: Icon(LucideIcons.settings, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // AI Tab
                MouseRegion(
                  onEnter: (_) => widget.onAiChatHoverChanged?.call(true),
                  onExit: (_) => widget.onAiChatHoverChanged?.call(false),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _AiChatWidget(
                      isDarkMode: widget.isDarkMode,
                      pdfId: widget.activePdf?.id,
                      pdfController: widget.pdfController,
                    ),
                  ),
                ),

                // Mini Apps Tab
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: const MiniAppsTabWidget(),
                ),

                // Bookmarks Tab
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: widget.activePdf != null
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.activePdf!.bookmarks.isNotEmpty)
                                ...widget.activePdf!.bookmarks.map((bookmark) {
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: widget.panelBorder,
                                      ),
                                    ),
                                    color: widget.surfaceAlt,
                                    child: InkWell(
                                      onTap: () {
                                        if (widget.pdfController.isReady) {
                                          widget.pdfController.goToPage(
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
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: widget.textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    'الصفحة ${bookmark.page}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: widget.textMuted,
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
                                                      widget.activePdf!.id,
                                                      bookmark.id,
                                                    );
                                              },
                                              tooltip: 'حذف العلامة المرجعية',
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
                                    padding: const EdgeInsets.only(top: 32),
                                    child: Text(
                                      'لا توجد علامات مرجعية بعد\n\nاستخدم Ctrl+S لإضافة علامة مرجعية',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: widget.textMuted,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Center(
                          child: Text(
                            'لا يوجد مستند مفتوح',
                            style: TextStyle(
                              color: widget.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                ),
                // Settings Tab
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: widget.settingsTab,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  final Color color;
  const _AnimatedDots({required this.color});

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // كل نقطة تتأخر بـ 200ms عن السابقة
            final delay = i * 0.25;
            final t = (_ctrl.value - delay).clamp(0.0, 1.0);
            // curve: صعود وهبوط
            final scale = 0.5 + 0.5 * math.sin(t * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.4 + 0.6 * scale),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _AiChatWidget extends StatefulWidget {
  final bool isDarkMode;
  final String? pdfId;
  final PdfViewerController? pdfController;

  const _AiChatWidget({
    required this.isDarkMode,
    this.pdfId,
    this.pdfController,
  });

  @override
  State<_AiChatWidget> createState() => _AiChatWidgetState();
}

class _AiChatWidgetState extends State<_AiChatWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'content':
          'مرحباً بك! أنا مساعدك الذكي في StudyFlow PDF. كيف يمكنني مساعدتك في فهم هذه الملزمة؟',
    },
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();
  bool _isLoading = false;
  bool _wasAtBottom = true;

  void _trackScrollPosition() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _wasAtBottom = (pos.maxScrollExtent - pos.pixels) < 60.0;
  }

  void _onConversationRevisionChanged() {
    _loadConversationForCurrentPdf();
  }

  String get _conversationKey =>
      '$_aiConversationKeyPrefix${widget.pdfId ?? '__global__'}';

  List<Map<String, String>> _defaultMessages() => [
    {
      'role': 'ai',
      'content':
          'مرحباً بك! أنا مساعدك الذكي في StudyFlow PDF. كيف يمكنني مساعدتك في فهم هذه الملزمة؟',
    },
  ];

  @override
  void initState() {
    super.initState();
    _aiConversationRevision.addListener(_onConversationRevisionChanged);
    _scrollController.addListener(_trackScrollPosition);
    _chatFocusNode.addListener(() {
      if (mounted) {
        context.read<AppProvider>().setKeyboardLock(_chatFocusNode.hasFocus);
      }
    });
    _loadConversationForCurrentPdf();
  }

  @override
  void didUpdateWidget(covariant _AiChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfId != widget.pdfId) {
      _loadConversationForCurrentPdf();
    }
  }

  Future<void> _loadConversationForCurrentPdf() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationKey);
    if (!mounted) return;

    if (raw == null || raw.isEmpty) {
      setState(() {
        _messages
          ..clear()
          ..addAll(_defaultMessages());
      });
      _scrollToBottom(jump: true);
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = decoded
          .whereType<Map>()
          .map(
            (e) => {
              'role': (e['role'] ?? 'ai').toString(),
              'content': (e['content'] ?? '').toString(),
            },
          )
          .toList();

      setState(() {
        _messages
          ..clear()
          ..addAll(restored.isEmpty ? _defaultMessages() : restored);
      });
      _scrollToBottom(jump: true);
    } catch (_) {
      setState(() {
        _messages
          ..clear()
          ..addAll(_defaultMessages());
      });
    }
  }

  Future<void> _saveConversationForCurrentPdf() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_conversationKey, jsonEncode(_messages));
  }

  Future<String> _getActivePageText() async {
    final controller = widget.pdfController;
    if (controller == null) return "لا يوجد نص متاح حالياً.";

    try {
      if (!controller.isReady) {
        return "المستند غير جاهز بعد لاستخراج النص. حاول بعد ثوانٍ.";
      }

      final doc = controller.document;
      final pages = doc.pages;
      if (pages.isEmpty) {
        return "لا توجد صفحات متاحة حالياً.";
      }

      final pageNumber = controller.pageNumber ?? 1;
      if (pageNumber < 1 || pageNumber > pages.length) {
        return "هذه الصفحة غير صالحة للسياق.";
      }

      final page = pages[pageNumber - 1];
      final text = await page.loadText();
      final content = text?.fullText.trim() ?? "";
      return content.isNotEmpty
          ? content
          : "هذه الصفحة لا تحتوي على نص قابل للقراءة.";
    } catch (e) {
      debugPrint('Error extracting page text: $e');
      return "تعذر استخراج النص من الصفحة الحالية.";
    }
  }

  String _buildSystemPrompt(String pageText) {
    const personaInstruction =
        "أنت مساعد دراسي، تتحدث باللهجة العراقية الجنوبية الأصيلة والدافئة.\n"
        "قاعدة التخاطب الصارمة: في بداية إجابتك، اختر عبارة ترحيب ومودة **واحدة فقط** (مثل: 'شوف مولاي'، 'تاج راسي'، 'يا ضلعي'، أو 'فدوة لعمرك') واستخدمها **مرة واحدة فقط** في أول سطر. يُمنع منعاً باتاً استخدام أكثر من عبارة ترحيب في نفس الرد، ويُمنع تكرارها بين الفقرات.\n"
        "قاعدة الاختصار: أجب على السؤال بشكل مباشر، علمي، ومختصر. أعطِ الخلاصة والزبدة فوراً. يُمنع تكرار نفس الفكرة بصيغ متعددة (لا تكن ثرثاراً).\n"
        "إذا كان السؤال بديهياً جداً، عاتبه بمزاح عراقي لطيف مرة واحدة فقط (مثال: 'يا مولاي معقولة مهندسنا يسأل هيج سؤال؟ بس تتدلل...') ثم اشرح باختصار شديد.";

    const strictMathInstruction =
        "قاعدة الرياضيات الصارمة — اتبعها حرفياً:\n"
        "1. المعادلات الكاملة في سطر منفصل: \$\$equation\$\$\n"
        "2. المتغيرات والرموز داخل الجملة: \$symbol\$ (مثال: حيث \$NF_i\$ هو معامل الضوضاء)\n"
        "3. يُمنع منعاً باتاً وضع متغير رياضي على سطر وحده منفصل عن نصه\n"
        "4. يُمنع وضع سطر فارغ قبل أو بعد المتغير داخل الجملة\n"
        "5. مثال صحيح: 'حيث \$G_i\$ هو كسب الطاقة للمرحلة \$i\$'\n"
        "6. مثال خاطئ:\n"
        "   'حيث\n"
        "   \$G_i\$\n"
        "   هو كسب الطاقة'\n"
        "7. يُمنع استخدام [ ] أو \\( \\) للمعادلات";

    return "$personaInstruction\n\n"
        "$strictMathInstruction\n\n"
        "أجب بأسلوب علمي دقيق، عراقي الروح، ومختصر جداً (بدون حشو أو تكرار فقرات).\n"
        "السياق الحالي لـ 'مولاي' من الصفحة المفتوحة في الملزمة هو:\n\n$pageText";
  }

  // 2. دالة تنظيف وتصحيح اللاتكس — تصلح المتغيرات اليتيمة
  String formatChatResponseForLaTeX(String text) {
    // Step 1: normalize \[ \] and \( \) to $$ and $
    String result = text
        .replaceAll(r'\[', r'$$')
        .replaceAll(r'\]', r'$$')
        .replaceAll(r'\(', r'$')
        .replaceAll(r'\)', r'$');

    // Step 2: fix orphaned inline variables — when $var$ is alone on its
    // own line surrounded by text lines, merge it with adjacent lines.
    // Pattern: text_line \n $var$ \n text_line → text_line $var$ text_line
    result = result.replaceAllMapped(
      RegExp(r'([^\n\$]+)\n(\$[^\$\n]+?\$)\n([^\n\$]+)', multiLine: true),
      (m) => '${m[1]} ${m[2]} ${m[3]}',
    );

    // Step 3: fix orphaned variable at start of line followed by text
    // Pattern: \n$var$\n text → $var$ text
    result = result.replaceAllMapped(
      RegExp(r'\n(\$[^\$\n]+?\$)\n([^\n\$])', multiLine: true),
      (m) => ' ${m[1]} ${m[2]}',
    );

    // Step 4: fix orphaned variable at end — text\n$var$\n
    result = result.replaceAllMapped(
      RegExp(r'([^\n\$])\n(\$[^\$\n]+?\$)\n', multiLine: true),
      (m) => '${m[1]} ${m[2]}\n',
    );

    return result;
  }

  Future<String> _generateGeminiReply(String prompt, String modelName) async {
    final app = context.read<AppProvider>();
    final settingsKey = app.geminiApiKey.trim();
    final envKey = (dotenv.env['GEMINI_API_KEY'] ?? '').trim();
    final usingSettingsKey = settingsKey.isNotEmpty;
    final apiKey = usingSettingsKey ? settingsKey : envKey;
    debugPrint(
      '[AI] Gemini key source: ${usingSettingsKey ? 'settings' : 'env'} (provider=${app.aiProvider})',
    );
    if (apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY missing in settings/.env');
    }

    // 1. Get Context
    final pageText = await _getActivePageText();
    final systemPrompt = _buildSystemPrompt(pageText);

    // 2. Sliding Window (Last 8 messages)
    final history = _messages.length > 8
        ? _messages.sublist(_messages.length - 8)
        : _messages;

    // 3. Construct Payload for Gemini
    // We'll prepend the system prompt as a user message or inside the prompt itself
    // because Gemini GenerativeModel.generateContent often expects a single prompt or part of a list.
    // For simplicity and effectiveness, we wrap it in a single prompt string for now.
    String fullPrompt = "Instructions:\n$systemPrompt\n\nHistory:\n";
    for (var msg in history) {
      fullPrompt +=
          "${msg['role'] == 'user' ? 'User' : 'AI'}: ${msg['content']}\n";
    }
    fullPrompt += "User: $prompt\nAI:";

    final model = GenerativeModel(model: modelName, apiKey: apiKey);
    final response = await model.generateContent([Content.text(fullPrompt)]);
    final aiText = (response.text ?? '').trim();
    return aiText.isEmpty ? 'لم أتمكن من توليد إجابة.' : aiText;
  }

  Future<String> _generateGroqReply(String prompt, String modelName) async {
    final app = context.read<AppProvider>();
    final settingsKey = app.groqApiKey.trim();
    final envKey = (dotenv.env['GROQ_API_KEY'] ?? '').trim();
    final usingSettingsKey = settingsKey.isNotEmpty;
    final apiKey = usingSettingsKey ? settingsKey : envKey;
    debugPrint(
      '[AI] Groq key source: ${usingSettingsKey ? 'settings' : 'env'} (provider=${app.aiProvider})',
    );

    if (apiKey.isEmpty) {
      throw Exception('GROQ_API_KEY missing in settings/.env');
    }

    // 1. Get Context
    final pageText = await _getActivePageText();
    final systemPrompt = _buildSystemPrompt(pageText);

    // 2. Sliding Window (Last 8 messages)
    final history = _messages.length > 8
        ? _messages.sublist(_messages.length - 8)
        : _messages;

    // 3. Construct Messages Array for Groq (OpenAI Compatible)
    final apiMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...history.map(
        (m) => {
          'role': m['role'] == 'ai' ? 'assistant' : m['role'],
          'content': m['content'],
        },
      ),
      {'role': 'user', 'content': prompt},
    ];

    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': modelName,
            'messages': apiMessages,
            'temperature': 0.3,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Groq HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Groq empty response');
    }

    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?;
    final content = (message?['content'] ?? '').toString().trim();
    return content.isEmpty ? 'لم أتمكن من توليد إجابة.' : content;
  }

  Future<String> _generateMcpReply(String prompt) async {
    if (!await McpClientService.instance.isNodeAvailable) {
      throw const McpException('MCP_UNAVAILABLE', 'Node.js is not installed.');
    }
    final pageText = await _getActivePageText();
    final systemPrompt = _buildSystemPrompt(pageText);

    final history = _messages.length > 8
        ? _messages.sublist(_messages.length - 8)
        : _messages;
    final historyBlock = history
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'User'}: ${m['content']}')
        .join('\n');

    final fullPrompt = [
      'Instructions:',
      systemPrompt,
      '',
      'History:',
      historyBlock,
      '',
      'User: $prompt',
      'AI:',
    ].join('\n');

    final answer = await McpClientService.instance.askQuestion(fullPrompt);
    return answer.isEmpty ? 'لم أتمكن من توليد إجابة.' : answer;
  }

  Future<String> _generateAiReply(String prompt) async {
    final app = context.read<AppProvider>();
    app.resetFallbackAttempts();

    while (true) {
      final provider = app.aiProvider;
      final model = provider == 'gemini'
          ? app.geminiModel
          : provider == 'mcp'
          ? app.mcpModel
          : app.groqModel;

      try {
        if (provider == 'gemini') {
          return await _generateGeminiReply(prompt, model);
        } else if (provider == 'mcp') {
          return await _generateMcpReply(prompt);
        } else {
          return await _generateGroqReply(prompt, model);
        }
      } catch (e) {
        debugPrint('[AI Chat] Failed with $provider ($model): $e');
        final canRetry = app.triggerAiFallback();
        if (!canRetry) {
          // Re-throw so _sendMessage shows the error bubble
          rethrow;
        }
        debugPrint(
          '[AI Chat] Retrying with ${app.aiProvider} (${app.currentModel})…',
        );
        // Small delay so Settings UI has time to reflect the switch
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_trackScrollPosition);
    _aiConversationRevision.removeListener(_onConversationRevisionChanged);
    _chatFocusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        if (jump) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  Future<void> _sendMessage([String? quickText]) async {
    if (_isLoading) return;
    final text = (quickText ?? _controller.text).trim();
    if (text.isEmpty) return;
    final provider = context.read<AppProvider>().aiProvider;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    _saveConversationForCurrentPdf();
    _controller.clear();
    _scrollToBottom();

    try {
      final aiText = await _generateAiReply(text);

      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'ai',
          'content': aiText.isEmpty ? 'لم أتمكن من توليد إجابة.' : aiText,
        });
        _isLoading = false;
      });
      _saveConversationForCurrentPdf();
      _scrollToBottom();
    } catch (e, st) {
      if (!mounted) return;
      final errorText = e.toString();
      debugPrint('[AI] Request failed in _sendMessage');
      debugPrint('[AI] Error: $errorText');
      debugPrint('[AI] StackTrace:\n$st');

      final isAuthIssue =
          errorText.contains('API key not valid') ||
          errorText.contains('PERMISSION_DENIED') ||
          errorText.contains('API_KEY_INVALID') ||
          errorText.contains('401') ||
          errorText.contains('403');

      final isQuotaIssue =
          errorText.contains('429') ||
          errorText.contains('quota') ||
          errorText.contains('RESOURCE_EXHAUSTED') ||
          errorText.contains('limit: 0') ||
          errorText.contains('billing');

      final isModelIssue =
          errorText.contains('not found') ||
          errorText.contains('not supported') ||
          errorText.contains('404');

      final isMcpUnavailable =
          errorText.contains('MCP_UNAVAILABLE') ||
          errorText.contains('MCP_DIED') ||
          errorText.contains('MCP_TIMEOUT');

      final isMcpAuthIssue = errorText.contains('MCP_NOT_AUTHENTICATED');

      setState(() {
        _messages.add({
          'role': 'ai',
          'content': isMcpAuthIssue
              ? 'لم يتم تسجيل الدخول إلى حساب Gemini الشخصي. افتح الإعدادات واضغط "ربط حساب Google" لإعادة الربط.'
              : isMcpUnavailable
              ? 'مزود MCP غير متاح. تأكد من تثبيت Node.js أو أعد المحاولة لاحقاً.'
              : isAuthIssue
              ? (provider == 'groq'
                    ? 'فشل التحقق من مفتاح Groq. تأكد أن المفتاح صحيح.'
                    : 'فشل التحقق من مفتاح Gemini. تأكد أن المفتاح صحيح ومفعّل على مشروع Google AI Studio.')
              : isQuotaIssue
              ? 'تم تجاوز حد الطلبات (Quota). جرب لاحقاً أو راجع حدود الاستخدام في حسابك.'
              : isModelIssue
              ? 'الموديل غير متاح حالياً لهذا المزود. اختر موديل آخر من الإعدادات.'
              : 'تعذر الاتصال بمزود الذكاء (${provider.toUpperCase()}). السبب: $errorText',
        });
        _isLoading = false;
      });
      _saveConversationForCurrentPdf();
      _scrollToBottom();
    }
  }

  Widget _buildChatBubble(Map<String, String> message) {
    final role = message['role'] ?? 'ai';
    final content = formatChatResponseForLaTeX(message['content'] ?? '');
    final isUser = role == 'user';

    final userColor = const Color(0xFF3B82F6);
    final aiBubbleColor = widget.isDarkMode
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final textColor = isUser
        ? Colors.white
        : (widget.isDarkMode ? Colors.white : const Color(0xFF0F172A));

    const bubbleMaxWidth = 272.0;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: bubbleMaxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? userColor : aiBubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: widget.isDarkMode ? 0.2 : 0.06,
            ),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: MarkdownBody(
          data: content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: textColor, fontSize: 14, height: 1.35),
            pPadding: EdgeInsets.zero,
            blockSpacing: 6,
            listBullet: TextStyle(color: textColor, fontSize: 14),
            listBulletPadding: const EdgeInsets.only(right: 4),
            code: TextStyle(
              color: widget.isDarkMode
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFF1E293B),
              backgroundColor: widget.isDarkMode
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
              fontFamily: 'monospace',
            ),
            codeblockDecoration: BoxDecoration(
              color: widget.isDarkMode
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          builders: {
            'math_block': LatexElementBuilder(
              textStyle: TextStyle(color: textColor, fontSize: 14),
              maxWidth: bubbleMaxWidth - 24,
            ),
            'math_inline': LatexElementBuilder(
              textStyle: TextStyle(color: textColor, fontSize: 14),
              maxWidth: bubbleMaxWidth - 24,
            ),
          },
          extensionSet:
              md.ExtensionSet(md.ExtensionSet.gitHubFlavored.blockSyntaxes, [
                md.EmojiSyntax(),
                LatexInlineSyntax(),
                ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
              ]),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.bot,
                size: 14,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final bg = widget.isDarkMode
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    const dotColor = Color(0xFF3B82F6);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.bot, size: 14, color: dotColor),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(0),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: const RepaintBoundary(child: _AnimatedDots(color: dotColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final scheme = Theme.of(context).colorScheme;
    final panelBg = widget.isDarkMode
        ? const Color(0xFF0B1220)
        : scheme.surfaceContainerLowest;
    final panelBorder = widget.isDarkMode
        ? const Color(0xFF334155)
        : scheme.outlineVariant;
    final inputBg = widget.isDarkMode
        ? const Color(0xFF111827)
        : scheme.surface;
    final hintColor = widget.isDarkMode
        ? const Color(0xFF94A3B8)
        : scheme.onSurfaceVariant;
    final inputTextColor = widget.isDarkMode
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);

    return Container(
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (_wasAtBottom) _scrollToBottom(jump: true);
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isLoading && index == _messages.length) {
                    return _buildTypingIndicator();
                  }
                  return _buildChatBubble(_messages[index]);
                },
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: panelBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _chatFocusNode,
                    enabled: !_isLoading,
                    style: TextStyle(color: inputTextColor, fontSize: 14),
                    cursorColor: inputTextColor,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'اسأل عن أي شيء في الملزمة...',
                      hintStyle: TextStyle(color: hintColor, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
                IconButton(
                  tooltip: 'إرسال',
                  onPressed: _isLoading ? null : _sendMessage,
                  icon: const Icon(
                    LucideIcons.send,
                    size: 18,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// CUSTOM LATEX RENDERERS FOR MARKDOWN
// ──────────────────────────────────────────────────────────────

class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax()
    : super(r'(\$\$[\s\S]+?\$\$|\$[\s\S]+?\$)', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match[1]!;
    if (text.startsWith(r'$$') && text.endsWith(r'$$')) {
      final math = text.substring(2, text.length - 2);
      parser.addNode(md.Element.text('math_block', math));
    } else {
      final math = text.substring(1, text.length - 1);
      parser.addNode(md.Element.text('math_inline', math));
    }
    return true;
  }
}

class _ScrollableMath extends StatefulWidget {
  final String formula;
  final double fontSize;
  final bool isBlock;
  final Color? textColor;

  const _ScrollableMath({
    required this.formula,
    required this.fontSize,
    this.isBlock = false,
    this.textColor,
  });

  @override
  State<_ScrollableMath> createState() => _ScrollableMathState();
}

class _ScrollableMathState extends State<_ScrollableMath> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mathWidget = Math.tex(
      widget.formula,
      textStyle: TextStyle(fontSize: widget.fontSize, color: widget.textColor),
      mathStyle: widget.isBlock ? MathStyle.display : MathStyle.text,
      onErrorFallback: (e) => SelectableText(
        widget.formula,
        style: TextStyle(
          fontSize: widget.fontSize,
          color: widget.textColor,
          fontFamily: 'monospace',
        ),
      ),
    );

    return Scrollbar(
      controller: _scrollController,
      thickness: 4,
      radius: const Radius.circular(3),
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: mathWidget,
            ),
          ),
        ),
      ),
    );
  }
}

class LatexElementBuilder extends MarkdownElementBuilder {
  final TextStyle? textStyle;
  final double maxWidth;

  LatexElementBuilder({this.textStyle, required this.maxWidth});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent.trim();
    if (element.tag == 'math_block') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: maxWidth,
          child: ClipRect(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: _ScrollableMath(
                formula: text,
                fontSize: 16,
                isBlock: true,
                textColor: textStyle?.color,
              ),
            ),
          ),
        ),
      );
    } else {
      // inline math — لا نضعها في SizedBox حتى لا تصير block
      return Directionality(
        textDirection: TextDirection.ltr,
        child: _ScrollableMath(
          formula: text,
          fontSize: textStyle?.fontSize ?? 14,
          textColor: textStyle?.color,
        ),
      );
    }
  }
}
