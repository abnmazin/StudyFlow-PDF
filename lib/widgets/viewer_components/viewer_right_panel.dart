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
import '../../models/models.dart';
import '../../providers/app_state.dart';
import 'mini_calculator_widget.dart';

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
          width: 320,
          decoration: BoxDecoration(
            color: panelBg,
            border: Border(left: BorderSide(color: panelBorder, width: 1.5)),
          ),
          child: _buildCursorUtilitiesHub(
            context,
            panelBg,
            panelBorder,
            surfaceAlt,
            textPrimary,
            textMuted,
          ),
        ),
      );
    }

    return TextFieldTapRegion(
      child: Container(
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
                                    if (isTextEditing) {
                                      final id =
                                          appProvider.activeEditingCommentId;
                                      if (id != null) {
                                        appProvider.updateEditingStyle(
                                          commentId: id,
                                          fontFamily: value,
                                        );
                                        return;
                                      }
                                    }
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
                                            successMessage:
                                                'تم تصفير سجل AI لهذا الملف.',
                                            onConfirm: () =>
                                                _clearAiConversationForPdf(
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
    final app = context.watch<AppProvider>();
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
                        icon: LucideIcons.trash2,
                        label: 'حذف جميع التعليقات والتظليلات',
                        onTap: () =>
                            _showClearAllAnnotationsDialog(context, activePdf!),
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
                        label: 'طباعة المستند',
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
                      label: isDarkMode ? 'الوضع الفاتح' : 'الوضع الداكن',
                      onTap: onToggleDarkMode,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildAiSettingsCard(
                  context,
                  app,
                  surfaceAlt,
                  panelBorder,
                  textPrimary,
                  textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiSettingsCard(
    BuildContext context,
    AppProvider app,
    Color surfaceAlt,
    Color panelBorder,
    Color textPrimary,
    Color textMuted,
  ) {
    final isDark = app.isDarkMode;
    const geminiModels = ['gemini-2.5-flash', 'gemini-2.0-flash'];
    const groqModels = [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'mixtral-8x7b-32768',
    ];

    final providerItems = const [
      DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
      DropdownMenuItem(value: 'groq', child: Text('Groq')),
    ];

    final modelItems = (app.aiProvider == 'groq' ? groqModels : geminiModels)
        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
        .toList();

    final selectedModel = app.aiProvider == 'groq'
        ? app.groqModel
        : app.geminiModel;
    final inputFill = isDark ? const Color(0xFF0B1220) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFCBD5E1);

    InputDecoration _decoration(String label) {
      return InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: inputFill,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: Color(0xFF3B82F6), width: 1.4),
        ),
      );
    }

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
              Icon(LucideIcons.bot, size: 18, color: textPrimary),
              const SizedBox(width: 8),
              Text(
                'إعدادات الذكاء الاصطناعي',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: app.aiProvider,
            dropdownColor: inputFill,
            style: TextStyle(color: textPrimary, fontSize: 13),
            decoration: _decoration('مزود الذكاء'),
            items: providerItems,
            onChanged: (value) {
              if (value != null) {
                app.setAiProvider(value);
              }
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: selectedModel,
            dropdownColor: inputFill,
            style: TextStyle(color: textPrimary, fontSize: 13),
            decoration: _decoration('النموذج'),
            items: modelItems,
            onChanged: (value) {
              if (value == null) return;
              if (app.aiProvider == 'groq') {
                app.setGroqModel(value);
              } else {
                app.setGeminiModel(value);
              }
            },
          ),
          if (app.aiProvider == 'gemini') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    app.geminiApiKey.isEmpty
                        ? 'Gemini API key غير مضبوط'
                        : 'Gemini API key مضبوط',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAiKeyDialog(
                    context: context,
                    title: 'Gemini API Key',
                    initialValue: app.geminiApiKey,
                    hint: 'AIza...',
                    onSave: app.setGeminiApiKey,
                  ),
                  icon: const Icon(LucideIcons.keyRound, size: 14),
                  label: const Text('تعديل المفتاح'),
                ),
              ],
            ),
          ],
          if (app.aiProvider == 'groq') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    app.groqApiKey.isEmpty
                        ? 'Groq API key غير مضبوط'
                        : 'Groq API key مضبوط',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAiKeyDialog(
                    context: context,
                    title: 'Groq API Key',
                    initialValue: app.groqApiKey,
                    hint: 'gsk_...',
                    onSave: app.setGroqApiKey,
                  ),
                  icon: const Icon(LucideIcons.keyRound, size: 14),
                  label: const Text('تعديل المفتاح'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAiKeyDialog({
    required BuildContext context,
    required String title,
    required String initialValue,
    required String hint,
    required ValueChanged<String> onSave,
  }) async {
    final app = context.read<AppProvider>();
    final isDark = app.isDarkMode;
    final controller = TextEditingController(text: initialValue);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final border = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFCBD5E1);
        return AlertDialog(
          backgroundColor: bg,
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: isDark ? const Color(0xFF0B1220) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                onSave(controller.text);
                Navigator.of(ctx).pop();
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCursorUtilitiesHub(
    BuildContext context,
    Color panelBg,
    Color panelBorder,
    Color surfaceAlt,
    Color textPrimary,
    Color textMuted,
  ) {
    final indicatorColor = const Color(0xFF3B82F6);
    final tabBg = isDarkMode
        ? const Color(0xFF111827)
        : const Color(0xFFE2E8F0);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: tabBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: panelBorder),
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
              unselectedLabelColor: textMuted,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(
                  icon: Icon(LucideIcons.bookmark, size: 16),
                  text: 'المرجعيات',
                ),
                Tab(
                  icon: Icon(LucideIcons.calculator, size: 16),
                  text: 'حاسبة',
                ),
                Tab(
                  icon: Icon(LucideIcons.bot, size: 16),
                  text: 'الذكاء الذكي',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Bookmarks Tab
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: activePdf != null
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (activePdf!.bookmarks.isNotEmpty)
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
                                    padding: const EdgeInsets.only(top: 32),
                                    child: Text(
                                      'لا توجد علامات مرجعية بعد\n\nاستخدم Ctrl+S لإضافة علامة مرجعية',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: textMuted,
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
                            style: TextStyle(color: textMuted, fontSize: 14),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: const MiniCalculatorWidget(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _AiChatWidget(
                    isDarkMode: isDarkMode,
                    pdfId: activePdf?.id,
                  ),
                ),
              ],
            ),
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

  Future<void> _showClearAllAnnotationsDialog(
    BuildContext context,
    PdfItem pdf,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final dialogBg = isDarkMode ? const Color(0xFF1E293B) : scheme.surface;
    final dialogText = isDarkMode ? Colors.white : scheme.onSurface;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: dialogBg,
          title: Text(
            'حذف جميع التعليقات؟',
            style: TextStyle(color: dialogText),
          ),
          content: Text(
            'سيتم حذف كل الهايلايت والرسومات والملاحظات النصية في هذا المستند نهائيًا.',
            style: TextStyle(color: dialogText),
          ),
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
              child: const Text(
                'حذف الكل',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (shouldClear == true && context.mounted) {
      context.read<AppProvider>().clearAllAnnotations(pdf.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف جميع التعليقات.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                onColorChanged(pickerColor); // Update local state
                appProvider.applyColorToCachedComment(
                  // Update cached comment/highlight
                  color: colorTarget == _ColorTarget.stroke
                      ? pickerColor
                      : null,
                  bgColor: colorTarget == _ColorTarget.bg ? pickerColor : null,
                  borderColor: colorTarget == _ColorTarget.border
                      ? pickerColor
                      : null,
                );
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
      default:
        return 'الأداة';
    }
  }
}

class _AiChatWidget extends StatefulWidget {
  final bool isDarkMode;
  final String? pdfId;

  const _AiChatWidget({required this.isDarkMode, this.pdfId});

  @override
  State<_AiChatWidget> createState() => _AiChatWidgetState();
}

class _AiChatWidgetState extends State<_AiChatWidget> {
  static const List<String> _geminiModels = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];
  static const List<String> _groqModels = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
  ];

  final List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'content':
          'مرحباً بك! أنا مساعدك الذكي في StudyFlow. كيف يمكنني مساعدتك في فهم هذه الملزمة؟',
    },
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  void _onConversationRevisionChanged() {
    _loadConversationForCurrentPdf();
  }

  String get _conversationKey =>
      '$_aiConversationKeyPrefix${widget.pdfId ?? '__global__'}';

  List<Map<String, String>> _defaultMessages() => [
    {
      'role': 'ai',
      'content':
          'مرحباً بك! أنا مساعدك الذكي في StudyFlow. كيف يمكنني مساعدتك في فهم هذه الملزمة؟',
    },
  ];

  @override
  void initState() {
    super.initState();
    _aiConversationRevision.addListener(_onConversationRevisionChanged);
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
      _scrollToBottom();
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
      _scrollToBottom();
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

  Future<String> _generateGeminiReply(String prompt, String modelName) async {
    final app = context.read<AppProvider>();
    final apiKey = app.geminiApiKey.isNotEmpty
        ? app.geminiApiKey
        : (dotenv.env['GEMINI_API_KEY'] ?? '');
    if (apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY missing in .env');
    }
    final model = GenerativeModel(model: modelName, apiKey: apiKey);
    final response = await model.generateContent([Content.text(prompt)]);
    final aiText = (response.text ?? '').trim();
    return aiText.isEmpty ? 'لم أتمكن من توليد إجابة.' : aiText;
  }

  Future<String> _generateGroqReply(String prompt, String modelName) async {
    final app = context.read<AppProvider>();
    final apiKey = app.groqApiKey.isNotEmpty
        ? app.groqApiKey
        : (dotenv.env['GROQ_API_KEY'] ?? '');

    if (apiKey.isEmpty) {
      throw Exception('GROQ_API_KEY missing in settings/.env');
    }

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
            'messages': [
              {
                'role': 'system',
                'content': 'You are a helpful study assistant for PDF notes.',
              },
              {'role': 'user', 'content': prompt},
            ],
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

  Future<String> _generateAiReply(String prompt) async {
    final app = context.read<AppProvider>();

    if (app.aiProvider == 'groq') {
      final model = _groqModels.contains(app.groqModel)
          ? app.groqModel
          : _groqModels.first;
      return _generateGroqReply(prompt, model);
    }

    final preferredModel = _geminiModels.contains(app.geminiModel)
        ? app.geminiModel
        : _geminiModels.first;
    final fallbacks = [
      preferredModel,
      ..._geminiModels.where((m) => m != preferredModel),
    ];

    Object? lastError;
    for (final modelName in fallbacks) {
      try {
        return await _generateGeminiReply(prompt, modelName);
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError?.toString() ?? 'Unknown Gemini API error');
  }

  @override
  void dispose() {
    _aiConversationRevision.removeListener(_onConversationRevisionChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
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

      setState(() {
        _messages.add({
          'role': 'ai',
          'content': isAuthIssue
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
    final content = message['content'] ?? '';
    final isUser = role == 'user';

    final userColor = const Color(0xFF3B82F6);
    final aiBubbleColor = widget.isDarkMode
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final textColor = isUser
        ? Colors.white
        : (widget.isDarkMode ? Colors.white : const Color(0xFF0F172A));

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? userColor : aiBubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isUser ? 14 : 0),
          bottomRight: Radius.circular(isUser ? 0 : 14),
        ),
      ),
      child: Text(
        content,
        style: TextStyle(color: textColor, fontSize: 14, height: 1.35),
        textDirection: TextDirection.rtl,
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
              margin: const EdgeInsets.only(right: 6, bottom: 2),
              padding: const EdgeInsets.all(6),
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
          ],
          bubble,
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final bg = widget.isDarkMode
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 6, bottom: 2),
            padding: const EdgeInsets.all(6),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(0),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
