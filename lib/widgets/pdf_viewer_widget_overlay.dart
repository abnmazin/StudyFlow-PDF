part of 'pdf_viewer_widget_w.dart';

extension _PDFViewerWidgetStateOverlay on _PDFViewerWidgetState {
  Widget _buildPageOverlay(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
    PdfItem pdf,
  ) {
    final appProvider = context.watch<AppProvider>();
    final scale = pageRect.width / page.width;
    final ignoring = _tool == ToolType.cursor;

    Widget overlay = IgnorePointer(
      ignoring: ignoring,
      child: Stack(
        children: [
          // ── 1. الأشكال المحفوظة ──
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

          // ── 2. معاينة الرسم الحي ──
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

          // ── 3. طبقة التفاعل — GestureDetector فقط عندما الأداة ليست cursor ──
          if (!ignoring)
            Positioned.fill(
              child: MouseRegion(
                cursor: _tool == ToolType.select
                    ? _shapeHoverCursor
                    : SystemMouseCursors.basic,
                onHover: (event) {
                  if (_tool == ToolType.select) {
                    _updateShapeHoverCursor(
                      event.localPosition / scale,
                      pdf,
                      page.pageNumber,
                      scale,
                    );
                  }
                },
                onExit: (_) {
                  if (_tool == ToolType.select) {
                    _resetShapeHoverCursor();
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final appProvider = context.read<AppProvider>();
                    if (appProvider.activeEditingCommentId != null) return;

                    if (_tool == ToolType.text) {
                      _addTextAt(
                        details.localPosition / scale,
                        page.pageNumber,
                      );
                    } else if (_tool == ToolType.select) {
                      _handleSelectionTap(
                        details.localPosition,
                        page,
                        pdf,
                        scale,
                      );
                    } else {
                      if (_selectedHighlightId != null) {
                        setState(() => _selectedHighlightId = null);
                      }
                    }
                  },
                  onPanStart: (details) {
                    if (_tool.isDrawing) {
                      _handlePanStart(details.localPosition, page, scale);
                    } else if (_tool == ToolType.select) {
                      _beginShapeTransform(
                        details.localPosition / scale,
                        pdf,
                        page.pageNumber,
                        scale,
                      );
                    }
                  },
                  onPanUpdate: (details) {
                    if (_tool.isDrawing && _currentPath != null) {
                      _handlePanUpdate(details.localPosition, page, scale);
                    } else if (_tool == ToolType.select) {
                      _updateShapeTransform(
                        details.localPosition / scale,
                        pdf,
                        page.pageNumber,
                      );
                    }
                  },
                  onPanEnd: (details) {
                    if (_tool.isDrawing && _currentPath != null) {
                      _handlePanEnd(pdf);
                    } else if (_tool == ToolType.select) {
                      _endShapeTransform();
                    }
                  },
                ),
              ),
            ),

          // ── 4. التعليقات النصية (دائماً في الأعلى) ──
          ...pdf.comments.where((c) => c.page == page.pageNumber).map((c) {
            final liveStyles = appProvider.getEditingStyles(c.id);
            final effectiveColor = liveStyles != null
                ? Color(liveStyles['color'] as int)
                : c.color;
            final effectiveFontSize = liveStyles != null
                ? (liveStyles['fontSize'] as num).toDouble()
                : c.fontSize;
            final effectiveIsBold = liveStyles != null
                ? (liveStyles['isBold'] as bool)
                : c.isBold;
            final effectiveIsLatex = liveStyles != null
                ? (liveStyles['isLatex'] as bool)
                : c.isLatex;
            final effectiveFontFamily = liveStyles != null
                ? (liveStyles['fontFamily'] as String)
                : c.fontFamily;
            final effectiveShowBorder = liveStyles != null
                ? (liveStyles['showBorder'] as bool)
                : c.showBorder;
            final effectiveBorderColor = liveStyles != null
                ? Color(liveStyles['borderColor'] as int)
                : c.borderColor;
            final effectiveBgColor = liveStyles != null
                ? Color(liveStyles['bgColor'] as int)
                : c.bgColor;

            return Positioned(
              left: c.position.dx * scale,
              top: c.position.dy * scale,
              child: DraggableTextWidget(
                commentId: c.id,
                content: c.content,
                color: effectiveColor,
                fontSize: effectiveFontSize,
                isBold: effectiveIsBold,
                isLatex: effectiveIsLatex,
                fontFamily: effectiveFontFamily,
                showBorder: effectiveShowBorder,
                borderColor: effectiveBorderColor,
                bgColor: effectiveBgColor,
                scale: scale,
                isEditing: c.id == _editingCommentId,
                enableDrag:
                    !(_tool == ToolType.eraser) && (c.id != _editingCommentId),
                onEditComplete: (newText, event) {
                  if (newText.trim().isEmpty) {
                    appProvider.cancelEditing(c.id);
                    appProvider.removeComment(pdf.id, c);
                  } else {
                    appProvider.endEditing(c.id, newText);
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
                        _textFontFamily = styles['fontFamily'];
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
                  if (_tool == ToolType.text ||
                      _tool == ToolType.cursor ||
                      _tool == ToolType.select) {
                    final newPos = c.position + offset / scale;
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
    );

    return RepaintBoundary(child: overlay);
  }
}
