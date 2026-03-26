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
              'جارٍ تجهيز الصفحات للطباعة...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم استئناف العرض تلقائيًا بعد الطباعة',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSafePrint(PdfItem pdf, PrintSettings settings) async {
    final sw = Stopwatch()..start();
    void logStage(String stage) {
      debugPrint('[PrintTiming] +${sw.elapsedMilliseconds}ms $stage');
    }

    debugPrint(
      '[Print] start pdf=${pdf.name} destination=${settings.destination.name} runMode=${settings.runMode.name} diagnostics=${settings.enableDiagnostics}',
    );
    logStage('start executeSafePrint');
    // Save current state
    final currentPage = _pdfController.pageNumber ?? 1;
    // final currentZoom = _pdfController.zoomLevel ?? 1.0; // unavailable in this version

    // Total unmount mode: remove PdfViewer from widget tree before printing.
    if (mounted) {
      _isPrintingMode = true;
      setState(() {});
      logStage('entered printing mode (viewer unmounted)');
    }

    // Ensure the old pdfrx texture/view is fully detached before touching
    // Windows print APIs.
    logStage('waiting for unmount frame');
    await Future.delayed(const Duration(milliseconds: 16));
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 700));
    logStage('unmount settle finished');

    try {
      _pdfController.removeListener(_onControllerChanged);
    } catch (e) {
      logStage('ignore pre-print removeListener error: $e');
    }
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onControllerChanged);
    logStage('controller detached and replaced before print');

    try {
      logStage('before PrintService.executePrint');
      await PrintService.executePrint(
        pdf.path,
        settings,
        currentPage: currentPage,
        printJobName: pdf.name,
      );
      logStage('after PrintService.executePrint (success)');
    } catch (e) {
      debugPrint("Print Error: $e");
      logStage('PrintService.executePrint threw error: $e');
      debugPrint(
        '[Print] diagnostics log path: ${PrintService.diagnosticsLogPath}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في الطباعة: $e\nسجل التشخيص: ${PrintService.diagnosticsLogPath}',
            ),
          ),
        );
      }
    } finally {
      // Store state for resurrection
      _targetPageAfterReload = currentPage;
      // _targetZoomAfterReload = currentZoom;
      _needsReload = true;

      // 1) Cool-down: let Windows spooler release native/GPU handles.
      logStage('cool-down start (2s)');
      await Future.delayed(const Duration(seconds: 2));
      logStage('cool-down end');

      if (!mounted) return;
      _isPrintingMode = false;
      setState(() {});
      logStage('printing mode disabled (UI structure restored)');

      // 2) Stabilization: allow Flutter to paint post-unmount UI first.
      logStage('stabilization start (1s)');
      await Future.delayed(const Duration(seconds: 1));
      logStage('stabilization end');

      if (!mounted || !_needsReload) return;

      // 3) Defensive resurrection.
      try {
        logStage('before _performHardReload');
        _performHardReload(pdf);
        logStage('after _performHardReload');
      } catch (e) {
        debugPrint('[Print] hard reload failed: $e');
        logStage('hard reload failed: $e');
      }

      sw.stop();
      debugPrint('[PrintTiming] total=${sw.elapsedMilliseconds}ms');
    }
  }

  void _performHardReload(PdfItem pdf) {
    // 1. Safely kill old controller to prevent memory/native handle issues.
    try {
      _pdfController.removeListener(_onControllerChanged);
    } catch (e) {
      debugPrint('[Print] ignore removeListener error during reload: $e');
    }
    // _pdfController.dispose(); // Not available in this version of pdfrx

    // 2. Create fresh controller (forces new PDFium initialization)
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onControllerChanged);

    // 3. Reset flag
    _needsReload = false;

    // 4. Trigger rebuild with new Key
    setState(() {});

    // 5. Restore position after the new native view is mounted
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _pdfController.isReady) {
        _pdfController.goToPage(pageNumber: _targetPageAfterReload);
        // _pdfController.zoomLevel = _targetZoomAfterReload;
      }
    });
  }

  Future<void> _showPrintDialog(PdfItem pdf) async {
    // Resolve total pages: prefer the controller's known count, fall back to 0.
    final totalPages = _pdfController.isReady
        ? _pdfController.pageCount
        : (pdf.lastPage ?? 1);
    final currentPage = _pdfController.pageNumber ?? pdf.lastPage ?? 1;

    final settings = await showDialog<PrintSettings>(
      context: context,
      builder: (_) => PrintDialog(
        pdfPath: pdf.path,
        pdfName: pdf.name,
        totalPages: totalPages,
        currentPage: currentPage,
      ),
    );

    if (!mounted || settings == null) return;
    await _executeSafePrint(pdf, settings);
  }
}
