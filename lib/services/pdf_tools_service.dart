import 'dart:io';
import 'dart:ui' as ui;
import 'package:syncfusion_flutter_pdf/pdf.dart';

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
    bool fitToPage = true,
  }) async {
    final PdfDocument document = PdfDocument();

    try {
      for (String path in imagePaths) {
        final File file = File(path);
        if (await file.exists()) {
          final List<int> bytes = await file.readAsBytes();
          final PdfBitmap image = PdfBitmap(bytes);

          // Create a page. If fitting to page, use standard A4, otherwise use image size
          PdfPage page;
          if (fitToPage) {
            page = document.pages.add(); // Adds A4 by default
            // Calculate aspect ratio to fit within margins
            final ui.Size pageSize = page.getClientSize();

            // Simple fit logic (contain)
            // Draw image to fit page maintaining aspect ratio could be added here
            // For now, we will just draw it to fill the page or use the rect
            page.graphics.drawImage(
              image,
              ui.Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
            );
          } else {
            // Create page with image dimensions
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
      }

      final List<int> bytes = await document.save();
      final File file = File(outputPath);
      await file.writeAsBytes(bytes);
      return outputPath;
    } catch (e) {
      debugPrint('Error converting images to PDF: $e');
      rethrow;
    } finally {
      document.dispose();
    }
  }
}
