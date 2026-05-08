import 'dart:io';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path/path.dart' as p;

class PdfMutationService {
  /// Generates a new unique file path in the SAME directory as [sourceFile].
  /// Strips previous `_studyflow_` suffixes to prevent ever-growing filenames
  /// across multiple successive mutations.
  static File _rollingFile(File sourceFile) {
    final dir = sourceFile.parent;
    final baseName = p.basenameWithoutExtension(sourceFile.path);
    // Remove any prior rolling suffix (e.g. "file_studyflow_111_studyflow_222" → "file")
    final cleanBase = baseName.split('_studyflow_').first;
    final newName =
        '${cleanBase}_studyflow_${DateTime.now().millisecondsSinceEpoch}.pdf';
    return File(p.join(dir.path, newName));
  }

  /// Deletes a page from the PDF locally using Syncfusion.
  /// Writes the result to a NEW rolling file — never touches/deletes the
  /// source file, which may still be held open by pdfrx (errno=32 fix).
  /// [pageIndex] is 0-based.
  static Future<File> deletePageLocally(File pdfFile, int pageIndex) async {
    try {
      final bytes = await pdfFile.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        throw RangeError('Page index $pageIndex out of bounds '
            '(total pages: ${document.pages.count})');
      }

      document.pages.removeAt(pageIndex);
      final List<int> modifiedBytes = await document.save();
      document.dispose();

      final newFile = _rollingFile(pdfFile);
      await newFile.writeAsBytes(modifiedBytes, flush: true);
      return newFile;
    } catch (e) {
      print('❌ [PdfMutationService] Error deleting page: $e');
      rethrow;
    }
  }

  /// Inserts a blank page into the PDF locally using Syncfusion.
  /// Writes the result to a NEW rolling file — never touches/deletes the
  /// source file (errno=32 fix).
  /// [insertIndex] is 0-based.
  static Future<File> insertPageLocally(File pdfFile, int insertIndex) async {
    try {
      final bytes = await pdfFile.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);

      if (insertIndex < 0 || insertIndex > document.pages.count) {
        document.dispose();
        throw RangeError('Insert index $insertIndex out of bounds '
            '(total pages: ${document.pages.count})');
      }

      document.pages.insert(insertIndex);
      final List<int> modifiedBytes = await document.save();
      document.dispose();

      final newFile = _rollingFile(pdfFile);
      await newFile.writeAsBytes(modifiedBytes, flush: true);
      return newFile;
    } catch (e) {
      print('❌ [PdfMutationService] Error inserting page: $e');
      rethrow;
    }
  }
}
