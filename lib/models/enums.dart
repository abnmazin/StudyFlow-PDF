enum HighlightType {
  highlight,
  pen,
  text,
  comment,
  arrow,
  rectangle,
  circle,
  select,
}

enum ToolType { cursor, select, highlight, pen, text, eraser, arrow, rectangle, circle }

extension ToolTypeX on ToolType {
  bool get isDrawing => switch (this) {
    ToolType.pen || ToolType.highlight || ToolType.arrow ||
    ToolType.rectangle || ToolType.circle || ToolType.eraser => true,
    _ => false,
  };

  bool get isTapOnly => this == ToolType.select || this == ToolType.text;

  bool get isHand => this == ToolType.cursor;
}
