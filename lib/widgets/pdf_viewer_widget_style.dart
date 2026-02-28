part of 'pdf_viewer_widget_w.dart';

extension _PDFViewerWidgetStateStyle on _PDFViewerWidgetState {
  // --- ADVANCED HIT-TESTING & SELECTION ---

  HighlightType _getActiveToolType() {
    switch (_tool) {
      case ToolType.pen:
        return HighlightType.pen;
      case ToolType.arrow:
        return HighlightType.arrow;
      case ToolType.rectangle:
        return HighlightType.rectangle;
      case ToolType.circle:
        return HighlightType.circle;
      case ToolType.highlight:
        return HighlightType.highlight;
      default:
        return HighlightType.pen;
    }
  }

  void _handleSelectionTap(
    Offset tapPos,
    PdfPage page,
    PdfItem pdf,
    double scale,
  ) {
    final scaledTap = tapPos / scale;
    final shapes = pdf.highlights
        .where((h) => h.page == page.pageNumber)
        .toList();

    Highlight? selectedShape;
    // Iterate in reverse to pick the top-most shape.
    for (final shape in shapes.reversed) {
      if (shape.path.length < 2) continue;
      final rect = Rect.fromPoints(
        shape.path.first,
        shape.path.last,
      ).inflate(15.0);
      if (rect.contains(scaledTap)) {
        selectedShape = shape;
        break;
      }
    }

    if (selectedShape != null) {
      final shape = selectedShape;
      setState(() {
        _selectedHighlightId = shape.id;
        _shapeStrokeColor = shape.color;
        // Load selected shape's stroke width into the tool slot.
        final shapeToolType = _highlightTypeToToolType(shape.type);
        _toolStrokeWidths[shapeToolType] = shape.strokeWidth;
      });
      if (!_isRightPanelOpen) setState(() => _isRightPanelOpen = true);
    } else {
      setState(() => _selectedHighlightId = null);
    }
  }

  /// Maps a persisted [HighlightType] back to the [ToolType] that created it.
  ToolType _highlightTypeToToolType(HighlightType type) {
    switch (type) {
      case HighlightType.pen:
        return ToolType.pen;
      case HighlightType.highlight:
        return ToolType.highlight;
      case HighlightType.arrow:
        return ToolType.arrow;
      case HighlightType.rectangle:
        return ToolType.rectangle;
      case HighlightType.circle:
        return ToolType.circle;
      default:
        return _tool;
    }
  }

  void _updateSelectedShapeColor(Color color) {
    if (_selectedHighlightId == null) return;
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    final shape = pdf.highlights
        .where((h) => h.id == _selectedHighlightId)
        .firstOrNull;
    if (shape != null) {
      final updated = shape.copyWith(color: color);
      app.removeHighlight(pdf.id, shape);
      app.addHighlight(pdf.id, updated);
    }
  }

  void _updateSelectedShapeStrokeWidth(double width) {
    if (_selectedHighlightId == null) return;
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    final shape = pdf.highlights
        .where((h) => h.id == _selectedHighlightId)
        .firstOrNull;
    if (shape != null) {
      final updated = shape.copyWith(strokeWidth: width);
      app.removeHighlight(pdf.id, shape);
      app.addHighlight(pdf.id, updated);
    }
  }

  void _onColorChanged(Color color) {
    setState(() {
      if (_tool == ToolType.pen) {
        _penColor = color;
      } else if (_tool == ToolType.highlight) {
        _highlightColor = color;
        _updateSelectedShapeColor(color);
      } else if (_tool == ToolType.text) {
        _textColor = color;
        _updateCurrentEditingText();
      } else {
        _shapeStrokeColor = color;
        _updateSelectedShapeColor(color);
      }
    });
  }

  void _onStrokeWidthChanged(double width) {
    setState(() => _toolStrokeWidths[_tool] = width);
    _updateSelectedShapeStrokeWidth(width); // Sync with active shape
  }
}