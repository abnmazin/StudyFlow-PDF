import 'dart:math';

class SyncNamingUtils {
  static const String sessionFallback = 'درس جديد';
  static const String bundleFallback = 'حزمة دراسية جديدة';

  /// Cleans a PDF filename into a user-friendly display name.
  static String generateSmartName(String filename, {bool isBundle = false}) {
    if (filename.isEmpty) return isBundle ? bundleFallback : sessionFallback;

    String cleaned = filename;

    // 1. Remove .pdf extension (case insensitive)
    cleaned = cleaned.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

    // 2. Remove trailing copy markers like (1), (2)
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(\d+\)$'), '');

    // 3. Replace underscores and hyphens with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[_\\-]'), ' ');

    // 4. Collapse repeated spaces and trim
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty) return isBundle ? bundleFallback : sessionFallback;

    return cleaned;
  }

  /// Suggests a 4-12 character code based on a name.
  static String suggestCodeFromName(String name) {
    if (name.isEmpty) return '';

    // Uppercase
    String code = name.toUpperCase();

    // Replace invalid characters with '-'
    // Allowed: A-Z, 0-9, _, -
    code = code.replaceAll(RegExp(r'[^A-Z0-9_-]'), '-');

    // Collapse multiple separators
    code = code.replaceAll(RegExp(r'[-_]{2,}'), '-');

    // Trim separators from ends
    code = code.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');

    // Cut to max 12 chars
    if (code.length > 12) {
      code = code.substring(0, 12);
      // Re-trim in case we cut into a separator
      code = code.replaceAll(RegExp(r'[-_]+$'), '');
    }

    if (code.length < 4) return '';

    return code;
  }

  /// Checks if a custom code follows the rules: A-Z, 0-9, -, _, length 4-12.
  static bool isValidCode(String code) {
    final regex = RegExp(r'^[A-Z0-9_-]{4,12}$');
    return regex.hasMatch(code);
  }

  /// Original random code generator logic preserved for fallback.
  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static String generateRandomCode(int length) {
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => _chars[rng.nextInt(_chars.length)],
    ).join();
  }
}
