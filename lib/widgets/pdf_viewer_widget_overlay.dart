part of 'pdf_viewer_widget_w.dart';

extension _PDFViewerWidgetStateOverlay on _PDFViewerWidgetState {
  Widget _buildPageOverlay(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
    PdfItem pdf,
  ) {
    final scale = pageRect.width / page.width;
    final ignoring = _tool == ToolType.cursor || _activePointerCount > 1;

    Widget overlay = Listener(
      // Outer Listener MUST be outside IgnorePointer so pointer-up/cancel
      // always fire even when the overlay is fully ignored (2-finger pan).
      // Without this the counter deadlocks at 2 and drawing never resumes.
      onPointerDown: (_) => setState(() => _activePointerCount++),
      onPointerUp: (_) => setState(() => _activePointerCount--),
      onPointerCancel: (_) => setState(() => _activePointerCount--),
      child: IgnorePointer(
      ignoring: ignoring,
      child: Stack(
        children: [
          // Highlights & Pen
          CustomPaint(
            size: Size(pageRect.width, pageRect.height),
            painter: HighlightPainter(
              highlights: pdf.highlights
                  .where((h) => h.page == page.pageNumber)
                  .toList(),
              scale: scale,
              isCurrent: false,
              selectedHighlightId: _selectedHighlightId,
            ),
          ),

          // Current Drawing
          if (_currentPage == page.pageNumber && _currentPath != null)
            CustomPaint(
              size: Size(pageRect.width, pageRect.height),
              painter: HighlightPainter(
                highlights: [
                  Highlight(
                    id: 'temp_drawing_id',
                    path: _currentPath!,
                    color: _currentColor,
                    page: page.pageNumber,
                    strokeWidth: _currentStrokeWidth,
                    type: _getActiveToolType(),
                  ),
                ],
                scale: scale,
                isCurrent: true,
                selectedHighlightId: null,
              ),
            ),

          if (!ignoring)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  // 1. Guard Clause: Prevent spawning new text if we are currently editing one.
                  // Clicking outside should only close the active text (handled by onTapOutside).
                  final appProvider = context.read<AppProvider>();
                  if (appProvider.activeEditingCommentId != null) {
                    return;
                  }

                  // 2. Normal Tool Logic
                  if (_tool == ToolType.cursor) {
                    _handleSelectionTap(
                      details.localPosition,
                      page,
                      pdf,
                      scale,
                    );
                  } else if (_tool == ToolType.text) {
                    // Only create new text if we are NOT currently editing another one
                    _addTextAt(details.localPosition / scale, page.pageNumber);
                  } else {
                    // Clear selection if tapping with a drawing tool
                    if (_selectedHighlightId != null) {
                      setState(() => _selectedHighlightId = null);
                    }
                  }
                },
                onPanStart: (details) {
                  if (_tool == ToolType.cursor &&
                      _selectedHighlightId != null) {
                    // Allow dragging the selected shape
                    return;
                  }
                  if (_tool != ToolType.cursor && _tool != ToolType.text) {
                    _handlePanStart(details.localPosition, page, scale);
                  }
                },
                onPanUpdate: (details) {
                  if (_tool == ToolType.cursor &&
                      _selectedHighlightId != null) {
                    // Execute the drag logic for the selected shape
                    final app = context.read<AppProvider>();
                    final shape = pdf.highlights
                        .where((h) => h.id == _selectedHighlightId)
                        .firstOrNull;
                    if (shape != null) {
                      final delta = details.delta / scale;
                      final newPath = shape.path.map((p) => p + delta).toList();
                      final updated = shape.copyWith(path: newPath);
                      app.removeHighlight(pdf.id, shape);
                      app.addHighlight(pdf.id, updated);
                    }
                    return;
                  }
                  if (_tool != ToolType.cursor && _tool != ToolType.text) {
                    _handlePanUpdate(details.localPosition, page, scale);
                  }
                },
                onPanEnd: (details) {
                  if (_tool != ToolType.cursor && _tool != ToolType.text) {
                    _handlePanEnd(pdf);
                  }
                },
              ),
            ),

          // Text (Comments) - Must be on TOP to receive hits!
          // Text (Comments) - Must be on TOP to receive hits!
          ...pdf.comments.where((c) => c.page == page.pageNumber).map((c) {
            return Positioned(
              // âœ… FIXED: Use unscaled position - DraggableTextWidget handles scaling
              left: c.position.dx, // REMOVED * scale
              top: c.position.dy, // REMOVED * scale
              child: DraggableTextWidget(
                commentId: c.id,
                content: c.content,
                color: c.color,
                fontSize: c.fontSize,
                isBold: c.isBold,
                isLatex: c.isLatex,
                showBorder: c.showBorder,
                borderColor: c.borderColor,
                bgColor: c.bgColor,
                scale:
                    scale, // âœ… Keep scale for internal font sizing and visual offset
                isEditing: c.id == _editingCommentId,
                enableDrag:
                    !(_tool == ToolType.eraser) && (c.id != _editingCommentId),
                onEditComplete: (newText, event) {
                  // ALWAYS release the provider editing lock first.
                  // Without this, an empty-text submit never calls endEditing,
                  // leaving _activeEditingCommentId set and blocking all future taps.
                  final appProvider = context.read<AppProvider>();
                  if (newText.trim().isEmpty) {
                    appProvider.cancelEditing(c.id); // clears lock, then remove
                    appProvider.removeComment(pdf.id, c);
                  } else {
                    appProvider.endEditing(c.id, newText); // clears lock internally
                  }
                  setState(() => _editingCommentId = null);
                },
                onTap: () {
                  if (_tool == ToolType.text) {
                    context.read<AppProvider>().startEditing(c.id, c);
                    setState(() {
                      _editingCommentId = c.id;
                      final styles = context
                          .read<AppProvider>()
                          .getEditingStyles(c.id);
                      if (styles != null) {
                        _textColor = Color(styles['color']);
                        _fontSize = styles['fontSize'];
                        _isBold = styles['isBold'];
                        _isLatex = styles['isLatex'];
                        _showBorder = styles['showBorder'];
                        _borderColor = Color(styles['borderColor']);
                        _textBgColor = Color(styles['bgColor']);
                      }
                    });
                  } else if (_tool == ToolType.eraser) {
                    context.read<AppProvider>().removeComment(pdf.id, c);
                  }
                  if (mounted) setState(() {});
                },
                onDragEnd: (offset) {
                  if (_tool == ToolType.text || _tool == ToolType.cursor) {
                    // âœ… CORRECT: offset is in screen pixels, position is in page coordinates
                    // DraggableTextWidget already applied the offset visually
                    // Now we update the permanent position in the database
                    final newPos = c.position + offset; // REMOVED / scale

                    context.read<AppProvider>().updateComment(
                      pdf.id,
                      c,
                      c.copyWith(position: newPos),
                    );
                  }
                },
              ),
            );
          }),
        ],
      ),
    ),
    );

    // PERFORMANCE SHIELD: Wrap entire overlay in RepaintBoundary to cache rendering
    return RepaintBoundary(child: overlay);
  }
}