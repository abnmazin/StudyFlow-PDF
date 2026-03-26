import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;
import 'dart:convert';
import 'package:pdf/pdf.dart'; // هذا السطر سيحل مشكلة الـ Undefined class
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/print_settings.dart';
import '../utils/print_utils.dart';

class PrintService {
  static Directory get _diagnosticsDir => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}studyflow_print_diagnostics',
  );

  static File get _diagnosticsLog =>
      File('${_diagnosticsDir.path}${Platform.pathSeparator}print.log');

  static File get _pendingMarker => File(
    '${_diagnosticsDir.path}${Platform.pathSeparator}pending_print.json',
  );

  static Future<void> _diagWrite(String line, {required bool enabled}) async {
    if (!enabled) return;
    await _diagnosticsDir.create(recursive: true);
    final ts = DateTime.now().toIso8601String();
    await _diagnosticsLog.writeAsString(
      '[$ts] $line\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<void> _writePendingMarker(Map<String, dynamic> data) async {
    await _diagnosticsDir.create(recursive: true);
    await _pendingMarker.writeAsString(jsonEncode(data), flush: true);
  }

  static Future<void> _clearPendingMarker() async {
    if (await _pendingMarker.exists()) {
      await _pendingMarker.delete();
    }
  }

  static Future<bool> _tryWindowsShellPrint(String filePath) async {
    final escapedPath = filePath.replaceAll("'", "''");
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Start-Process -FilePath '$escapedPath' -Verb Print",
    ]);
    return result.exitCode == 0;
  }

  static Future<void> _openFileInWindowsDefaultApp(String filePath) async {
    await Process.start('explorer.exe', [filePath]);
  }

  static String get diagnosticsLogPath => _diagnosticsLog.path;

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
    List<Map<String, dynamic>> annotationsJson = const [],
  }) async {
    final sw = Stopwatch()..start();
    Future<void> logTiming(String stage) async {
      final msg = '[PrintServiceTiming] +${sw.elapsedMilliseconds}ms $stage';
      debugPrint(msg);
      await _diagWrite(msg, enabled: settings.enableDiagnostics);
    }

    await _diagWrite(
      'START executePrint source=$sourcePdfPath destination=${settings.destination.name} runMode=${settings.runMode.name} copies=${settings.copies} range=${settings.pageRange} parity=${settings.parity} reverse=${settings.reverse} orientation=${settings.orientation.name} color=${settings.colorMode.name}',
      enabled: settings.enableDiagnostics,
    );
    await logTiming('start executePrint');

    if (await _pendingMarker.exists()) {
      final marker = await _pendingMarker.readAsString();
      await _diagWrite(
        'WARNING previous print ended unexpectedly. Pending marker=$marker',
        enabled: settings.enableDiagnostics,
      );
    }

    final file = File(sourcePdfPath);
    if (!await file.exists()) {
      await _diagWrite(
        'ERROR source PDF missing at $sourcePdfPath',
        enabled: settings.enableDiagnostics,
      );
      throw Exception('Source PDF not found: $sourcePdfPath');
    }

    final sourceBytes = await file.readAsBytes();
    await logTiming('source bytes loaded (${sourceBytes.length})');
    await _diagWrite(
      'Loaded source bytes=${sourceBytes.length}',
      enabled: settings.enableDiagnostics,
    );

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
        annotationsJson: annotationsJson,
      ),
    );
    await logTiming('pdf processed in isolate (${processedBytes.length})');

    await _diagWrite(
      'PDF processed bytes=${processedBytes.length} elapsedMs=${sw.elapsedMilliseconds}',
      enabled: settings.enableDiagnostics,
    );

    if (settings.runMode == PrintRunMode.preprocessOnly) {
      await _diagWrite(
        'RUNMODE preprocessOnly completed successfully. No OS print dialog opened.',
        enabled: settings.enableDiagnostics,
      );
      return;
    }

    if (settings.runMode == PrintRunMode.preprocessAndSaveDebugPdf) {
      final outputPath =
          settings.debugOutputPath ??
          '${_diagnosticsDir.path}${Platform.pathSeparator}debug_print_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outputPath).writeAsBytes(processedBytes);
      await _diagWrite(
        'RUNMODE preprocessAndSaveDebugPdf wrote file=$outputPath',
        enabled: settings.enableDiagnostics,
      );
      return;
    }

    if (settings.destination == PrintDestination.pdfFile) {
      if (settings.outputPath == null || settings.outputPath!.isEmpty) {
        await _diagWrite(
          'ERROR output path missing for Save as PDF',
          enabled: settings.enableDiagnostics,
        );
        throw Exception('Output path is required for Save as PDF');
      }
      await File(settings.outputPath!).writeAsBytes(processedBytes);
      await logTiming('saved as PDF file');
      await _diagWrite(
        'Saved PDF file to ${settings.outputPath!}',
        enabled: settings.enableDiagnostics,
      );
    } else {
      if (Platform.isWindows) {
        await logTiming('windows safe-print path selected');

        final tempPath =
            '${_diagnosticsDir.path}${Platform.pathSeparator}print_job_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(tempPath).writeAsBytes(processedBytes, flush: true);
        await logTiming('windows temp PDF written: $tempPath');

        final printed = await _tryWindowsShellPrint(tempPath);
        if (printed) {
          await _diagWrite(
            'Windows shell print dispatched successfully for $tempPath',
            enabled: settings.enableDiagnostics,
          );
          await logTiming('windows shell print dispatched');
        } else {
          await _diagWrite(
            'Windows shell print verb failed, opening file in default viewer: $tempPath',
            enabled: settings.enableDiagnostics,
          );
          await logTiming('windows shell print failed; opening file');
          await _openFileInWindowsDefaultApp(tempPath);
        }

        await _clearPendingMarker();
        sw.stop();
        await logTiming('end executePrint total=${sw.elapsedMilliseconds}ms');
        await _diagWrite(
          'END executePrint totalElapsedMs=${sw.elapsedMilliseconds}',
          enabled: settings.enableDiagnostics,
        );
        return;
      }

      // 1. تسجيل العملية في سجل التشخيص
      await _writePendingMarker({
        'createdAt': DateTime.now().toIso8601String(),
        'sourcePdfPath': sourcePdfPath,
        'printJobName': printJobName,
        'destination': settings.destination.name,
        'runMode': settings.runMode.name,
      });

      await _diagWrite(
        'Attempting Direct Printing to avoid OS Dialog Crash',
        enabled: settings.enableDiagnostics,
      );

      try {
        // 2. جلب قائمة الطابعات المتاحة في النظام
        final printers = await Printing.listPrinters();
        await logTiming('printers listed (${printers.length})');
        
        // 3. البحث عن الطابعة الافتراضية
        Printer? targetPrinter;
        if (printers.isNotEmpty) {
          try {
            targetPrinter = printers.firstWhere((p) => p.isDefault);
          } catch (_) {
            targetPrinter = printers.first; // إذا لم توجد افتراضية، خذ الأولى
          }
        }

        if (targetPrinter != null) {
          await _diagWrite(
            'Sending directly to printer: ${targetPrinter.name}',
            enabled: settings.enableDiagnostics,
          );

          // 4. الطباعة الصامتة (Direct Print) - بدون نافذة ويندوز
          await Printing.directPrintPdf(
            printer: targetPrinter,
            // نمرر البيانات مباشرة بشكل متزامن (بدون async)
            onLayout: (PdfPageFormat format) => processedBytes,
            name: printJobName,
            dynamicLayout: false,
          );
          await logTiming('directPrintPdf completed');
          
          await _clearPendingMarker();
          await _diagWrite(
            'Direct print job sent successfully',
            enabled: settings.enableDiagnostics,
          );
        } else {
          throw Exception('لم يتم العثور على طابعة متصلة بالنظام');
        }
      } catch (e) {
        await logTiming('directPrintPdf failed, fallback to layoutPdf');
        await _diagWrite(
          'Direct Print Failed: $e. Falling back to layoutPdf...',
          enabled: settings.enableDiagnostics,
        );
        
        // Fallback: إذا فشلت الطباعة المباشرة، نعود للطريقة التقليدية كخيار أخير
        await Printing.layoutPdf(
          onLayout: (_) => processedBytes, // بدون async
          name: printJobName,
          dynamicLayout: false,
        );
        await logTiming('layoutPdf completed');
      }
    }

    sw.stop();
    await logTiming('end executePrint total=${sw.elapsedMilliseconds}ms');
    await _diagWrite(
      'END executePrint totalElapsedMs=${sw.elapsedMilliseconds}',
      enabled: settings.enableDiagnostics,
    );
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

    final List<Map<String, dynamic>> annotations = args.annotationsJson;

    // ── Build output document ─────────────────────────────────────────────────
    final sf.PdfDocument output = sf.PdfDocument();

    for (final pageNum in pageNums) {
      final sf.PdfPage srcPage = source.pages[pageNum - 1];
      final Size srcSize = srcPage.size; // dart:ui Size
      final List<Map<String, dynamic>> pageAnnotations = annotations
        .where((a) => (a['page'] as num?)?.toInt() == pageNum)
        .toList();
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
        _drawFlattenedAnnotations(g, pageAnnotations);
      } else if (!wantLandscape && !srcIsPortrait) {
        // Landscape → Portrait: rotate +90° with compensating translation
        g.translateTransform(srcSize.width, 0);
        g.rotateTransform(90);
        g.drawPdfTemplate(
          template,
          origin,
          Size(srcSize.width, srcSize.height),
        );
        _drawFlattenedAnnotations(g, pageAnnotations);
      } else {
        // No rotation — same orientation, just blit the template
        g.drawPdfTemplate(
          template,
          origin,
          Size(srcSize.width, srcSize.height),
        );
        _drawFlattenedAnnotations(g, pageAnnotations);
      }

      g.restore();
    }

    final List<int> outBytes = output.saveSync();
    source.dispose();
    output.dispose();

    return Uint8List.fromList(outBytes);
  }

  static void _drawFlattenedAnnotations(
    sf.PdfGraphics g,
    List<Map<String, dynamic>> pageAnnotations,
  ) {
    for (final a in pageAnnotations) {
      final kind = (a['annotationKind'] ?? '').toString();
      if (kind == 'comment') {
        _drawCommentAnnotation(g, a);
      } else {
        _drawHighlightAnnotation(g, a);
      }
    }
  }

  static void _drawHighlightAnnotation(
    sf.PdfGraphics g,
    Map<String, dynamic> a,
  ) {
    final type = (a['type'] ?? '').toString().toLowerCase();
    final strokeWidth = _toDouble(a['strokeWidth'], 2.0).clamp(0.5, 64.0);
    final strokeColor = _pdfColorFromArgb(
      a['color'] as int? ?? 0xFF000000,
      opacity: 1.0,
    );
    final fillColor = _pdfColorFromArgb(
      (a['backgroundColor'] as int?) ?? (a['color'] as int? ?? 0xFF000000),
      opacity: 0.12,
    );
    final pen = sf.PdfPen(strokeColor, width: strokeWidth);
    final fillBrush = sf.PdfSolidBrush(fillColor);

    final rects = (a['rects'] as List?)?.cast<Map>();
    if ((type.contains('highlight') || type.contains('text')) &&
        rects != null &&
        rects.isNotEmpty) {
      for (final r in rects) {
        final left = _toDouble(r['L']);
        final top = _toDouble(r['T']);
        final right = _toDouble(r['R']);
        final bottom = _toDouble(r['B']);
        final rect = Rect.fromLTRB(left, top, right, bottom);
        g.drawRectangle(bounds: rect, brush: sf.PdfSolidBrush(_pdfColorFromArgb(
          a['color'] as int? ?? 0xFF000000,
          opacity: 0.45,
        )));
      }
      return;
    }

    final path = (a['path'] as List?)?.cast<Map>();
    if (path == null || path.length < 2) return;

    final points = path
        .map((p) => Offset(_toDouble(p['dx']), _toDouble(p['dy'])))
        .toList();
    if (points.length < 2) return;

    if (type.contains('rectangle')) {
      final rect = Rect.fromPoints(points.first, points.last);
      g.drawRectangle(bounds: rect, brush: fillBrush, pen: pen);
      return;
    }

    if (type.contains('circle')) {
      final rect = Rect.fromPoints(points.first, points.last);
      g.drawEllipse(bounds: rect, brush: fillBrush, pen: pen);
      return;
    }

    if (type.contains('arrow')) {
      final p1 = points.first;
      final p2 = points.last;
      g.drawLine(pen, p1, p2);

      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final mag = (dx * dx + dy * dy);
      if (mag < 0.0001) return;
      final len = mag.sqrt();
      final ux = dx / len;
      final uy = dy / len;
      final headLen = (10.0 + strokeWidth * 2).clamp(8.0, 24.0);
      final wing = headLen * 0.4;

      final bx = p2.dx - ux * headLen;
      final by = p2.dy - uy * headLen;
      final wx = -uy * wing;
      final wy = ux * wing;

      g.drawLine(pen, p2, Offset(bx + wx, by + wy));
      g.drawLine(pen, p2, Offset(bx - wx, by - wy));
      return;
    }

    final drawPen = type.contains('highlight')
        ? sf.PdfPen(
            _pdfColorFromArgb(a['color'] as int? ?? 0xFF000000, opacity: 0.55),
            width: (strokeWidth * 1.4).clamp(0.5, 96.0),
          )
        : pen;
    for (var i = 1; i < points.length; i++) {
      g.drawLine(drawPen, points[i - 1], points[i]);
    }
  }

  static void _drawCommentAnnotation(
    sf.PdfGraphics g,
    Map<String, dynamic> a,
  ) {
    final content = (a['content'] ?? '').toString();
    if (content.trim().isEmpty) return;

    final x = _toDouble(a['dx']);
    final y = _toDouble(a['dy']);
    final fontSize = _toDouble(a['fontSize'], 14.0).clamp(6.0, 128.0);
    final isBold = a['isBold'] == true;
    final showBorder = a['showBorder'] != false;
    final textColor = _pdfColorFromArgb(a['color'] as int? ?? 0xFF000000);
    final borderColor = _pdfColorFromArgb(a['borderColor'] as int? ?? 0xFF000000);
    final bgColor = _pdfColorFromArgb(a['bgColor'] as int? ?? 0xFFFEF3C7);

    final font = sf.PdfStandardFont(
      sf.PdfFontFamily.helvetica,
      fontSize,
      style: isBold ? sf.PdfFontStyle.bold : sf.PdfFontStyle.regular,
    );

    final textSize = font.measureString(content);
    const padding = 4.0;
    final bounds = Rect.fromLTWH(
      x,
      y,
      textSize.width + (padding * 2),
      textSize.height + (padding * 2),
    );

    g.drawRectangle(bounds: bounds, brush: sf.PdfSolidBrush(bgColor));
    if (showBorder) {
      g.drawRectangle(
        bounds: bounds,
        pen: sf.PdfPen(borderColor, width: 1),
      );
    }

    g.drawString(
      content,
      font,
      brush: sf.PdfSolidBrush(textColor),
      bounds: Rect.fromLTWH(
        x + padding,
        y + padding,
        textSize.width,
        textSize.height,
      ),
    );
  }

  static double _toDouble(dynamic v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static sf.PdfColor _pdfColorFromArgb(int argb, {double opacity = 1.0}) {
    final a = (((argb >> 24) & 0xFF) / 255.0) * opacity.clamp(0.0, 1.0);
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;

    // PdfColor in this package path is opaque; blend alpha over white.
    final br = (r * a + 255 * (1 - a)).round().clamp(0, 255);
    final bg = (g * a + 255 * (1 - a)).round().clamp(0, 255);
    final bb = (b * a + 255 * (1 - a)).round().clamp(0, 255);
    return sf.PdfColor(br, bg, bb);
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
  final List<Map<String, dynamic>> annotationsJson;

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
    required this.annotationsJson,
  });
}
