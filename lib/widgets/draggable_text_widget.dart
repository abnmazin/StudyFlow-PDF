import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:math_expressions/math_expressions.dart';

class DraggableTextWidget extends StatefulWidget {
  final String commentId;
  final String content;
  final Color color;
  final double fontSize;
  final bool isBold;
  final bool isLatex;
  final String fontFamily;
  final bool showBorder;
  final Color borderColor;
  final Color bgColor;
  final double scale;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragEnd;
  final bool enableDrag;
  final bool isEditing;
  final void Function(String text, PointerDownEvent? event) onEditComplete;

  const DraggableTextWidget({
    super.key,
    required this.commentId,
    required this.content,
    required this.color,
    required this.fontSize,
    required this.isBold,
    required this.isLatex,
    required this.fontFamily,
    required this.showBorder,
    required this.borderColor,
    required this.bgColor,
    required this.scale,
    required this.onTap,
    required this.onDragEnd,
    required this.enableDrag,
    this.isEditing = false,
    required this.onEditComplete,
  });

  @override
  State<DraggableTextWidget> createState() => _DraggableTextWidgetState();
}

class _DraggableTextWidgetState extends State<DraggableTextWidget> {
  Offset _dragOffset = Offset.zero;
  late TextEditingController _textController;
  late FocusNode _focusNode;

  bool _containsArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  TextDirection _plainTextDirection(String text) {
    return _containsArabic(text) ? TextDirection.rtl : TextDirection.ltr;
  }

  String _normalizeFontFamily(String family) {
    // Map legacy/display label to the bundled pubspec family name.
    if (family.trim() == 'Noto Naskh Arabic') {
      return 'NotoNaskhArabic';
    }
    return family;
  }

  bool _isArabicSafeFont(String family) {
    final normalized = _normalizeFontFamily(family).trim().toLowerCase();
    const arabicSafeFamilies = {
      'notonaskharabic',
      'noto sans arabic',
      'amiri',
      'times new roman',
      'segoe ui',
      'tahoma',
      'arial',
    };
    return arabicSafeFamilies.contains(normalized);
  }

  String? _plainTextFontFamily(String text) {
    final selected = _normalizeFontFamily(widget.fontFamily);
    if (_containsArabic(text)) {
      // Arabic must use a shaping-safe family to avoid disconnected letters.
      if (selected.isEmpty) return 'NotoNaskhArabic';
      return _isArabicSafeFont(selected) ? selected : 'NotoNaskhArabic';
    }
    return selected;
  }

  String _prepareDisplayText(String text, {required bool isArabic}) {
    if (!isArabic || text.isEmpty) return text;

    // Bracketed snippets like (6) are safer without wrapping.
    if (RegExp(r'[\(\)\[\]\{\}]').hasMatch(text)) {
      return text;
    }

    // Use Unicode bidi isolates for LTR technical segments in Arabic context.
    const fsi = '\u2068';
    const pdi = '\u2069';
    final latinOrMathSegment = RegExp(
      r'([A-Za-z0-9][A-Za-z0-9\s/\\+\-*=.,:;_%^<>]*)',
    );

    return text.replaceAllMapped(
      latinOrMathSegment,
      (m) => '$fsi${m.group(1)}$pdi',
    );
  }

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content);
    _focusNode = FocusNode();
    // When a brand-new widget is built already in editing mode (e.g. _addTextAt),
    // didUpdateWidget never fires, so we must request focus here.
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _tryAutoSolveLatex(String currentText) {
    if (!widget.isLatex) return;
    if (!currentText.endsWith('=')) return;

    // Extract the equation before the '='
    String rawEquation = currentText.substring(0, currentText.length - 1).trim();

    // Clean LaTeX formatting into a standard math expression using Regex
    String cleanEq = rawEquation;
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\\frac{([^}]+)}{([^}]+)}'), (m) => '(${m[1]})/(${m[2]})');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\times'), '*');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\div'), '/');
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\\sqrt{([^}]+)}'), (m) => 'sqrt(${m[1]})');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\left\('), '(');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\right\)'), ')');
    cleanEq = cleanEq.replaceAll(' ', ''); // remove spaces

    try {
      Parser p = Parser();
      Expression exp = p.parse(cleanEq);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);

      // Format result (remove trailing .0 for integers)
      String resultStr = eval.toString();
      if (resultStr.endsWith('.0')) {
        resultStr = resultStr.substring(0, resultStr.length - 2);
      }

      // Auto-append the result to the controller
      final newText = '$currentText $resultStr';
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    } catch (e) {
      // Not a mathematically solvable equation (e.g., contains variables or text)
      // Do nothing, just leave the '=' there.
      return;
    }
  }

  void _insertAtCursor(String code) {
    final ctrl = _textController;
    final selection = ctrl.selection;

    // إذا لم يكن هناك cursor، أضف للنهاية
    final base = selection.baseOffset < 0
        ? ctrl.text.length
        : selection.baseOffset.clamp(0, ctrl.text.length);
    final extent = selection.extentOffset < 0
        ? ctrl.text.length
        : selection.extentOffset.clamp(0, ctrl.text.length);

    final newText = ctrl.text.replaceRange(base, extent, code);

    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: base + code.length),
    );
  }

  // ✅ هذا هو الإصلاح: تصفير الإزاحة عند تحديث الودجت من الخارج
  @override
  void didUpdateWidget(DraggableTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // KEEP THE EXISTING DRAG OFFSET FIX:
    if (_dragOffset != Offset.zero) {
      _dragOffset = Offset.zero;
    }

    // NEW LOGIC FOR TEXT EDITING:
    if (widget.isEditing && !oldWidget.isEditing) {
      // Transitioning INTO editing mode
      _textController.text = widget.content;
      // Move cursor to end
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
      _focusNode.requestFocus();
    } else if (!widget.isEditing && oldWidget.isEditing) {
      // Transitioning OUT of editing mode — sync read-only display
      _textController.text = widget.content;
    } else if (!widget.isEditing && widget.content != oldWidget.content) {
      // Content updated from outside while not editing
      _textController.text = widget.content;
    }
  }

  @override
  Widget build(BuildContext context) {
    // تحديد لون الخلفية والإطار
    final effectiveBgColor = widget.bgColor;
    final effectiveBorderColor = widget.showBorder
        ? widget.borderColor
        : Colors.transparent;
    final effectiveShowBorder = widget.showBorder;

    // تحديد الـ TextStyle المشترك
    final editingIsArabic = _containsArabic(_textController.text);
    final displayIsArabic = _containsArabic(widget.content);
    final editingDirection = widget.isLatex
        ? TextDirection.ltr
        : _plainTextDirection(_textController.text);
    final displayDirection = widget.isLatex
        ? TextDirection.ltr
        : _plainTextDirection(widget.content);

    final sharedStyle = TextStyle(
      color: widget.color,
      fontSize: widget.fontSize * widget.scale,
      fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
      fontFamilyFallback: const [
        'NotoNaskhArabic',
        'Noto Naskh Arabic',
        'Noto Sans Arabic',
        'Amiri',
        'Segoe UI',
        'Tahoma',
        'Arial',
      ],
    );

    final editingStyle = sharedStyle.copyWith(
      fontFamily: widget.isLatex
          ? widget.fontFamily
          : _plainTextFontFamily(_textController.text),
    );
    final displayStyle = sharedStyle.copyWith(
      fontFamily: widget.isLatex
          ? widget.fontFamily
          : _plainTextFontFamily(widget.content),
    );

    // تجهيز المحتوى (حقل تعديل أو نص عرض)
    Widget contentWidget;

    if (widget.isEditing) {
      // ── وضع التعديل: حقل نص مضمّن مع معاينة حية للـ LaTeX ────────────────────────
      contentWidget = TapRegion(
        groupId: 'text_editing_region',
        onTapOutside: (event) {
          widget.onEditComplete(_textController.text, event);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.isLatex)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _textController,
                builder: (context, value, child) {
                  if (value.text.trim().isEmpty) return const SizedBox.shrink();
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                const Color(0xFF1E293B).withValues(alpha: 0.9),
                                const Color(0xFF0F172A).withValues(alpha: 0.95),
                              ]
                            : [
                                const Color(0xFFF8FAFC),
                                const Color(0xFFFFFFFF),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                          blurRadius: 4,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Math.tex(
                            value.text,
                            textStyle: TextStyle(
                              fontSize: 20,
                              color: isDark
                                  ? const Color(0xFFF1F5F9)
                                  : const Color(0xFF1E293B),
                              fontWeight: FontWeight.w500,
                            ),
                            onErrorFallback: (err) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.alertCircle,
                                  color: Color(0xFFEF4444),
                                  size: 14,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'خطأ في الكود',
                                  style: TextStyle(
                                    color: const Color(0xFFEF4444),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            Directionality(
              textDirection: editingDirection,
              child: IntrinsicWidth(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event.logicalKey == LogicalKeyboardKey.space) {
                      return KeyEventResult.skipRemainingHandlers;
                    }

                    // Keep arrow keys inside the text editor and stop viewer-level
                    // handlers from hijacking navigation.
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                        event.logicalKey == LogicalKeyboardKey.arrowRight ||
                        event.logicalKey == LogicalKeyboardKey.arrowUp ||
                        event.logicalKey == LogicalKeyboardKey.arrowDown ||
                        event.logicalKey == LogicalKeyboardKey.home ||
                        event.logicalKey == LogicalKeyboardKey.end) {
                      return KeyEventResult.skipRemainingHandlers;
                    }

                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    autofocus: true,
                    maxLines: null,
                    minLines: 1,
                    style: editingStyle,
                    textDirection: editingDirection,
                    textAlign: editingDirection == TextDirection.rtl
                        ? TextAlign.right
                        : TextAlign.left,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      _tryAutoSolveLatex(val);
                      // Re-evaluate direction while typing so mixed-language text feels natural.
                      setState(() {});
                    },
                    onSubmitted: (value) {
                      widget.onEditComplete(value, null);
                    },
                  ),
                ),
              ),
            ),
            if (widget.isLatex)
              _MathToolbar(
                onInsert: (code) {
                  _insertAtCursor(code);
                  _focusNode.requestFocus();
                },
              ),
          ],
        ),
      );
    } else if (widget.isLatex) {
      // ── وضع العرض: لاتيكس ────────────────────────────────────────────────
      contentWidget = Directionality(
        textDirection: TextDirection.ltr,
        child: Math.tex(
          widget.content,
          textStyle: sharedStyle.copyWith(fontFamily: widget.fontFamily),
        ),
      );
    } else {
      // ── وضع العرض: نص عادي ───────────────────────────────────────────────
      final displayText = _prepareDisplayText(
        widget.content,
        isArabic: displayIsArabic,
      );

      contentWidget = Directionality(
        textDirection: displayDirection,
        child: Text(
          displayText,
          style: displayStyle,
          textDirection: displayDirection,
          textAlign: displayDirection == TextDirection.rtl
              ? TextAlign.right
              : TextAlign.left,
          locale: displayIsArabic ? const Locale('ar') : null,
          softWrap: true,
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      // التحديث أثناء السحب (Visual Feedback)
      onPanUpdate: widget.enableDrag
          ? (details) {
              setState(() {
                _dragOffset += details.delta;
              });
            }
          : null,
      // عند انتهاء السحب، نرسل القيمة النهائية
      onPanEnd: widget.enableDrag
          ? (details) {
              widget.onDragEnd(_dragOffset);
              // ⚠️ ملاحظة مهمة: لا نصفر _dragOffset هنا يدوياً
              // لأننا نعتمد على didUpdateWidget لتقوم بذلك بعد تحديث الأب
            }
          : null,
      child: Transform.translate(
        offset: _dragOffset,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: effectiveBgColor == Colors.transparent
                ? null
                : effectiveBgColor,
            border: Border.all(
              color: widget.isEditing
                  ? Colors.blue.withOpacity(0.5) // إطار أزرق عند التعديل
                  : (effectiveShowBorder
                        ? effectiveBorderColor
                        : Colors.transparent),
              width: widget.isEditing ? 1.5 : (effectiveShowBorder ? 2 : 0),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: contentWidget,
        ),
      ),
    );
  }
}

class _MathSymbol {
  final String label;
  final String code;
  final String? tooltip;
  const _MathSymbol({required this.label, required this.code, this.tooltip});
}

const _basicSymbols = [
  _MathSymbol(label: 'x/y', code: r'\frac{x}{y}', tooltip: 'كسر'),
  _MathSymbol(label: '√x', code: r'\sqrt{x}', tooltip: 'جذر تربيعي'),
  _MathSymbol(label: 'ⁿ√x', code: r'\sqrt[n]{x}', tooltip: 'جذر n'),
  _MathSymbol(label: '( )', code: r'\left(  \right)', tooltip: 'أقواس'),
  _MathSymbol(label: '∑', code: r'\sum_{i=1}^{n}', tooltip: 'مجموع'),
  _MathSymbol(label: '∞', code: r'\infty', tooltip: 'مالانهاية'),
];

class _MathToolbar extends StatelessWidget {
  final void Function(String code) onInsert;

  const _MathToolbar({required this.onInsert});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final tabBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFCBD5E1);
    final chipBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: tabBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tabBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: _basicSymbols.map((sym) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message: sym.tooltip ?? sym.code,
                child: Material(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onInsert(sym.code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: tabBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Math.tex(
                          sym.label,
                          textStyle: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          onErrorFallback: (_) => Text(
                            sym.label,
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
