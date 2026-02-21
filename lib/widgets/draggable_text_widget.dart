import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

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
  late FocusNode _focusNode;
  late TextEditingController _controller;
  Offset _dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'TextComment_${widget.commentId}');
    _controller = TextEditingController(text: widget.content);

    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && widget.isEditing && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _finishEditing();
        }
      });
    }
  }

  void _finishEditing() {
    widget.onEditComplete(_controller.text, null);
  }

  @override
  void didUpdateWidget(covariant DraggableTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🚨 الحل الجذري: إجبار حفظ النص إذا قام المستخدم بتغيير الأداة بشكل مفاجئ
    if (widget.isEditing && !oldWidget.isEditing) {
      _focusNode.requestFocus();
    } else if (!widget.isEditing && oldWidget.isEditing) {
      // إرسال النص للـ Provider لحفظه قبل الخروج من وضع التعديل
      final text = _controller.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onEditComplete(text, null);
        }
      });
      _focusNode.unfocus();
    }

    // CRITICAL FIX: NEVER reset controller text while user is actively editing (focus is on the field)
    // This would destroy the cursor position and selection
    if (!widget.isEditing && !_focusNode.hasFocus && widget.content != oldWidget.content) {
      _controller.text = widget.content;
    }

    // 🚨 منع القفز: تصفير إزاحة السحب بعد أن يقوم الـ Provider بتحديث موقع النص الأساسي
    if (_dragOffset != Offset.zero) {
      _dragOffset = Offset.zero;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<Widget> _buildRichContent(String text, TextStyle style) {
    if (text.isEmpty) return [];

    final regex = RegExp(r'(\$\$[\s\S]+?\$\$|\$[^$]+?\$)');
    final children = <Widget>[];
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        children.add(
          Text(text.substring(lastMatchEnd, match.start), style: style),
        );
      }

      final mathContent = match.group(0)!;
      String cleanMath;
      if (mathContent.startsWith(r'$$')) {
        cleanMath = mathContent.substring(2, mathContent.length - 2);
      } else {
        cleanMath = mathContent.substring(1, mathContent.length - 1);
      }

      children.add(
        Math.tex(
          cleanMath,
          textStyle: style,
          onErrorFallback: (e) =>
              Text(mathContent, style: style.copyWith(color: Colors.red)),
        ),
      );
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      children.add(Text(text.substring(lastMatchEnd), style: style));
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Use read() instead of watch() to prevent rebuilds that destroy TextField cursor state
    // Only fetch editing styles without triggering rebuilds on every provider change
    final app = context.read<AppProvider>();
    final tempStyles = widget.isEditing
        ? app.getEditingStyles(widget.commentId)
        : null;

    final effectiveColor = tempStyles != null
        ? Color(tempStyles['color'])
        : widget.color;
    final effectiveFontSize = tempStyles != null
        ? (tempStyles['fontSize'] as double)
        : widget.fontSize;
    final effectiveIsBold = tempStyles != null
        ? (tempStyles['isBold'] as bool)
        : widget.isBold;
    final effectiveIsLatex = tempStyles != null
        ? (tempStyles['isLatex'] as bool)
        : widget.isLatex;
    final effectiveShowBorder = tempStyles != null
        ? (tempStyles['showBorder'] as bool)
        : widget.showBorder;
    final effectiveBorderColor = tempStyles != null
        ? Color(tempStyles['borderColor'])
        : widget.borderColor;
    final effectiveBgColor = tempStyles != null
        ? Color(tempStyles['bgColor'])
        : widget.bgColor;

    final style = TextStyle(
      color: effectiveColor,
      fontSize: effectiveFontSize * widget.scale,
      fontWeight: effectiveIsBold ? FontWeight.bold : FontWeight.normal,
    );

    Widget contentWidget;

    // 🚨 توحيد شكل الـ Container في حالة الكتابة وحالة العرض ليكون مرتباً
    if (widget.isEditing) {
      contentWidget = Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
            minWidth: 100,
          ),
          child: IntrinsicWidth(
            child: Focus(
              onKeyEvent: (node, event) {
                // CRITICAL: Allow TextField to receive arrow keys for cursor navigation
                // Only consume them AFTER TextField handles them to prevent PDF viewer shortcuts
                final key = event.logicalKey;
                
                // Let arrow keys and navigation keys pass through to TextField
                if (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowRight ||
                    key == LogicalKeyboardKey.arrowUp ||
                    key == LogicalKeyboardKey.arrowDown ||
                    key == LogicalKeyboardKey.home ||
                    key == LogicalKeyboardKey.end) {
                  // Return ignored to let TextField handle them first
                  // TextField will consume them, preventing parent widgets from seeing them
                  return KeyEventResult.ignored;
                }
                
                // Allow space key for typing
                if (key == LogicalKeyboardKey.space) {
                  return KeyEventResult.ignored;
                }
                
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: null,
                minLines: 1,
                style: style,
                enableInteractiveSelection: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  // hintText: 'اكتب هنا...',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onTapOutside: (event) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  if (event.position.dx > screenWidth - 320) return;
                  _finishEditing();
                },
                onSubmitted: (val) => _finishEditing(),
              ),
            ),
          ),
        ),
      );
    } else {
      final textContent = _controller.text;
      if (effectiveIsLatex) {
        contentWidget = textContent.isEmpty
            ? Text(
                'Tap to edit',
                style: style.copyWith(fontStyle: FontStyle.italic),
              )
            : Math.tex(
                textContent,
                textStyle: style,
                onErrorFallback: (e) =>
                    Text(textContent, style: style.copyWith(color: Colors.red)),
              );
      } else {
        final children = _buildRichContent(textContent, style);
        if (children.isEmpty) {
          contentWidget = Text(
            'Tap to edit',
            style: style.copyWith(fontStyle: FontStyle.italic),
          );
        } else {
          contentWidget = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            runSpacing: 2,
            children: children,
          );
        }
      }
    }

    return GestureDetector(
      onTap: widget.onTap,
      onPanUpdate: widget.enableDrag
          ? (details) => setState(() => _dragOffset += details.delta)
          : null,
      onPanEnd: widget.enableDrag
          ? (details) => widget.onDragEnd(_dragOffset)
          : null,
      child: Transform.translate(
        offset: _dragOffset,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: effectiveBgColor == Colors.transparent
                ? null
                : effectiveBgColor,  // Use full opacity for visibility
            // إظهار إطار لطيف أثناء التعديل أو إذا اختار المستخدم إظهار الإطار
            border: effectiveShowBorder
                ? Border.all(color: effectiveBorderColor, width: 2)  // Thicker border for visibility
                : Border.all(
                    color: widget.isEditing
                        ? Colors.blue.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: widget.isEditing ? 1.5 : 0,
                  ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: contentWidget,
        ),
      ),
    );
  }
}
