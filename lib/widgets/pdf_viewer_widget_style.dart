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
    } else {
      setState(() => _selectedHighlightId = null);
    }
  }

  void _beginShapeTransform(
    Offset docPos,
    PdfItem pdf,
    int pageNumber,
    double scale,
  ) {
    final selected = _findSelectedShape(pdf, pageNumber);
    if (selected == null) return;

    final bounds = _highlightBounds(selected);
    if (bounds == null) return;

    // Keep handle hit radius stable on screen regardless of zoom.
    final handleHitRadius = (12.0 / scale).clamp(6.0, 24.0);
    final inflateBy = selected.strokeWidth + 2.0 > 6.0
        ? selected.strokeWidth + 2.0
        : 6.0;
    final visualBounds = bounds.inflate(inflateBy);
    final handleIndex = _hitHandleIndex(docPos, visualBounds, handleHitRadius);

    _shapeTransformStart = docPos;
    _shapeTransformInitialBounds = bounds;
    _shapeTransformOriginalPath = List<Offset>.from(selected.path);
    _activeResizeHandleIndex = handleIndex;
    _isMovingSelectedShape =
        handleIndex == null && visualBounds.contains(docPos);
  }

  void _updateShapeTransform(Offset docPos, PdfItem pdf, int pageNumber) {
    final selected = _findSelectedShape(pdf, pageNumber);
    final start = _shapeTransformStart;
    final initialBounds = _shapeTransformInitialBounds;
    final originalPath = _shapeTransformOriginalPath;
    if (selected == null ||
        start == null ||
        initialBounds == null ||
        originalPath == null) {
      return;
    }

    final app = context.read<AppProvider>();
    final activePdf = app.activePdf;
    if (activePdf == null) return;

    final delta = docPos - start;
    Rect nextBounds = initialBounds;

    if (_activeResizeHandleIndex != null) {
      nextBounds = _resizeRectFromHandle(
        initialBounds,
        _activeResizeHandleIndex!,
        delta,
      );
    } else if (_isMovingSelectedShape) {
      nextBounds = initialBounds.shift(delta);
    } else {
      return;
    }

    final updatedPath = _fitPathToBounds(
      originalPath,
      initialBounds,
      nextBounds,
    );
    final updatedShape = selected.copyWith(path: updatedPath);
    app.updateHighlight(activePdf.id, selected, updatedShape);
  }

  void _endShapeTransform() {
    _shapeTransformStart = null;
    _shapeTransformInitialBounds = null;
    _shapeTransformOriginalPath = null;
    _activeResizeHandleIndex = null;
    _isMovingSelectedShape = false;
  }

  void _updateShapeHoverCursor(
    Offset docPos,
    PdfItem pdf,
    int pageNumber,
    double scale,
  ) {
    final next = _cursorForSelectPosition(docPos, pdf, pageNumber, scale);
    if (_shapeHoverCursor == next) return;
    if (!mounted) return;
    setState(() => _shapeHoverCursor = next);
  }

  void _resetShapeHoverCursor() {
    if (_shapeHoverCursor == SystemMouseCursors.basic) return;
    if (!mounted) return;
    setState(() => _shapeHoverCursor = SystemMouseCursors.basic);
  }

  MouseCursor _cursorForSelectPosition(
    Offset docPos,
    PdfItem pdf,
    int pageNumber,
    double scale,
  ) {
    final selected = _findSelectedShape(pdf, pageNumber);
    if (selected == null) return SystemMouseCursors.basic;
    final bounds = _highlightBounds(selected);
    if (bounds == null) return SystemMouseCursors.basic;

    final inflateBy = selected.strokeWidth + 2.0 > 6.0
        ? selected.strokeWidth + 2.0
        : 6.0;
    final visualBounds = bounds.inflate(inflateBy);
    final handleHitRadius = (12.0 / scale).clamp(6.0, 24.0);
    final handle = _hitHandleIndex(docPos, visualBounds, handleHitRadius);

    if (handle == 0 || handle == 3) {
      return SystemMouseCursors.resizeUpLeftDownRight;
    }
    if (handle == 1 || handle == 2) {
      return SystemMouseCursors.resizeUpRightDownLeft;
    }
    if (visualBounds.contains(docPos)) {
      return SystemMouseCursors.move;
    }

    return SystemMouseCursors.basic;
  }

  Highlight? _findSelectedShape(PdfItem pdf, int pageNumber) {
    if (_selectedHighlightId == null) return null;
    return pdf.highlights
        .where((h) => h.page == pageNumber)
        .where((h) => h.id == _selectedHighlightId)
        .firstOrNull;
  }

  Rect? _highlightBounds(Highlight shape) {
    if (shape.path.isEmpty) return null;
    if (shape.path.length == 1) {
      final p = shape.path.first;
      return Rect.fromLTWH(p.dx, p.dy, 0.01, 0.01);
    }

    double left = shape.path.first.dx;
    double top = shape.path.first.dy;
    double right = shape.path.first.dx;
    double bottom = shape.path.first.dy;
    for (final p in shape.path) {
      if (p.dx < left) left = p.dx;
      if (p.dy < top) top = p.dy;
      if (p.dx > right) right = p.dx;
      if (p.dy > bottom) bottom = p.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  int? _hitHandleIndex(Offset point, Rect rect, double radius) {
    final handles = <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];

    for (var i = 0; i < handles.length; i++) {
      if ((handles[i] - point).distance <= radius) {
        return i;
      }
    }
    return null;
  }

  Rect _resizeRectFromHandle(Rect rect, int handleIndex, Offset delta) {
    const minSize = 8.0;
    double left = rect.left;
    double right = rect.right;
    double top = rect.top;
    double bottom = rect.bottom;

    switch (handleIndex) {
      case 0: // top-left
        left += delta.dx;
        top += delta.dy;
        break;
      case 1: // top-right
        right += delta.dx;
        top += delta.dy;
        break;
      case 2: // bottom-left
        left += delta.dx;
        bottom += delta.dy;
        break;
      case 3: // bottom-right
        right += delta.dx;
        bottom += delta.dy;
        break;
    }

    if ((right - left).abs() < minSize) {
      if (handleIndex == 0 || handleIndex == 2) {
        left = right - minSize;
      } else {
        right = left + minSize;
      }
    }
    if ((bottom - top).abs() < minSize) {
      if (handleIndex == 0 || handleIndex == 1) {
        top = bottom - minSize;
      } else {
        bottom = top + minSize;
      }
    }

    return Rect.fromLTRB(
      left < right ? left : right,
      top < bottom ? top : bottom,
      left < right ? right : left,
      top < bottom ? bottom : top,
    );
  }

  List<Offset> _fitPathToBounds(List<Offset> path, Rect oldRect, Rect newRect) {
    final oldW = oldRect.width.abs() < 0.0001 ? 1.0 : oldRect.width;
    final oldH = oldRect.height.abs() < 0.0001 ? 1.0 : oldRect.height;

    return path.map((p) {
      final nx = (p.dx - oldRect.left) / oldW;
      final ny = (p.dy - oldRect.top) / oldH;
      return Offset(
        newRect.left + nx * newRect.width,
        newRect.top + ny * newRect.height,
      );
    }).toList();
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
    final effectiveTool = _tool == ToolType.select
        ? (_selectedAnnotationTool(context.read<AppProvider>().activePdf) ??
              _tool)
        : _tool;

    setState(() {
      if (effectiveTool == ToolType.pen) {
        _penColor = color;
      } else if (effectiveTool == ToolType.highlight) {
        _highlightColor = color;
        _updateSelectedShapeColor(color);
      } else if (effectiveTool == ToolType.text) {
        _textColor = color;
        _updateCurrentEditingText();
      } else {
        _shapeStrokeColor = color;
        _updateSelectedShapeColor(color);
      }
    });
  }

  void _onStrokeWidthChanged(double width) {
    final effectiveTool = _tool == ToolType.select
        ? (_selectedAnnotationTool(context.read<AppProvider>().activePdf) ??
              _tool)
        : _tool;
    setState(() => _toolStrokeWidths[effectiveTool] = width);
    _updateSelectedShapeStrokeWidth(width); // Sync with active shape
  }
}
