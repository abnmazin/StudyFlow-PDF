import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:image/image.dart' as img;

import 'package:flutter/foundation.dart';

class PdfToolsService {
  // 1. MERGE PDFs
  // Merges multiple PDF files into one output file.
  static Future<String?> mergePdfs(
    List<String> inputPaths,
    String outputPath,
  ) async {
    final PdfDocument outputDocument = PdfDocument();

    try {
      for (String path in inputPaths) {
        final File file = File(path);
        if (await file.exists()) {
          final List<int> bytes = await file.readAsBytes();
          final PdfDocument inputDocument = PdfDocument(inputBytes: bytes);

          // Import pages from input to output
          // Using strict template import for best compatibility
          for (int i = 0; i < inputDocument.pages.count; i++) {
            outputDocument.pages.add().graphics.drawPdfTemplate(
              inputDocument.pages[i].createTemplate(),
              const ui.Offset(0, 0),
            );
          }
          inputDocument.dispose();
        }
      }

      final List<int> bytes = await outputDocument.save();
      final File file = File(outputPath);
      await file.writeAsBytes(bytes);
      return outputPath;
    } catch (e) {
      debugPrint('Error merging PDFs: $e');
      rethrow;
    } finally {
      outputDocument.dispose();
    }
  }

  // 2. IMAGES TO PDF
  // Converts a list of images to a PDF document.
  static Future<String?> imagesToPdf(
    List<String> imagePaths,
    String outputPath, {
    bool fitToPage = false,
    int jpegQuality = 78,
    int maxImageDimension = 0,
  }) async {
    try {
      await Isolate.run(() {
        final PdfDocument document = PdfDocument();
        try {
          for (final path in imagePaths) {
            final file = File(path);
            if (!file.existsSync()) continue;

            final Uint8List bytes = file.readAsBytesSync();
            final Uint8List preparedBytes = _compressImageBytes(
              bytes,
              jpegQuality: jpegQuality,
              maxImageDimension: maxImageDimension,
            );
            final PdfBitmap image = PdfBitmap(preparedBytes);

            PdfPage page;
            if (fitToPage) {
              page = document.pages.add();
              final ui.Size pageSize = page.getClientSize();
              page.graphics.drawImage(
                image,
                ui.Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
              );
            } else {
              document.pageSettings.size = ui.Size(
                image.width.toDouble(),
                image.height.toDouble(),
              );
              document.pageSettings.margins.all = 0;
              page = document.pages.add();
              page.graphics.drawImage(
                image,
                ui.Rect.fromLTWH(
                  0,
                  0,
                  image.width.toDouble(),
                  image.height.toDouble(),
                ),
              );
            }
          }

          final List<int> bytes = document.saveSync();
          File(outputPath).writeAsBytesSync(bytes, flush: true);
        } finally {
          document.dispose();
        }
      });

      return outputPath;
    } catch (e) {
      debugPrint('Error converting images to PDF: $e');
      rethrow;
    }
  }

  static Uint8List _compressImageBytes(
    Uint8List inputBytes, {
    required int jpegQuality,
    required int maxImageDimension,
  }) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      return inputBytes;
    }

    img.Image processed = decoded;

    if (maxImageDimension > 0) {
      final longestSide =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longestSide > maxImageDimension) {
        if (decoded.width >= decoded.height) {
          processed = img.copyResize(
            decoded,
            width: maxImageDimension,
            interpolation: img.Interpolation.linear,
          );
        } else {
          processed = img.copyResize(
            decoded,
            height: maxImageDimension,
            interpolation: img.Interpolation.linear,
          );
        }
      }
    }

    final safeQuality = jpegQuality.clamp(35, 95);
    final encoded = img.encodeJpg(processed, quality: safeQuality);
    return Uint8List.fromList(encoded);
  }
}
