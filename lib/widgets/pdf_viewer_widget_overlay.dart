part of 'pdf_viewer_widget_w.dart';

extension _PDFViewerWidgetStateOverlay on _PDFViewerWidgetState {
  Widget _buildPageOverlay(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
    PdfItem pdf,
  ) {
    final scale = pageRect.width / page.width;
    final bool passThrough = _tool.isHand;

    return RepaintBoundary(
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

          // ── 3. طبقة التفاعل: Listener فقط (لا يدخل gesture arena أبداً) ──
          Positioned.fill(
            child: IgnorePointer(
              ignoring: passThrough,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown:   (e) => _onOverlayPointerDown(e, page, pdf, scale),
                onPointerMove:   (e) => _onOverlayPointerMove(e, page, scale),
                onPointerUp:     (e) => _onOverlayPointerUp(e, page, pdf, scale),
                onPointerCancel: (e) => _onOverlayPointerCancel(e),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // ── 4. التعليقات النصية (دائماً في الأعلى) ──
          ...pdf.comments.where((c) => c.page == page.pageNumber).map((c) {
            return Positioned(
              left: c.position.dx,
              top: c.position.dy,
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
                scale: scale,
                isEditing: c.id == _editingCommentId,
                enableDrag: !(_tool == ToolType.eraser) && (c.id != _editingCommentId),
                onEditComplete: (newText, event) {
                  final appProvider = context.read<AppProvider>();
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
                      final styles = context.read<AppProvider>().getEditingStyles(c.id);
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
                    final newPos = c.position + offset;
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
  }

  // ═══════════════════════════════════════════════════════════════
  // معالجات أحداث المؤشر — تعمل على مستوى Listener (بدون arena)
  // ═══════════════════════════════════════════════════════════════

  void _onOverlayPointerDown(PointerDownEvent e, PdfPage page, PdfItem pdf, double scale) {
    _activePointerIds.add(e.pointer);

    if (_activePointerIds.length == 1) {
      _primaryPointerId = e.pointer;
      _primaryDownPos   = e.localPosition;
      _primaryDownTime  = DateTime.now();

      if (_tool.isDrawing) {
        setState(() => _isActivelyDrawing = true);
        _handlePanStart(e.localPosition, page, scale);
      }
    } else {
      // إصبع ثاني → إلغاء الرسم، pdfrx يتولى pinch-zoom
      if (_isActivelyDrawing) {
        setState(() {
          _currentPath = null;
          _isActivelyDrawing = false;
        });
      }
    }
  }

  void _onOverlayPointerMove(PointerMoveEvent e, PdfPage page, double scale) {
    if (_activePointerIds.length != 1) return;
    if (e.pointer != _primaryPointerId) return;
    if (!_isActivelyDrawing) return;
    if (_currentPath == null) return;
    if (_selectedHighlightId != null) return;

    _handlePanUpdate(e.localPosition, page, scale);
  }

  void _onOverlayPointerUp(PointerUpEvent e, PdfPage page, PdfItem pdf, double scale) {
    final wasPrimary = (e.pointer == _primaryPointerId);

    if (wasPrimary && _isActivelyDrawing && _currentPath != null) {
      _handlePanEnd(pdf);
    }

    // كشف النقر يدوياً (بديل onTapUp في GestureDetector)
    if (wasPrimary && _primaryDownPos != null && _primaryDownTime != null) {
      final distance = (e.localPosition - _primaryDownPos!).distance;
      final duration = DateTime.now().difference(_primaryDownTime!);

      if (distance < 8.0 && duration.inMilliseconds < 400) {
        _handleOverlayTap(e.localPosition, page, pdf, scale);
      }
    }

    _activePointerIds.remove(e.pointer);
    if (wasPrimary) {
      setState(() => _isActivelyDrawing = false);
      _primaryPointerId = null;
      _primaryDownPos   = null;
      _primaryDownTime  = null;
    }
  }

  void _onOverlayPointerCancel(PointerCancelEvent e) {
    _activePointerIds.remove(e.pointer);

    if (e.pointer == _primaryPointerId) {
      if (_isActivelyDrawing && _currentPath != null) {
        setState(() => _currentPath = null);
      }
      setState(() => _isActivelyDrawing = false);
      _primaryPointerId = null;
      _primaryDownPos   = null;
      _primaryDownTime  = null;
    }
  }

  void _handleOverlayTap(Offset pos, PdfPage page, PdfItem pdf, double scale) {
    final appProvider = context.read<AppProvider>();
    if (appProvider.activeEditingCommentId != null) return;

    if (_tool == ToolType.cursor || _tool == ToolType.select) {
      _handleSelectionTap(pos, page, pdf, scale);
    } else if (_tool == ToolType.text) {
      _addTextAt(pos / scale, page.pageNumber);
    } else if (_tool.isDrawing) {
      if (_selectedHighlightId != null) {
        setState(() => _selectedHighlightId = null);
      }
    }
  }
}