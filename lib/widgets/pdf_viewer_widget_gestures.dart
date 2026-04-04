part of 'pdf_viewer_widget_w.dart';

extension _PDFViewerWidgetStateGestures on _PDFViewerWidgetState {
  void _handlePanStart(Offset position, PdfPage page, double scale) {
    // Guard: only drawing tools reach here (Listener in overlay enforces this)
    if (!_tool.isDrawingTool()) return;

    // SESSION LOCK: If lecturer locked drawing, block it for students.
    final app = context.read<AppProvider>();
    if (app.currentSessionCode != null && app.isLockedDrawingForCurrentUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرسم مقفل حالياً من قبل المحاضر')),
      );
      return;
    }

    if (_tool == ToolType.eraser) {
      _eraseAt(position / scale, page.pageNumber, scale);
      return;
    }

    // VECTOR SHAPES: Initialize with start point
    setState(() {
      _currentPath = [position / scale];
      _currentPage = page.pageNumber;
    });
  }

  void _handlePanUpdate(Offset position, PdfPage page, double scale) {
    // Guard: only drawing tools reach here (Listener in overlay enforces this)
    if (!_tool.isDrawingTool()) return;
    if (_tool == ToolType.eraser) {
      _eraseAt(position / scale, page.pageNumber, scale);
    } else {
      if (_currentPath != null) {
        setState(() {
          // VECTOR SHAPES: Use 2-point paths (start + current end)
          if (_tool == ToolType.arrow ||
              _tool == ToolType.rectangle ||
              _tool == ToolType.circle) {
            // Replace the end point for shapes
            if (_currentPath!.length == 1) {
              _currentPath!.add(position / scale);
            } else {
              _currentPath![1] = position / scale;
            }
          } else {
            // Freehand drawing: add all points
            _currentPath!.add(position / scale);
          }
        });
      }
    }
  }

  void _handlePanEnd(PdfItem pdf) {
    if ((_tool == ToolType.highlight ||
            _tool == ToolType.pen ||
            _tool == ToolType.arrow ||
            _tool == ToolType.rectangle ||
            _tool == ToolType.circle) &&
        _currentPath != null) {
      // Determine highlight type
      HighlightType type;
      if (_tool == ToolType.pen) {
        type = HighlightType.pen;
      } else if (_tool == ToolType.arrow) {
        type = HighlightType.arrow;
      } else if (_tool == ToolType.rectangle) {
        type = HighlightType.rectangle;
      } else if (_tool == ToolType.circle) {
        type = HighlightType.circle;
      } else {
        type = HighlightType.highlight;
      }

      // Determine background color based on shape type
      // Arrows: no background color (null)
      // Rectangles & Circles: use current background color
      int? bgColorValue;
      if (type == HighlightType.rectangle || type == HighlightType.circle) {
        bgColorValue = _shapeFillColor.value;
      }
      // For arrows, pen, and highlight: bgColorValue remains null

      final highlight = Highlight(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        path: List.from(_currentPath!),
        color: _currentColor,
        page: _currentPage,
        strokeWidth: _currentStrokeWidth,
        type: type,
        backgroundColor: bgColorValue, // Set background color for shapes
      );

      context.read<AppProvider>().addHighlight(pdf.id, highlight);

      // DELTA SYNC: Handled by AppProvider.addHighlight/removeHighlight
      setState(() {
        _currentPath = null;
        _currentPage = -1;
      });
    }
  }

  void _eraseAt(Offset pt, int pageNumber, double scale) {
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;
    final double hitRadius = 20.0 / scale; // Tolerance in PDF units (20px screen)
    List<Highlight> toRemove = [];

    for (var h in pdf.highlights) {
      if (h.page != pageNumber) continue;
      bool hit = false;

      // Ø¥Ø°Ø§ ÙƒØ§Ù† ØªØ¸Ù„ÙŠÙ„Ø§Ù‹ Ø°ÙƒÙŠØ§Ù‹ Ù„Ù„Ù†ØµÙˆØµ
      if (h.type == HighlightType.text && h.rects != null) {
        for (var r in h.rects!) {
          // ØªÙˆØ³ÙŠØ¹ Ù…Ù†Ø·Ù‚Ø© Ø§Ù„Ù„Ù…Ø³ Ù‚Ù„ÙŠÙ„Ø§Ù‹ Ù„ØªØ³Ù‡ÙŠÙ„ Ø§Ù„Ù…Ø³Ø­
          if (r.inflate(hitRadius).contains(pt)) {
            hit = true;
            break;
          }
        }
      }
      // Geometric shapes: allow erasing from border or inside area.
      else if ((h.type == HighlightType.rectangle ||
              h.type == HighlightType.circle ||
              h.type == HighlightType.arrow) &&
          h.path.length >= 2) {
        final p1 = h.path.first;
        final p2 = h.path.last;
        final double effectiveRadius = (h.strokeWidth / 2) + hitRadius;

        if (h.type == HighlightType.arrow) {
          final d = _distanceToSegment(pt, p1, p2);
          hit = d <= effectiveRadius;
        } else if (h.type == HighlightType.rectangle) {
          final rect = Rect.fromPoints(p1, p2);
          // Better logic: inside inflated rect, but specifically hitting the stroke or the fill
          if (rect.inflate(effectiveRadius).contains(pt)) {
            // Hit edge
            final onEdge = (pt.dx - rect.left).abs() <= effectiveRadius ||
                (pt.dx - rect.right).abs() <= effectiveRadius ||
                (pt.dy - rect.top).abs() <= effectiveRadius ||
                (pt.dy - rect.bottom).abs() <= effectiveRadius;
            
            // Hit interior if it has a background fill
            final filled = h.backgroundColor != null && rect.contains(pt);
            
            hit = onEdge || filled;
          }
        } else if (h.type == HighlightType.circle) {
          final rect = Rect.fromPoints(p1, p2);
          final cx = (rect.left + rect.right) / 2;
          final cy = (rect.top + rect.bottom) / 2;
          final rx = rect.width / 2;
          final ry = rect.height / 2;

          if (rx > 0 && ry > 0) {
            // Distance from center relative to radius (ellipsoid distance)
            final dx = (pt.dx - cx);
            final dy = (pt.dy - cy);
            
            // Check border hit
            // In a circle rx=ry=R, distance is sqrt(dx^2+dy^2). Hit if distance close to R.
            // For ellipses, we check if the point is within tolerance of the edge
            final double distFromCenter = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
            
            // Border tolerance: 1.0 is the exact edge. 
            // We want to be within tolerance on either side of 1.0
            final double tol = effectiveRadius / ((rx + ry) / 2);
            final hitBorder = (distFromCenter - 1.0).abs() <= tol;
            final hitFill = h.backgroundColor != null && distFromCenter <= 1.0;
            
            hit = hitBorder || hitFill;
          }
        }
      }
      // Freehand pen or highlight
      else {
        // PER-STROKE HIT DETECTION: 
        // strokeWidth / 2 (the radius of the line) + base tolerance (hitRadius already in PDF units)
        final double effectiveRadius = (h.strokeWidth / 2) + hitRadius;

        for (var i = 0; i < h.path.length; i++) {
          final p = h.path[i];
          // 1. Direct point hit
          if ((p - pt).distance < effectiveRadius) {
            hit = true;
            break;
          }
          // 2. Segment hit (allowing swipes across any part of the line)
          if (i > 0) {
            final d = _distanceToSegment(pt, h.path[i - 1], p);
            if (d <= effectiveRadius) {
              hit = true;
              break;
            }
          }
        }
      }

      if (hit) toRemove.add(h);
    }

    bool removedSomething = false;
    for (var h in toRemove) {
      app.removeHighlight(pdf.id, h);
      removedSomething = true;
    }

    // UI FIX: Force the screen to repaint immediately after erasing
    if (removedSomething && mounted) {
      setState(() {});
    }
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLen2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLen2 == 0) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLen2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  void _addTextAt(Offset pt, int pageNumber) {
    if (_isProcessing) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final comment = PdfComment(
      id: id,
      page: pageNumber,
      position: pt, // Assumed unscaled ID passed from caller
      content: '',
      date: DateTime.now(),
      createdBy: context.read<AppProvider>().currentUser?.username,
      color: _textColor,
      fontSize: _fontSize,
      isBold: _isBold,
      isLatex: _isLatex, // NEW: carry current LaTeX mode
      fontFamily: _textFontFamily,
      showBorder: _showBorder,
      borderColor: _borderColor,
      bgColor: _textBgColor,
    );

    final app = context.read<AppProvider>();
    if (app.activePdf == null) return;

    app.addComment(app.activePdf!.id, comment);

    // CRITICAL: Initialize editing styles for the new comment
    app.startEditing(comment.id, comment);

    setState(() => _editingCommentId = comment.id);
  }

  void _updateCurrentEditingText() {
    if (_editingCommentId == null) return;
    final app = context.read<AppProvider>();
    app.updateEditingStyle(
      commentId: _editingCommentId!,
      color: _textColor,
      fontSize: _fontSize,
      isBold: _isBold,
      isLatex: _isLatex,
      fontFamily: _textFontFamily,
      showBorder: _showBorder,
      borderColor: _borderColor,
      bgColor: _textBgColor,
    );
  }

  void _addTextHighlight(Color color) async {
    final selection = _textSelection;
    if (selection == null) return;

    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;

    try {
      final ranges = await selection.getSelectedTextRanges();
      final selectionsByPage = <int, List<Rect>>{};

      for (final range in ranges) {
        final pageNumber = range.pageNumber;
        final page = _pdfController
            .document
            .pages[pageNumber - 1]; // Ensure document is loaded

        if (!selectionsByPage.containsKey(pageNumber)) {
          selectionsByPage[pageNumber] = [];
        }

        for (final fragment in range.enumerateFragmentBoundingRects()) {
          final rect = fragment.bounds.toRect(page: page);
          selectionsByPage[pageNumber]!.add(rect);
        }
      }

      for (final entry in selectionsByPage.entries) {
        final highlight = Highlight(
          id: 'hl_${DateTime.now().microsecondsSinceEpoch}',
          path: [], // Empty path for text highlights
          color: color,
          page: entry.key,
          type: HighlightType.text,
          rects: entry.value,
        );
        app.addHighlight(pdf.id, highlight);
      }

      await _clearCurrentTextSelection(selection);
    } catch (e) {
      debugPrint('Error adding text highlight: $e');
    }
  }

  Future<void> _clearCurrentTextSelection([PdfTextSelection? selection]) async {
    final currentSelection = selection ?? _textSelection;

    _selectionChangeToken++;
    _ignoreSelectionEventsUntil = DateTime.now().add(
      const Duration(milliseconds: 900),
    );

    if (mounted) {
      setState(() {
        _textSelection = null;
        _isTextSelectionMenuVisible = false;
        _suppressTextSelection = true;
      });
    }

    if (currentSelection is PdfTextSelectionDelegate) {
      await currentSelection.clearTextSelection();
    }

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          setState(() => _suppressTextSelection = false);
        }
      });
    });
  }
}