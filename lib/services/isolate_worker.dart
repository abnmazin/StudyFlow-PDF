import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PURE DART WORKER - NO FIREBASE, NO PLATFORM CHANNELS, NO FLUTTER UI
/// This file is safe to load in a background isolate.

/// Computes file hash and page count sequentially in a background isolate.
Future<Map<String, dynamic>> computePdfMetadataIsolate(String path) async {
  final file = File(path);
  if (!file.existsSync()) return {};
  
  try {
    // 1. Calculate Hash (Pure Dart)
    final bytes = file.readAsBytesSync();
    final hash = sha256.convert(bytes).toString();
    
    // 2. Page Count (Syncfusion is Pure Dart in this context)
    final doc = PdfDocument(inputBytes: bytes);
    final count = doc.pages.count;
    doc.dispose();

    return {
      'hash': hash,
      'pageCount': count,
    };
  } catch (e) {
    return {};
  }
}
