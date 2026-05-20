part of 'pdf_viewer_widget_w.dart';

extension _PDFViewerWidgetStateOverlay on _PDFViewerWidgetState {
  /// Builds DraggableTextWidget widgets for annotations on a specific page.
  /// These are rendered inside pageOverlaysBuilder so they scroll/zoom with the PDF page.
  /// Keyboard isolation is handled by ExcludeFocus + enableKeyboardNavigation instead.
  List<Widget> _buildCommentOverlaysForPage(
    PdfItem pdf,
    AppProvider appProvider,
    Rect pageRect,
    PdfPage page,
    double scale,
  ) {
    final List<Widget> commentWidgets = [];

    for (final c in pdf.comments) {
      if (c.page != page.pageNumber) continue;

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

      commentWidgets.add(
        Positioned(
          left: c.position.dx * scale,
          top: c.position.dy * scale,
          child: DraggableTextWidget(
            commentId: c.id,
            content: c.content,
            attachedMediaUrl: c.attachedMediaUrl,
            color: effectiveColor,
            fontSize: effectiveFontSize,
            isBold: effectiveIsBold,
            isLatex: effectiveIsLatex,
            fontFamily: effectiveFontFamily,
            showBorder: effectiveShowBorder,
            borderColor: effectiveBorderColor,
            bgColor: effectiveBgColor,
            mediaHeight: c.mediaHeight,
            scale: scale,
            isEditing: c.id == _editingCommentId,
            enableDrag:
                !(_tool == ToolType.eraser) && (c.id != _editingCommentId),
            onEditComplete: (newText, mediaUrl, mediaHeight, event) {
              final hasText = newText.trim().isNotEmpty;
              final hasMedia = mediaUrl != null && mediaUrl.isNotEmpty;

              if (!hasText && !hasMedia) {
                appProvider.cancelEditing(c.id);
                appProvider.removeComment(pdf.id, c);
              } else {
                appProvider.endEditing(
                  c.id,
                  newText,
                  attachedMediaUrl: mediaUrl,
                  mediaHeight: mediaHeight,
                );
              }
              if (mounted) setState(() => _editingCommentId = null);
            },
            onIncreaseSize: () {
              final styles = appProvider.getEditingStyles(c.id);
              if (styles != null) {
                appProvider.updateEditingStyle(
                  commentId: c.id,
                  fontSize: (styles['fontSize'] as double) + 2,
                );
              }
            },
            onDecreaseSize: () {
              final styles = appProvider.getEditingStyles(c.id);
              if (styles != null && (styles['fontSize'] as double) > 8) {
                appProvider.updateEditingStyle(
                  commentId: c.id,
                  fontSize: (styles['fontSize'] as double) - 2,
                );
              }
            },
            onToggleBorder: () {
              final styles = appProvider.getEditingStyles(c.id);
              if (styles != null) {
                appProvider.updateEditingStyle(
                  commentId: c.id,
                  showBorder: !(styles['showBorder'] as bool),
                );
              }
            },
            onToggleLatex: () {
              final styles = appProvider.getEditingStyles(c.id);
              if (styles != null) {
                appProvider.updateEditingStyle(
                  commentId: c.id,
                  isLatex: !(styles['isLatex'] as bool),
                );
              }
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
        ),
      );
    }

    return commentWidgets;
  }

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

          // ── 4. التعليقات النصية (DraggableTextWidget) ──
          // تم إعادة التعليقات إلى pageOverlaysBuilder لتتحرك مع الصفحة.
          // مشكلة الكيبورد تم حلها عبر:
          //   - ExcludeFocus في _buildPdfViewerCore
          //   - enableKeyboardNavigation: showOverlays && _editingCommentId == null
          ..._buildCommentOverlaysForPage(pdf, appProvider, pageRect, page, scale),
        ],
      ),
    );

    return RepaintBoundary(child: overlay);
  }
}
