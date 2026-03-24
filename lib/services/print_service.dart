import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/print_settings.dart';
import '../utils/print_utils.dart';

class PrintService {
  /// Single entry point for the print pipeline.
  ///
  /// 1. Loads [sourcePdfPath].
  /// 2. Filters + reorients pages via a `compute` isolate.
  /// 3. Routes the resulting bytes to the OS printer or a PDF file.
  static Future<void> executePrint(
    String sourcePdfPath,
    PrintSettings settings, {
    int currentPage = 1,
    String printJobName = 'Document',
  }) async {
    final file = File(sourcePdfPath);
    if (!await file.exists()) {
      throw Exception('Source PDF not found: $sourcePdfPath');
    }

    final sourceBytes = await file.readAsBytes();
    final processedBytes = await compute(
      _processPdfIsolate,
      _ProcessArgs(
        sourceBytes: sourceBytes,
        currentPage: currentPage,
        destinationIndex: settings.destination.index,
        outputPath: settings.outputPath,
        pageRange: settings.pageRange,
        parity: settings.parity,
        reverse: settings.reverse,
        copies: settings.copies,
        orientationIndex: settings.orientation.index,
        colorModeIndex: settings.colorMode.index,
      ),
    );

    if (settings.destination == PrintDestination.pdfFile) {
      if (settings.outputPath == null || settings.outputPath!.isEmpty) {
        throw Exception('Output path is required for Save as PDF');
      }
      await File(settings.outputPath!).writeAsBytes(processedBytes);
    } else {
      await Printing.layoutPdf(
        onLayout: (_) async => processedBytes,
        name: printJobName,
      );
    }
  }

  // ── Isolate entry point ────────────────────────────────────────────────────

  // NOTE: This function runs in a separate isolate, so it cannot reference any
  // Flutter widget state. Only dart:ui primitives and Syncfusion PDF are used.
  static Uint8List _processPdfIsolate(_ProcessArgs args) {
    final sf.PdfDocument source = sf.PdfDocument(inputBytes: args.sourceBytes);
    final int total = source.pages.count;

    final settings = PrintSettings(
      destination: PrintDestination.values[args.destinationIndex],
      outputPath: args.outputPath,
      pageRange: args.pageRange,
      parity: args.parity,
      reverse: args.reverse,
      copies: args.copies,
      orientation: PrintOrientation.values[args.orientationIndex],
      colorMode: PrintColorMode.values[args.colorModeIndex],
    );

    // ── Resolve page numbers (1-indexed) ─────────────────────────────────────
    List<int> basePages;
    if (settings.pageRange == 'all') {
      basePages = List.generate(total, (i) => i + 1);
    } else if (settings.pageRange == 'current') {
      basePages = [args.currentPage.clamp(1, total)];
    } else {
      // Custom range (e.g., "1-3, 5")
      basePages = PrintUtils.parsePageRange(settings.pageRange, total);
    }

    final List<int> pageNums = PrintUtils.applyParityAndReverse(
      basePages,
      settings.parity,
      settings.reverse,
    );

    // ── Build output document ─────────────────────────────────────────────────
    final sf.PdfDocument output = sf.PdfDocument();

    for (final pageNum in pageNums) {
      final sf.PdfPage srcPage = source.pages[pageNum - 1];
      final Size srcSize = srcPage.size; // dart:ui Size
      final bool srcIsPortrait = srcSize.height >= srcSize.width;
      final bool wantLandscape =
          settings.orientation == PrintOrientation.landscape;
      final bool needsRotation = wantLandscape == srcIsPortrait;

      // Add a section so we can set per-page dimensions
      final sf.PdfSection section = output.sections!.add();
      section.pageSettings.margins.all = 0;

      if (needsRotation) {
        // Swap width ↔ height for the output page
        section.pageSettings.size = Size(srcSize.height, srcSize.width);
      } else {
        section.pageSettings.size = Size(srcSize.width, srcSize.height);
      }

      final sf.PdfPage outPage = section.pages.add();
      final sf.PdfGraphics g = outPage.graphics;
      final sf.PdfTemplate template = srcPage.createTemplate();
      const Offset origin = Offset(0, 0);

      g.save();

      if (wantLandscape && srcIsPortrait) {
        // Portrait → Landscape: rotate -90° with compensating translation
        g.translateTransform(0, srcSize.height);
        g.rotateTransform(-90);
        g.drawPdfTemplate(
          template,
          origin,
          Size(srcSize.width, srcSize.height),
        );
      } else if (!wantLandscape && !srcIsPortrait) {
        // Landscape → Portrait: rotate +90° with compensating translation
        g.translateTransform(srcSize.width, 0);
        g.rotateTransform(90);
        g.drawPdfTemplate(
          template,
          origin,
          Size(srcSize.width, srcSize.height),
        );
      } else {
        // No rotation — same orientation, just blit the template
        g.drawPdfTemplate(
          template,
          origin,
          Size(srcSize.width, srcSize.height),
        );
      }

      g.restore();
    }

    final List<int> outBytes = output.saveSync();
    source.dispose();
    output.dispose();

    return Uint8List.fromList(outBytes);
  }
}

// ── Isolate payload ────────────────────────────────────────────────────────────

class _ProcessArgs {
  final Uint8List sourceBytes;
  final int currentPage;
  final int destinationIndex;
  final String? outputPath;
  final String pageRange;
  final String parity;
  final bool reverse;
  final int copies;
  final int orientationIndex;
  final int colorModeIndex;

  const _ProcessArgs({
    required this.sourceBytes,
    required this.currentPage,
    required this.destinationIndex,
    required this.outputPath,
    required this.pageRange,
    required this.parity,
    required this.reverse,
    required this.copies,
    required this.orientationIndex,
    required this.colorModeIndex,
  });
}
