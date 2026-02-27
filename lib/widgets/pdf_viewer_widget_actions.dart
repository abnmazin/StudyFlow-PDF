part of 'pdf_viewer_widget_w.dart';

//  UTILITY ACTIONS EXTENSION 
// All methods here are extension methods on _PDFViewerWidgetState.
// Being in the same library (via `part of`) gives full access to:
//    `this`   the state instance
//    `setState`, `context`, `mounted`  inherited from State<T>
//    `_isProcessing`, `_pdfController`, etc.  library-private fields

extension _PDFViewerWidgetStateActions on _PDFViewerWidgetState {
  //  Page Operations 

  void _addPage(PdfItem pdf) {
    if (_isProcessing) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _isProcessing = true);

    // Add after current page
    int targetPage = 1;
    if (_pdfController.isReady && _pdfController.pageNumber != null) {
      targetPage = _pdfController.pageNumber!;
    } else {
      targetPage = pdf.lastPage ?? 1;
    }
    context.read<AppProvider>().addPage(pdf.id, insertAtIndex: targetPage);
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
        title: const Text('Delete Page?'),
        content: Text(
          'Are you sure you want to delete page $pageToDelete? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // ignore: invalid_use_of_protected_member
              setState(() => _isProcessing = true);
              // Page numbers in controller are 1-based, our API expects 0-based index
              context.read<AppProvider>().deletePage(pdf.id, pageToDelete - 1);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
        title: const Text('Add Bookmark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Page $currentPage',
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Bookmark name',
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
            child: const Text('Cancel'),
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
            child: const Text('Add'),
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
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getCurrentProcess = kernel32
          .lookupFunction<IntPtr Function(), int Function()>(
            'GetCurrentProcess',
          );
      final emptyWorkingSet = kernel32
          .lookupFunction<Bool Function(IntPtr), bool Function(int)>(
            'K32EmptyWorkingSet',
          );
      final handle = getCurrentProcess();
      emptyWorkingSet(handle);
    } catch (e) {
      // Silently ignore  non-critical trim
      debugPrint('Memory trim skipped: $e');
    }
  }

  //  PDF Relayout 

  void _forcePdfRelayout() {
    if (!_pdfController.isReady) return;
    final currentPage = _pdfController.pageNumber ?? 1;
    // VIEWPORT ADAPTER: Wait 300ms for sidebar animation to complete
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _pdfController.isReady) {
        _pdfController.goToPage(pageNumber: currentPage);
      }
    });
  }
}