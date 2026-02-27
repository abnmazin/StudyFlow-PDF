part of 'pdf_viewer_widget_w.dart';

//  PRINT / RELOAD LIFECYCLE EXTENSION 
// Extension on _PDFViewerWidgetState for print orchestration and hard reload.
// Has full access to mutable state fields and setState via 	his.

extension _PDFViewerWidgetStatePrint on _PDFViewerWidgetState {
  Widget _buildPrintLoadingScreen() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Ø¬Ø§Ø±ÙŠ ØªØ¬Ù‡ÙŠØ² Ø§Ù„ØµÙØ­Ø§Øª Ù„Ù„Ø·Ø¨Ø§Ø¹Ø©...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ø³ÙŠØªÙ… Ø§Ø³ØªØ¦Ù†Ø§Ù Ø§Ù„Ø¹Ø±Ø¶ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¨Ø¹Ø¯ Ø§Ù„Ø·Ø¨Ø§Ø¹Ø©',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSafePrint(PdfItem pdf, PrintSettings settings) async {
    // Save current state
    final currentPage = _pdfController.pageNumber ?? 1;
    // final currentZoom = _pdfController.zoomLevel ?? 1.0; // unavailable in this version

    // Pause rendering to avoid Thread Collision
    if (mounted) setState(() => _isPreparingPrint = true);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      await PrintService.executePrint(
        pdf.path,
        settings,
        currentPage: currentPage,
        printJobName: pdf.name,
      );
    } catch (e) {
      debugPrint("Print Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print error: $e')));
      }
    } finally {
      if (mounted) {
        // Store state for resurrection
        _targetPageAfterReload = currentPage;
        // _targetZoomAfterReload = currentZoom;
        _needsReload = true;

        // Remove loading screen but DO NOT render old pointers yet
        setState(() => _isPreparingPrint = false);

        // Wait for UI to flush
        await Future.delayed(const Duration(milliseconds: 50));

        // Resurrect the viewer
        if (mounted && _needsReload) {
          _performHardReload(pdf);
        }
      }
    }
  }

  void _performHardReload(PdfItem pdf) {
    // 1. Safely kill old controller to prevent Memory Leaks! (CRITICAL)
    _pdfController.removeListener(_onControllerChanged);
    // _pdfController.dispose(); // Not available in this version of pdfrx

    // 2. Create fresh controller (forces new PDFium initialization)
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onControllerChanged);

    // 3. Reset flag
    _needsReload = false;

    // 4. Trigger rebuild with new Key
    setState(() {});

    // 5. Restore position after the new native view is mounted
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _pdfController.isReady) {
        _pdfController.goToPage(pageNumber: _targetPageAfterReload);
        // _pdfController.zoomLevel = _targetZoomAfterReload;
      }
    });
  }

  void _showPrintDialog(PdfItem pdf) {
    // Resolve total pages: prefer the controller's known count, fall back to 0.
    final totalPages = _pdfController.isReady
        ? _pdfController.pageCount
        : (pdf.lastPage ?? 1);
    final currentPage = _pdfController.pageNumber ?? pdf.lastPage ?? 1;

    showDialog(
      context: context,
      builder: (_) => PrintDialog(
        pdfPath: pdf.path,
        pdfName: pdf.name,
        totalPages: totalPages,
        currentPage: currentPage,
        onPrint: (settings) async {
          await _executeSafePrint(pdf, settings);
        },
      ),
    );
  }
}