import 'dart:io';
import 'package:crypto/crypto.dart';

class FileHashService {
  /// Calculates the SHA-256 hash of a file at the given path.
  static Future<String> calculateFileHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes);
      return hash.toString();
    } catch (e) {
      throw Exception('Error calculating file hash: $e');
    }
  }
}
