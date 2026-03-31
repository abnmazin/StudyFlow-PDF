part of 'pdf_viewer_widget_w.dart';

//  PRINT / RELOAD LIFECYCLE EXTENSION
// Extension on _PDFViewerWidgetState for print orchestration and hard reload.
// Has full access to mutable state fields and setState via 	his.

extension _PDFViewerWidgetStatePrint on _PDFViewerWidgetState {
  List<Map<String, dynamic>> _collectAnnotationsForPrint(
    PdfItem pdf,
    AppProvider appProvider,
  ) {
    // نجيب حجم كل صفحة من pdfrx — هذا هو الحجم الحقيقي للـ PDF بالـ points
    double _pageW(int page) {
      try {
        final pages = _pdfController.pages;
        if (page < 1 || page > pages.length) return 0;
        return pages[page - 1].width;
      } catch (_) { return 0; }
    }

    double _pageH(int page) {
      try {
        final pages = _pdfController.pages;
        if (page < 1 || page > pages.length) return 0;
        return pages[page - 1].height;
      } catch (_) { return 0; }
    }

    final highlights = pdf.highlights.map((h) {
      final rawJson = h.toJson();
      return <String, dynamic>{
        'annotationKind': 'highlight',
        'coordSpace': 'ui',
        'uiRenderWidth': _pageW(h.page),
        'uiRenderHeight': _pageH(h.page),
        ...rawJson,
      };
    }).toList();

    final comments = pdf.comments.map((c) {
      final liveStyles = appProvider.getEditingStyles(c.id);
      final effectiveColor = liveStyles != null
          ? (liveStyles['color'] as int)
          : c.color.value;
      final effectiveFontSize = liveStyles != null
          ? (liveStyles['fontSize'] as num).toDouble()
          : c.fontSize;
      final effectiveIsBold = liveStyles != null
          ? (liveStyles['isBold'] as bool)
          : c.isBold;
      final effectiveShowBorder = liveStyles != null
          ? (liveStyles['showBorder'] as bool)
          : c.showBorder;
      final effectiveBorderColor = liveStyles != null
          ? (liveStyles['borderColor'] as int)
          : c.borderColor.value;
      final effectiveBgColor = liveStyles != null
          ? (liveStyles['bgColor'] as int)
          : c.bgColor.value;

      return <String, dynamic>{
        'annotationKind': 'comment',
        'coordSpace': 'ui',
        'uiRenderWidth': _pageW(c.page),
        'uiRenderHeight': _pageH(c.page),
        'id': c.id,
        'page': c.page,
        'dx': c.position.dx,
        'dy': c.position.dy,
        'content': c.content,
        'color': effectiveColor,
        'fontSize': effectiveFontSize,
        'isBold': effectiveIsBold,
        'showBorder': effectiveShowBorder,
        'borderColor': effectiveBorderColor,
        'bgColor': effectiveBgColor,
      };
    }).toList();

    return <Map<String, dynamic>>[...highlights, ...comments];
  }

  Widget _buildPrintLoadingScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
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
                color: isDark ? Colors.white : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم استئناف العرض تلقائيًا بعد الطباعة',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
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
      final appProvider = context.read<AppProvider>();
      final annotationsJson = _collectAnnotationsForPrint(pdf, appProvider);
      logStage('before PrintService.executePrint');
      await PrintService.executePrint(
        pdf.path,
        settings,
        currentPage: currentPage,
        printJobName: pdf.name,
        annotationsJson: annotationsJson,
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
      logStage('cool-down start (1s)');
      await Future.delayed(const Duration(seconds: 1));
      logStage('cool-down end');

      if (!mounted) return;
      _isPrintingMode = false;
      setState(() {});
      logStage('printing mode disabled (UI structure restored)');

      // 2) Stabilization: allow Flutter to paint post-unmount UI first.
      logStage('stabilization start (500ms)');
      await Future.delayed(const Duration(milliseconds: 500));
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
