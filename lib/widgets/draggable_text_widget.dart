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

  TextDirection _resolveTextDirection(String text) {
    final trimmedLeading = text.trimLeft();
    if (trimmedLeading.isEmpty) return TextDirection.rtl;

    // Dynamic direction from the first meaningful character in the note.
    final first = trimmedLeading[0];
    final startsWithArabic = RegExp(r'^[\u0600-\u06FF]').hasMatch(first);
    return startsWithArabic ? TextDirection.rtl : TextDirection.ltr;
  }

  String _fixBidiBrackets(String text) {
    const lrm = '\u200E';

    // Isolate common LTR math/physics segments so brackets and slashes do not flip in RTL context.
    var fixed = text.replaceAllMapped(
      RegExp(r'([A-Za-z0-9][A-Za-z0-9\s/\\+\-*=.,:;_%^]*[\)\]])'),
      (m) => '${m.group(1)}$lrm',
    );

    // Also stabilize opening brackets that start LTR chunks like (F/m) or [v/t].
    fixed = fixed.replaceAllMapped(
      RegExp(r'([\(\[])([A-Za-z0-9])'),
      (m) => '${m.group(1)}$lrm${m.group(2)}',
    );

    return fixed;
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
    final textDirection = _resolveTextDirection(_textController.text);
    final isRtl = textDirection == TextDirection.rtl;
    final displayDirection = _resolveTextDirection(widget.content);
    final displayIsRtl = displayDirection == TextDirection.rtl;
    final fixedDisplayText = _fixBidiBrackets(widget.content);

    final sharedStyle = TextStyle(
      color: widget.color,
      fontSize: widget.fontSize * widget.scale,
      fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
      fontFamily: widget.fontFamily,
      fontFamilyFallback: const [
        'Noto Naskh Arabic',
        'Noto Sans Arabic',
        'Amiri',
        'Segoe UI',
        'Tahoma',
        'Arial',
      ],
    );

    // تجهيز المحتوى (حقل تعديل أو نص عرض)
    Widget contentWidget;

    if (widget.isEditing) {
      // ── وضع التعديل: حقل نص مضمّن ──────────────────────────────────────
      contentWidget = IntrinsicWidth(
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
            style: sharedStyle,
            textDirection: textDirection,
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) {
              // Re-evaluate direction while typing so mixed-language text feels natural.
              setState(() {});
            },
            onTapOutside: (event) {
              widget.onEditComplete(_textController.text, event);
            },
            onSubmitted: (value) {
              widget.onEditComplete(value, null);
            },
          ),
        ),
      );
    } else if (widget.isLatex) {
      // ── وضع العرض: لاتيكس ────────────────────────────────────────────────
      contentWidget = Math.tex(widget.content, textStyle: sharedStyle);
    } else {
      // ── وضع العرض: نص عادي ───────────────────────────────────────────────
      List<String> lines = fixedDisplayText.split('\n');
      if (lines.length <= 1) {
        contentWidget = Text(
          fixedDisplayText,
          style: sharedStyle,
          textDirection: displayIsRtl ? TextDirection.rtl : TextDirection.ltr,
          textAlign: displayIsRtl ? TextAlign.right : TextAlign.left,
        );
      } else {
        contentWidget = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: displayIsRtl
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: lines
              .map(
                (line) => Text(
                  line,
                  style: sharedStyle,
                  textDirection: displayIsRtl
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  textAlign: displayIsRtl ? TextAlign.right : TextAlign.left,
                ),
              )
              .toList(),
        );
      }
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
