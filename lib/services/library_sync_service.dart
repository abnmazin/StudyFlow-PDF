import 'dart:math';
import '../models/app_user.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySyncService
//
// Every university library file carries its OWN sync code (stored on
// university_files.syncCode and auto-generated at upload/backfill).
//
// That code is the *same* session identifier used by the ordinary local-file
// sync engine (SyncService writes to sync_sessions/{code}/annotations/{hash}),
// which is why library booklets annotate and share identically to any locally
// joined session — no second code space, no separate download bookkeeping.
//
// Auto-connect: opening a booklet from any university account links it to the
// file's sync code with zero user input (no code entry, nothing displayed).
// ─────────────────────────────────────────────────────────────────────────────

class LibrarySyncService {
  const LibrarySyncService._();

  /// The account that owns/manages the university library.
  static const String ownerUsername = 'abnmazin';

  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Generates a fresh 6-char sync code (safe charset, no confusing chars).
  static String generateSyncCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => _chars[rng.nextInt(_chars.length)]).join();
  }

  /// Deterministic fallback code derived from a file hash — used when a file
  /// somehow still has no syncCode yet (e.g. opened before the owner's
  /// backfill), so the session link never breaks.
  static String codeFromHash(String fileHash) {
    final clean = fileHash.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (clean.isEmpty) {
      return 'FILE${DateTime.now().millisecondsSinceEpoch % 1000000}';
    }
    final upper = clean.toUpperCase();
    return upper.length >= 6 ? upper.substring(0, 6) : upper.padRight(6, 'K');
  }

  static bool isOwner(AppUser? user) =>
      user != null &&
      user.username.trim().toLowerCase() == ownerUsername.toLowerCase();
}
