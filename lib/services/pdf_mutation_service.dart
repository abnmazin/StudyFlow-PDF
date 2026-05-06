import 'dart:io';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PdfMutationService {
  /// Deletes a page from the PDF locally using Syncfusion.
  /// Returns the newly saved File.
  /// [pageIndex] is 0-based.
  static Future<File> deletePageLocally(File pdfFile, int pageIndex) async {
    try {
      final Uint8List bytes = await pdfFile.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        document.dispose();
        throw RangeError('Page index out of bounds');
      }

      // Remove the page
      document.pages.removeAt(pageIndex);

      // Save the modified document
      final List<int> modifiedBytes = await document.save();
      document.dispose();

      // Write to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(tempDir.path, 'temp_${DateTime.now().millisecondsSinceEpoch}.pdf'));
      await tempFile.writeAsBytes(modifiedBytes, flush: true);

      // Replace the original file
      await pdfFile.delete();
      final newFile = await tempFile.copy(pdfFile.path);
      await tempFile.delete();

      return newFile;
    } catch (e) {
      print('❌ [PdfMutationService] Error deleting page: $e');
      rethrow;
    }
  }

  /// Inserts a blank page into the PDF locally using Syncfusion.
  static Future<File> insertPageLocally(File pdfFile, int insertIndex) async {
    try {
      final Uint8List bytes = await pdfFile.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      if (insertIndex < 0 || insertIndex > document.pages.count) {
        document.dispose();
        throw RangeError('Insert index out of bounds');
      }

      // Insert the page
      document.pages.insert(insertIndex);

      // Save the modified document
      final List<int> modifiedBytes = await document.save();
      document.dispose();

      // Write to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(
          tempDir.path, 'temp_${DateTime.now().millisecondsSinceEpoch}.pdf'));
      await tempFile.writeAsBytes(modifiedBytes, flush: true);

      // Replace the original file
      await pdfFile.delete();
      final newFile = await tempFile.copy(pdfFile.path);
      await tempFile.delete();

      return newFile;
    } catch (e) {
      print('❌ [PdfMutationService] Error inserting page: $e');
      rethrow;
    }
  }
}
