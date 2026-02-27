part of 'pdf_viewer_widget_w.dart';

extension _PDFViewerWidgetStateGestures on _PDFViewerWidgetState {
  void _handlePanStart(Offset position, PdfPage page, double scale) {
    if (_tool == ToolType.cursor || _tool == ToolType.text) {
      return; // Text handled by onTapUp
    }
    if (_tool == ToolType.eraser) {
      _eraseAt(position / scale, page.pageNumber);
      return;
    }

    // VECTOR SHAPES: Initialize with start point
    setState(() {
      _currentPath = [position / scale];
      _currentPage = page.pageNumber;
    });
  }

  void _handlePanUpdate(Offset position, PdfPage page, double scale) {
    if (_tool == ToolType.cursor || _tool == ToolType.text) return;
    if (_tool == ToolType.eraser) {
      _eraseAt(position / scale, page.pageNumber);
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

      setState(() {
        _currentPath = null;
        _currentPage = -1;
      });
    }
  }

  void _eraseAt(Offset pt, int pageNumber) {
    final app = context.read<AppProvider>();
    final pdf = app.activePdf;
    if (pdf == null) return;
    const double hitRadius = 20.0;
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
      // Ø¥Ø°Ø§ ÙƒØ§Ù† ØªØ¸Ù„ÙŠÙ„Ø§Ù‹ Ø­Ø±Ø§Ù‹ Ø£Ùˆ Ù‚Ù„Ù…Ø§Ù‹
      else {
        for (var p in h.path) {
          if ((p - pt).distance < hitRadius) {
            hit = true;
            break;
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

  void _addTextAt(Offset pt, int pageNumber) {
    if (_isProcessing) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final comment = PdfComment(
      id: id,
      page: pageNumber,
      position: pt, // Assumed unscaled ID passed from caller
      content: '',
      date: DateTime.now(),
      color: _textColor,
      fontSize: _fontSize,
      isBold: _isBold,
      isLatex: _isLatex, // NEW: carry current LaTeX mode
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
    final pdf = app.activePdf;
    if (pdf == null) return;

    try {
      final comment = pdf.comments.firstWhere((c) => c.id == _editingCommentId);
      final updatedComment = comment.copyWith(
        color: _textColor,
        fontSize: _fontSize,
        isBold: _isBold,
        isLatex: _isLatex,
        showBorder: _showBorder,
        borderColor: _borderColor,
        bgColor: _textBgColor,
      );
      app.updateComment(pdf.id, comment, updatedComment);
    } catch (e) {
      debugPrint('Error updating comment style: $e');
    }
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

      if (selection is PdfTextSelectionDelegate) {
        await selection.clearTextSelection();
      }
      if (mounted) setState(() => _textSelection = null);
    } catch (e) {
      debugPrint('Error adding text highlight: $e');
    }
  }
}