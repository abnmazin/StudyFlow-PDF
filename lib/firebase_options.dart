import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Secure Firebase options loaded from environment variables.
///
/// Required keys in .env:
/// FIREBASE_API_KEY
/// FIREBASE_PROJECT_ID
/// FIREBASE_APP_ID_WINDOWS
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'FirebaseOptions are not configured for web in this app.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'FirebaseOptions are not configured for ${defaultTargetPlatform.name}.',
        );
    }
  }

  static FirebaseOptions get windows => FirebaseOptions(
    apiKey: _require('FIREBASE_API_KEY'),
    appId: _require('FIREBASE_APP_ID_WINDOWS'),
    projectId: _require('FIREBASE_PROJECT_ID'),
    messagingSenderId: _optional('FIREBASE_MESSAGING_SENDER_ID', '000000000000'),
  );

  static String _require(String key) {
    final value = dotenv.maybeGet(key)?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError('Missing required .env key: $key');
    }
    return value;
  }

  static String _optional(String key, String fallback) {
    final value = dotenv.maybeGet(key)?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }
}
