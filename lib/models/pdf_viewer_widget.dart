import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';
import '../providers/app_state.dart';
import '../models/models.dart';

class PDFViewerWidget extends StatefulWidget {
  const PDFViewerWidget({super.key});

  @override
  State<PDFViewerWidget> createState() => _PDFViewerWidgetState();
}

class _PDFViewerWidgetState extends State<PDFViewerWidget> {
  final PdfViewerController _pdfController = PdfViewerController();
  String _tool = 'cursor'; // 'cursor', 'highlight'
  Color _color = const Color(0xFFFEF08A); // yellow-200
  double _strokeWidth = 5.0;

  // Current drawing state
  List<Offset>? _currentPath;
  int _currentPage = -1;

  // @override
  // void dispose() {
  //   // _pdfController.dispose();
  //   super.dispose();
  // }

  // void _onPanStart(DragStartDetails details, PdfPage page, double scale) {
  //   if (_tool != 'highlight') return;
  //   setState(() {
  //     _currentPath = [details.localPosition / scale];
  //     _currentPage = page.pageNumber;
  //   });
  // }

  // void _onPanUpdate(DragUpdateDetails details, double scale) {
  //   if (_tool != 'highlight' || _currentPath == null) return;
  //   setState(() {
  //     _currentPath!.add(details.localPosition / scale);
  //   });
  // }

  // void _onPanEnd(DragEndDetails details, PdfItem pdf) {
  //   if (_tool != 'highlight' || _currentPath == null) return;
  //
  //   final highlight = Highlight(
  //     path: List.from(_currentPath!),
  //     color: _color,
  //     page: _currentPage,
  //   );
  //
  //   context.read<AppProvider>().addHighlight(pdf.id, highlight);
  //
  //   setState(() {
  //     _currentPath = null;
  //     _currentPage = -1;
  //   });
  // }

  // ... (build method remains) ...

  // Widget _buildPageOverlay(...) { ... }
  // class HighlightPainter ... { ... }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final pdf = app.activePdf;

    if (pdf == null) {
      return Container(
        color: const Color(0xFFF8FAFC),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(LucideIcons.upload, size: 48, color: Color(0xFFCBD5E1)),
              SizedBox(height: 16),
              Text(
                'No PDF Selected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
              Text(
                'Select a class and upload a PDF to get started.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyH): () =>
            setState(() => _tool = 'highlight'),
        const SingleActivator(LogicalKeyboardKey.keyE): () =>
            setState(() => _tool = 'eraser'),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _tool = 'cursor'),
        const SingleActivator(LogicalKeyboardKey.keyV): () =>
            setState(() => _tool = 'cursor'),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            // Toolbar
            _buildToolbar(app, pdf),

            // Viewer
            Expanded(
              child: Container(
                color: const Color(0xFFE2E8F0),
                child: PdfViewer.file(
                  pdf.path,
                  key: ValueKey(
                    pdf.path,
                  ), // Ensure viewer resets when file changes
                  controller: _pdfController,
                  params: PdfViewerParams(
                    backgroundColor: const Color(0xFFE2E8F0),
                    pageOverlaysBuilder: (context, pageRect, page) {
                      // Only show overlay when highlighting is active to prevent blocking scrolling
                      if (_tool != 'highlight' && _tool != 'eraser') {
                        // Show existing highlights even in read mode?
                        // Yes, we want to SEE highlights, just not intercept gestures.
                        // But existing logic combines viewing and drawing.
                        // Let's fallback to the IgnorePointer approach inside the builder,
                        // BUT ensure _buildPageOverlay is returning a widget that allows hit testing to pass through.
                        // ...
                        // Actually, if we return empty list, we see NO highlights.
                        // We MUST return highlights.
                        // The issue must be IgnorePointer not working or something else.
                        // Let's try:
                        return [
                          _buildPageOverlay(context, pageRect, page, pdf),
                        ];
                      }
                      return [_buildPageOverlay(context, pageRect, page, pdf)];
                    },
                    onPageChanged: (page) {
                      context.read<AppProvider>().updatePdfScroll(
                        pdf.id,
                        pageNumber: page,
                      );
                      setState(() {}); // Re-build for page counter
                    },
                  ),
                  initialPageNumber: pdf.lastPage ?? 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(AppProvider app, PdfItem? pdf) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (isMobile)
                IconButton(
                  icon: const Icon(LucideIcons.menu, color: Color(0xFF64748B)),
                  onPressed: () => app.toggleMobile(),
                )
              else if (app.isSidebarCollapsed)
                IconButton(
                  icon: const Icon(
                    LucideIcons.panelLeftOpen,
                    color: Color(0xFF64748B),
                  ),
                  onPressed: () => app.toggleSidebar(),
                ),
              if (isMobile || app.isSidebarCollapsed) const SizedBox(width: 8),

              // Page Counter
              if (pdf != null && _pdfController.isReady)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_pdfController.pageNumber} / ${_pdfController.pages.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),

              const SizedBox(width: 12),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.zoomOut, size: 18),
                      onPressed: () => _pdfController.zoomDown(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    const SizedBox(
                      width: 48,
                      child: Center(
                        child: Text('Zoom', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.zoomIn, size: 18),
                      onPressed: () => _pdfController.zoomUp(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          Row(
            children: [
              if (_tool == 'highlight') ...[
                _buildStrokeSlider(),
                const SizedBox(width: 12),
                _buildColorPicker(),
                const SizedBox(width: 12),
              ],

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _ToolBtn(
                      icon: LucideIcons.mousePointer2,
                      label: 'Read',
                      isActive: _tool == 'cursor',
                      onPressed: () => setState(() => _tool = 'cursor'),
                      shortcut: 'Esc',
                    ),
                    _ToolBtn(
                      icon: LucideIcons.highlighter,
                      label: 'Highlight',
                      isActive: _tool == 'highlight',
                      onPressed: () => setState(() => _tool = 'highlight'),
                      shortcut: 'H',
                    ),
                    _ToolBtn(
                      icon: LucideIcons.eraser,
                      label: 'Eraser',
                      isActive: _tool == 'eraser',
                      onPressed: () => setState(() => _tool = 'eraser'),
                      shortcut: 'E',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStrokeSlider() {
    return SizedBox(
      width: 100,
      height: 32,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          trackHeight: 2,
        ),
        child: Slider(
          value: _strokeWidth,
          min: 2,
          max: 20,
          activeColor: const Color(0xFF64748B),
          inactiveColor: const Color(0xFFCBD5E1),
          onChanged: (v) => setState(() => _strokeWidth = v),
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    return Row(
      children:
          [
                const Color(0xFFFEF08A), // Yellow
                const Color(0xFFBBF7D0), // Green
                const Color(0xFFBFDBFE), // Blue
                const Color(0xFFFBCFE8), // Pink
                const Color(0xFFDDD6FE), // Purple
                const Color(0xFFFECACA), // Red
              ]
              .map(
                (c) => GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFFE2E8F0),
                        width: _color == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  // RE-WRITE HANDLERS TO ACCEPT PAGE
  void _handlePanStart(DragStartDetails d, PdfPage page, double scale) {
    if (_tool == 'cursor') return;
    if (_tool == 'eraser') {
      _eraseAt(d.localPosition / scale, page.pageNumber);
    } else {
      setState(() {
        _currentPath = [d.localPosition / scale];
        _currentPage = page.pageNumber;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails d, PdfPage page, double scale) {
    if (_tool == 'cursor') return;
    if (_tool == 'eraser') {
      _eraseAt(d.localPosition / scale, page.pageNumber);
    } else {
      if (_currentPath != null) {
        setState(() {
          _currentPath!.add(d.localPosition / scale);
        });
      }
    }
  }

  void _handlePanEnd(DragEndDetails d, PdfItem pdf) {
    if (_tool == 'highlight' && _currentPath != null) {
      final highlight = Highlight(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        path: List.from(_currentPath!),
        color: _color,
        page: _currentPage,
        strokeWidth: _strokeWidth,
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

      // إذا كان تظليلاً ذكياً للنصوص
      if (h.type == HighlightType.text && h.rects != null) {
        for (var r in h.rects!) {
          // توسيع منطقة اللمس قليلاً لتسهيل المسح
          if (r.inflate(hitRadius).contains(pt)) {
            hit = true;
            break;
          }
        }
      }
      // إذا كان تظليلاً حراً أو قلماً
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

    for (var h in toRemove) {
      app.removeHighlight(pdf.id, h);
    }
  }

  // Method to restore scroll position after load if needed,
  // but pdfrx controller usually handles initial page if passed to params.
  // We can use controller.goToPage(pageNumber: ...)

  @override
  void initState() {
    super.initState();
    // We need to wait for pdf to load to jump to page?
    // PdfViewerParams has initialPageNumber!
    // But we need to access it from build.
  }

  Widget _buildPageOverlay(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
    PdfItem pdf,
  ) {
    // When NOT highlighting, we want gestures to pass through to the PDF for scrolling.
    // When highlighting, we want gestures to be caught by the GestureDetector.
    final ignoring =
        _tool ==
        'cursor'; // Ignore only if cursor (read) mode. Eraser needs events!

    return IgnorePointer(
      ignoring: ignoring,
      child: Stack(
        children: [
          // Existing Highlights
          // These are just visual paintings, they shouldn't block hits unless they have handlers?
          // CustomPaint itself is hit-testable only if a painter returns true in hitTest (default false).
          CustomPaint(
            size: Size(pageRect.width, pageRect.height),
            painter: HighlightPainter(
              highlights: pdf.highlights
                  .where((h) => h.page == page.pageNumber)
                  .toList(),
              scale: pageRect.width / page.width,
            ),
          ),

          // Current Drawing
          if (_currentPage == page.pageNumber && _currentPath != null)
            CustomPaint(
              size: Size(pageRect.width, pageRect.height),
              painter: HighlightPainter(
                highlights: [
                  Highlight(
                    id: 'temp_drawing',
                    path: _currentPath!,
                    color: _color,
                    page: page.pageNumber,
                    strokeWidth: _strokeWidth,
                  ),
                ],
                scale: pageRect.width / page.width,
                isCurrent: true,
              ),
            ),

          // Gesture Detector
          // Only present in tree if highlighting?
          // If we are IgnoringPointer, this won't get hits anyway.
          if (!ignoring)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque, // Opaque blocks hits below it
                onPanStart: (d) =>
                    _handlePanStart(d, page, pageRect.width / page.width),
                onPanUpdate: (d) =>
                    _handlePanUpdate(d, page, pageRect.width / page.width),
                onPanEnd: (d) => _handlePanEnd(d, pdf),
              ),
            ),
        ],
      ),
    );
  }
}

class HighlightPainter extends CustomPainter {
  final List<Highlight> highlights;
  final double scale;
  final bool isCurrent;

  HighlightPainter({
    required this.highlights,
    required this.scale,
    this.isCurrent = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var h in highlights) {
      // 1. رسم التظليل الذكي (النصوص) أولاً
      if (h.type == HighlightType.text && h.rects != null) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = h.color.withOpacity(0.3); // الشفافية المناسبة للقراءة

        for (final rect in h.rects!) {
          final scaledRect = Rect.fromLTRB(
            rect.left * scale,
            rect.top * scale,
            rect.right * scale,
            rect.bottom * scale,
          );
          canvas.drawRect(scaledRect, paint);
        }
        continue; // تم رسم المربع، انتقل للتظليل التالي
      }

      // 2. رسم التظليل الحر والقلم (تجاهل إذا كان المسار فارغاً)
      if (h.path.isEmpty) continue;

      final paint = Paint()
        ..color = h.type == HighlightType.pen
            ? h.color
            : h.color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h.strokeWidth * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      path.moveTo(h.path.first.dx * scale, h.path.first.dy * scale);
      for (var i = 1; i < h.path.length; i++) {
        path.lineTo(h.path[i].dx * scale, h.path[i].dy * scale);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant HighlightPainter oldDelegate) => true;
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;
  final String? shortcut;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context) {
    Color activeColor = const Color(0xFF2563EB);
    if (label == 'Highlight') activeColor = const Color(0xFFA16207);
    if (label == 'Eraser') activeColor = const Color(0xFFDC2626);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? activeColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isActive ? activeColor : const Color(0xFF64748B),
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  shortcut!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
