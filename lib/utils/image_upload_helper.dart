import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../services/supabase_storage_service.dart';

/// Asks the reader for one image, uploads it, and returns its public URL.
///
/// Returns null when nothing was picked — the dialog was closed — which is not
/// a failure and has nothing to report. A pick that happened but could not be
/// uploaded throws instead, so the caller can tell "cancelled" apart from
/// "failed": a publish bar that silently does nothing on a failed upload is a
/// button that appears broken.
///
/// The same path `DraggableTextWidget._pickAndUploadImage` walks for an image
/// attached to a note, lifted here so the announcements bar does not grow a
/// second copy of it. Two pickers because one is not enough: `image_picker`'s
/// desktop path was failing in the Windows runner, so a desktop pick goes
/// through `FilePicker`'s native dialog and only the mobile targets go through
/// the gallery plugin.
///
/// `defaultTargetPlatform` rather than `Platform.isWindows`: the same answer,
/// readable from `flutter/foundation`, and it does not need `dart:io` to be
/// asked a question about the operating system.
Future<String?> pickAndUploadImage() async {
  final path = await _pickImagePath();
  if (path == null || path.isEmpty) return null;

  final url = await SupabaseStorageService().uploadFile(
    File(path),
    isAudio: false,
  );
  // `uploadFile` reports the storage error to the console and answers null, so
  // the sentence the reader sees has to be written here.
  if (url == null) throw StateError('تعذّر رفع الصورة، حاول مرة أخرى');
  return url;
}

Future<String?> _pickImagePath() async {
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }

  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 70,
  );
  return picked?.path;
}
