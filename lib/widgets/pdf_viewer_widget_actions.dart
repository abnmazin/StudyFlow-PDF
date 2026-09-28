part of 'pdf_viewer_widget_w.dart';

class _WinMemoryTrimmer {
  _WinMemoryTrimmer._();
  static final _WinMemoryTrimmer _instance = _WinMemoryTrimmer._();
  factory _WinMemoryTrimmer() => _instance;

  late final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  late final int Function() _getCurrentProcess = _kernel32
      .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
  late final bool Function(int) _emptyWorkingSet = _kernel32
      .lookupFunction<Bool Function(IntPtr), bool Function(int)>(
        'K32EmptyWorkingSet',
      );

  int trimsCount = 0;
  Duration lastDuration = Duration.zero;

  void trim({bool telemetry = false}) {
    final handle = _getCurrentProcess();
    final sw = Stopwatch()..start();
    _emptyWorkingSet(handle);
    sw.stop();
    trimsCount++;
    lastDuration = sw.elapsed;
    if (telemetry) {
      debugPrint(
        '[RAM] Windows trim #$trimsCount took ${lastDuration.inMilliseconds} ms',
      );
    }
  }
}

//  UTILITY ACTIONS EXTENSION
// All methods here are extension methods on _PDFViewerWidgetState.
// Being in the same library (via `part of`) gives full access to:
//    `this`   the state instance
//    `setState`, `context`, `mounted`  inherited from State<T>
//    `_isProcessing`, `_pdfController`, etc.  library-private fields

extension _PDFViewerWidgetStateActions on _PDFViewerWidgetState {
  //  Page Operations

  Future<void> _addPage(PdfItem pdf) async {
    if (_isProcessing) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _isProcessing = true);
    try {
      // Add after current page
      int targetPage = 1;
      if (_pdfController.isReady && _pdfController.pageNumber != null) {
        targetPage = _pdfController.pageNumber!;
      } else {
        targetPage = pdf.lastPage ?? 1;
      }
      await context.read<AppProvider>().addPage(
        pdf.id,
        insertAtIndex: targetPage,
      );

      final hash = pdf.fileHash;
      if (mounted && hash != null) {
        SyncService.logMutation(
          '🚀 [SYNC SENDER] Triggering insert_page broadcast for fileHash: $hash, pageIndex: $targetPage',
        );
        await context.read<AppProvider>().broadcastMutation(
          hash,
          'insert_page',
          targetPage,
        );
      }
    } finally {
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _deleteCurrentPage(PdfItem pdf) {
    if (_isProcessing) return;

    // Secure controller access with strict checks
    int pageToDelete = 1;
    if (_pdfController.isReady && _pdfController.pageNumber != null) {
      pageToDelete = _pdfController.pageNumber!;
    } else {
      pageToDelete = pdf.lastPage ?? 1;
    }

    // Show confirmation
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصفحة؟'),
        content: Text(
          'هل أنت متأكد من حذف الصفحة $pageToDelete؟ لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // ignore: invalid_use_of_protected_member
              setState(() => _isProcessing = true);
              try {
                // Page numbers in controller are 1-based, our API expects 0-based index
                await context.read<AppProvider>().deletePage(
                  pdf.id,
                  pageToDelete - 1,
                );

                final hash = pdf.fileHash;
                if (mounted && hash != null) {
                  SyncService.logMutation(
                    '🚀 [SYNC SENDER] Triggering delete_page broadcast for fileHash: $hash, pageIndex: ${pageToDelete - 1}',
                  );
                  await context.read<AppProvider>().broadcastMutation(
                    hash,
                    'delete_page',
                    pageToDelete - 1,
                  );
                }
              } finally {
                // ignore: invalid_use_of_protected_member
                if (mounted) setState(() => _isProcessing = false);
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  //  Bookmark

  void _showAddBookmarkDialog(PdfItem pdf) {
    final controller = TextEditingController();
    final currentPage = _pdfController.pageNumber ?? 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة علامة مرجعية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'الصفحة $currentPage',
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'اسم العلامة المرجعية',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (controller.text.trim().isNotEmpty) {
                  ctx.read<AppProvider>().addBookmark(
                    pdf.id,
                    controller.text.trim(),
                    currentPage,
                  );
                  Navigator.of(ctx).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ctx.read<AppProvider>().addBookmark(
                  pdf.id,
                  controller.text.trim(),
                  currentPage,
                );
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  //  Win32 Memory Trim
  // Calls EmptyWorkingSet via FFI to force Windows to release native heap pages
  // back to the OS. Safe to call from the main thread  it does NOT freeze the UI.
  void _trimWindowsMemory() {
    if (!Platform.isWindows) return;
    try {
      final settings = context.read<AppProvider>().devSettings;
      _WinMemoryTrimmer().trim(telemetry: settings.telemetryEnabled ?? false);
    } catch (e) {
      // Silently ignore  non-critical trim
      debugPrint('Memory trim skipped: $e');
    }
  }

  //  PDF Relayout

  void _requestAutoFit({
    Duration delay = const Duration(milliseconds: 180),
    bool force = false,
  }) {
    if (!_autoFitEnabled && !force) return;
    if (!_pdfController.isReady) return;

    _autoFitDebounce?.cancel();
    _autoFitDebounce = Timer(delay, () {
      _applyAutoFit(force: force);
    });
  }

  void _applyAutoFit({bool force = false}) {
    if ((!_autoFitEnabled && !force) || !_pdfController.isReady || !mounted) {
      return;
    }
    if (_isAutoFitting) return;

    _isAutoFitting = true;
    try {
      final currentPage = _pdfController.pageNumber ?? 1;
      final dynamic controller = _pdfController;

      final dynamic matrix = controller.value;
      final Size? viewSize = controller.viewSize as Size?;
      final double? fitScale = (controller.alternativeFitScale as num?)
          ?.toDouble();

      if (matrix != null && viewSize != null && fitScale != null) {
        final Size basisSize = _lastPdfViewSize ?? viewSize;
        final Offset centerPosition = matrix.calcPosition(basisSize) as Offset;
        final Matrix4 target =
            controller.calcMatrixFor(
                  centerPosition,
                  zoom: fitScale,
                  viewSize: viewSize,
                )
                as Matrix4;
        controller.goTo(target);
      } else {
        // Fallback: keep page stable even if fit APIs are unavailable.
        _pdfController.goToPage(pageNumber: currentPage);
      }
    } catch (_) {
      final currentPage = _pdfController.pageNumber ?? 1;
      _pdfController.goToPage(pageNumber: currentPage);
    } finally {
      _isAutoFitting = false;
    }
  }

  void _forcePdfRelayout() {
    // Wait for panel animation/layout to settle, then fit the current page.
    _requestAutoFit(delay: const Duration(milliseconds: 320), force: true);
  }
}
