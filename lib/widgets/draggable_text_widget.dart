import 'dart:ui';
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
  final VoidCallback? onIncreaseSize;
  final VoidCallback? onDecreaseSize;
  final VoidCallback? onToggleBorder;
  final VoidCallback? onToggleLatex;

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
    this.onIncreaseSize,
    this.onDecreaseSize,
    this.onToggleBorder,
    this.onToggleLatex,
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
        if (mounted) {
          _focusNode.requestFocus();
          if (widget.isLatex) _showOverlay();
        }
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _tryAutoSolveLatex(String currentText) {
    if (!widget.isLatex) return;
    if (!currentText.endsWith('=')) return;

    // Extract the equation before the '='
    String rawEquation = currentText
        .substring(0, currentText.length - 1)
        .trim();

    // Clean LaTeX formatting into a standard math expression using Regex
    String cleanEq = rawEquation;

    // 1. تحويل الأقواس الخاصة باللاتكس
    cleanEq = cleanEq.replaceAll(RegExp(r'\\left\('), '(');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\right\)'), ')');

    // 2. معالجة الأسس للتخلص من الأقواس المعكوفة {} قبل الوصول للكسور
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\^\{([^}]+)\}'), (m) => '^(${m[1]})');
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'_\{([^}]+)\}'), (m) => '_(${m[1]})');

    // 3. معالجة الجذور والكسور
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\\sqrt{([^}]+)}'), (m) => 'sqrt(${m[1]})');
    cleanEq = cleanEq.replaceAllMapped(RegExp(r'\\frac{([^}]+)}{([^}]+)}'), (m) => '(${m[1]})/(${m[2]})');

    // 4. العمليات الأساسية
    cleanEq = cleanEq.replaceAll(RegExp(r'\\times'), '*');
    cleanEq = cleanEq.replaceAll(RegExp(r'\\div'), '/');
    
    cleanEq = cleanEq.replaceAll(' ', ''); // remove spaces

    try {
      Parser p = Parser();
      Expression exp = p.parse(cleanEq);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);

      String resultStr;
      
      // تقريب الأرقام الكبيرة جداً أو الصغيرة جداً إلى صيغة علمية احترافية
      if (eval.abs() >= 100000 || (eval.abs() < 0.001 && eval != 0)) {
        String expStr = eval.toStringAsExponential(4); // e.g., "3.1250e9"
        expStr = expStr.replaceAll(RegExp(r'0+e'), 'e'); // remove trailing zeros in base
        expStr = expStr.replaceAll(RegExp(r'\.e'), 'e'); // clean dangling dot
        
        List<String> parts = expStr.split('e');
        if (parts.length == 2) {
          String base = parts[0];
          String exponent = parts[1];
          if (exponent.startsWith('+')) exponent = exponent.substring(1);
          resultStr = '$base \\times 10^{$exponent}';
        } else {
          resultStr = expStr;
        }
      } else {
        // الأرقام العادية: نحدد 4 مراتب عشرية كحد أقصى ثم نزيل الأصفار الزائدة
        resultStr = eval.toStringAsFixed(4);
        resultStr = resultStr.replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
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

  void _insertAtCursor(String code, {int? cursorOffset}) {
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

    final finalOffset = cursorOffset != null 
        ? base + cursorOffset 
        : base + code.length;

    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: finalOffset),
    );
  }

  OverlayEntry? _overlayEntry;

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _MathOverlayWidget(
          textController: _textController,
          onInsert: (code, [cursorOffset]) {
            _insertAtCursor(code, cursorOffset: cursorOffset);
            _focusNode.requestFocus();
          },
          onIncreaseSize: widget.onIncreaseSize,
          onDecreaseSize: widget.onDecreaseSize,
          onToggleBorder: widget.onToggleBorder,
          onToggleLatex: widget.onToggleLatex,
          showBorder: widget.showBorder,
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_textController.text != widget.content) {
          _textController.text = widget.content;
        }
        // Move cursor to end
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        _focusNode.requestFocus();
        if (widget.isLatex) {
          _showOverlay();
        }
      });
    } else if (!widget.isEditing && oldWidget.isEditing) {
      // Transitioning OUT of editing mode — sync read-only display
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _removeOverlay();
        if (_textController.text != widget.content) {
          _textController.text = widget.content;
        }
      });
    } else if (!widget.isEditing && widget.content != oldWidget.content) {
      // Content updated from outside while not editing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_textController.text != widget.content) {
          _textController.text = widget.content;
        }
      });
    }

    if (widget.isEditing && oldWidget.isEditing) {
      if (widget.isLatex && !oldWidget.isLatex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showOverlay();
        });
      } else if (!widget.isLatex && oldWidget.isLatex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _removeOverlay();
        });
      } else if (widget.isLatex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _overlayEntry?.markNeedsBuild();
        });
      }
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

    // تجهيز قلب المحتوى (حقل تعديل أو نص عرض)
    Widget coreContent;

    if (widget.isEditing) {
      // ── وضع التعديل: حقل نص مضمّن ──────────────────────────────────────
      coreContent = Directionality(
        textDirection: editingDirection,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: IntrinsicWidth(
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
      );
    } else if (widget.isLatex) {
      // ── وضع العرض: لاتيكس ────────────────────────────────────────────────
      coreContent = Directionality(
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

      coreContent = Directionality(
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

    // تغليف المحتوى الأساسي بالمربع ذو الحدود والخلفية
    final isDarkContext = Theme.of(context).brightness == Brightness.dark;

    Widget boxedContent = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: widget.isEditing
            ? (isDarkContext
                  ? const Color.fromARGB(255, 255, 255, 255).withOpacity(0.9)
                  : Colors.white.withOpacity(0.9))
            : (effectiveBgColor == Colors.transparent
                  ? null
                  : effectiveBgColor),
        border: Border.all(
          color: widget.isEditing
              ? Colors.blue.withOpacity(0.5) // إطار أزرق عند التعديل
              : (effectiveShowBorder
                    ? effectiveBorderColor
                    : Colors.transparent),
          width: widget.isEditing ? 1.5 : (effectiveShowBorder ? 2 : 0),
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: widget.isEditing
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkContext ? 0.3 : 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: coreContent,
    );

    // إضافة الكبسولات والأدوات حول المربع عند التعديل
    Widget finalContent = boxedContent;

    if (widget.isEditing) {
      finalContent = TapRegion(
        groupId: 'text_editing_region',
        onTapOutside: (event) {
          widget.onEditComplete(_textController.text, event);
        },
        child: boxedContent,
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
      child: Transform.translate(offset: _dragOffset, child: finalContent),
    );
  }
}

class _MathOverlayWidget extends StatelessWidget {
  final TextEditingController textController;
  final void Function(String code, [int? cursorOffset]) onInsert;
  final VoidCallback? onIncreaseSize;
  final VoidCallback? onDecreaseSize;
  final VoidCallback? onToggleBorder;
  final VoidCallback? onToggleLatex;
  final bool showBorder;

  const _MathOverlayWidget({
    required this.textController,
    required this.onInsert,
    this.onIncreaseSize,
    this.onDecreaseSize,
    this.onToggleBorder,
    this.onToggleLatex,
    required this.showBorder,
  });

  Widget _buildMathButton(BuildContext context, String tooltip, String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      left: 16,
      right: 16,
      child: SafeArea(
        child: TapRegion(
          groupId: 'text_editing_region',
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                    maxHeight: 220, // HARD CAP — prevents vertical explosion no matter what Math.tex does
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ─── 1. LIVE PREVIEW AREA (Top Section) ───
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: textController,
                        builder: (context, value, child) {
                          if (value.text.trim().isEmpty) return const SizedBox.shrink();
                          return Container(
                            constraints: const BoxConstraints(
                              minWidth: 150,
                              maxHeight: 80, // 🛡️ Absolute vertical cap. No explosions allowed.
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                                ),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: FittedBox( // 🪄 Prevents infinite constraint crashes & scales down long equations
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Math.tex(
                                  value.text,
                                  textStyle: TextStyle(
                                    fontSize: 28,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  onErrorFallback: (err) => Text(
                                    value.text,
                                    style: TextStyle(
                                      color: Colors.redAccent.withOpacity(0.8),
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      // ─── 2. BOTTOM AREA (Formatting + Math Tools) ───
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min, // SHRINK-WRAP THE ROW
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // COMPACT 2x2 FORMATTING GRID
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(LucideIcons.zoomIn, size: 18), onPressed: onIncreaseSize, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: Colors.blueAccent),
                                    IconButton(icon: const Icon(LucideIcons.zoomOut, size: 18), onPressed: onDecreaseSize, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: Colors.blueAccent),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: Icon(showBorder ? LucideIcons.checkSquare : LucideIcons.square, size: 18), onPressed: onToggleBorder, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: showBorder ? const Color(0xFF10B981) : Colors.blueAccent),
                                    IconButton(icon: const Icon(LucideIcons.messageSquare, size: 18), onPressed: onToggleLatex, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), color: const Color(0xFFEF4444)),
                                  ],
                                ),
                              ],
                            ),
                            
                            // SEPARATOR
                            Container(
                              width: 1,
                              height: 40,
                              color: isDark ? Colors.white24 : Colors.black12,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                            ),

                            // MATH BUTTONS
                            Flexible( // Allows scrolling only if it overflows
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min, // SHRINK-WRAP THE MATH BUTTONS
                                  children: [
                                    _buildMathButton(context, 'مالانهاية', '∞', () => onInsert('\\infty ', 7)),
                                    _buildMathButton(context, 'قوسين', '( )', () => onInsert('\\left(  \\right)', 7)),
                                    _buildMathButton(context, 'مجموع', '∑', () => onInsert('\\sum_{}^{} ', 6)),
                                    _buildMathButton(context, 'تكامل', '∫', () => onInsert('\\int_{}^{} ', 6)),
                                    _buildMathButton(context, 'أساس', 'x₂', () => onInsert('_{ }', 2)),
                                    _buildMathButton(context, 'أس', 'x²', () => onInsert('^{ }', 2)),
                                    _buildMathButton(context, 'جذر', '√', () => onInsert('\\sqrt{ }', 6)),
                                    _buildMathButton(context, 'كسر', 'x/y', () => onInsert('\\frac{ }{ }', 6)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
