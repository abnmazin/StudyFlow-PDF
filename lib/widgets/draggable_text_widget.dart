import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class DraggableTextWidget extends StatefulWidget {
  final String commentId;
  final String content;
  final Color color;
  final double fontSize;
  final bool isBold;
  final bool isLatex;
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
    final sharedStyle = TextStyle(
      color: widget.color,
      fontSize: widget.fontSize * widget.scale,
      fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
      fontFamily: 'Roboto',
    );

    // تجهيز المحتوى (حقل تعديل أو نص عرض)
    Widget contentWidget;

    if (widget.isEditing) {
      // ── وضع التعديل: حقل نص مضمّن ──────────────────────────────────────
      contentWidget = IntrinsicWidth(
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          autofocus: true,
          maxLines: null,
          minLines: 1,
          style: sharedStyle,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTapOutside: (event) {
            widget.onEditComplete(_textController.text, event);
          },
          onSubmitted: (value) {
            widget.onEditComplete(value, null);
          },
        ),
      );
    } else if (widget.isLatex) {
      // ── وضع العرض: لاتيكس ────────────────────────────────────────────────
      contentWidget = Math.tex(widget.content, textStyle: sharedStyle);
    } else {
      // ── وضع العرض: نص عادي ───────────────────────────────────────────────
      List<String> lines = widget.content.split('\n');
      if (lines.length <= 1) {
        contentWidget = Text(widget.content, style: sharedStyle);
      } else {
        contentWidget = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines
              .map((line) => Text(line, style: sharedStyle))
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
