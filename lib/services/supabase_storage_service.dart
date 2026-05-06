import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageService {
  SupabaseStorageService({
    String? bucketName,
  }) : bucketName = bucketName ?? _readBucketName();

  final String bucketName;

  SupabaseClient get _client => Supabase.instance.client;

  static String _readBucketName() {
    const fallback = 'media';
    final value = dotenv.maybeGet('SUPABASE_BUCKET_NAME')?.trim() ?? '';
    return value.trim().isEmpty ? fallback : value.trim();
  }

  Future<String?> uploadFile(
    File file, {
    bool isAudio = false,
    bool upsert = false,
  }) async {
    try {
      final extension = path.extension(file.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
      final folder = isAudio ? 'audio' : 'images';
      final filePath = '$folder/$fileName';

      await _client.storage.from(bucketName).upload(
            filePath,
            file,
            fileOptions: FileOptions(upsert: upsert),
          );

      return _client.storage.from(bucketName).getPublicUrl(filePath);
    } catch (error) {
      print('❌ [SupabaseStorage] upload failed: $error');
      return null;
    }
  }
}