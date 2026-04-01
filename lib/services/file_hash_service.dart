import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class FileHashService {
  /// Calculates SHA-256 hash of file content for accurate file identification.
  /// This is the most reliable method - identical files will always have the same hash,
  /// regardless of filename, location, or when they were copied.
  static Future<String> calculateFileHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes);
      
      debugPrint('📋 [FileHashService] File size: ${bytes.length} bytes | Hash: ${hash.toString().substring(0, 16)}...');
      return hash.toString();
    } catch (e) {
      throw Exception('Error calculating file hash: $e');
    }
  }

  /// Extracts filename and size from a filepath (used for fallback matching).
  static Future<Map<String, dynamic>> getFileMetadata(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final basename = p.basename(filePath);
    final fileSize = await file.length();
    return {
      'filename': basename,
      'size': fileSize,
    };
  }

  /// Calculates SHA-256 of file content for integrity verification (optional).
  static Future<String> calculateContentHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes);
      return hash.toString();
    } catch (e) {
      throw Exception('Error calculating content hash: $e');
    }
  }
}

