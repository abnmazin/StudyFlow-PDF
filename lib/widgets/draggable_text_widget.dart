import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
      fontFamily: widget.isLatex ? widget.fontFamily : _plainTextFontFamily(widget.content),
    );

    // تجهيز المحتوى (حقل تعديل أو نص عرض)
    Widget contentWidget;

    if (widget.isEditing) {
      // ── وضع التعديل: حقل نص مضمّن ──────────────────────────────────────
      contentWidget = Directionality(
        textDirection: editingDirection,
        child: IntrinsicWidth(
          child: TapRegion(
            groupId: 'text_editing_region',
            onTapOutside: (event) {
              widget.onEditComplete(_textController.text, event);
            },
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
                onChanged: (_) {
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
      );
    } else if (widget.isLatex) {
      // ── وضع العرض: لاتيكس ────────────────────────────────────────────────
      contentWidget = Directionality(
        textDirection: TextDirection.ltr,
        child: Math.tex(widget.content, textStyle: sharedStyle.copyWith(fontFamily: widget.fontFamily)),
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
