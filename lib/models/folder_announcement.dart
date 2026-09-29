import 'package:cloud_firestore/cloud_firestore.dart';

/// One note a professor posted to a university-library folder.
///
/// Firestore path: `university_folders/{folderId}/announcements/{announcementId}`
///
///   title      String     short headline, shown as the card's bold line.
///                         May be empty: a photo of the week's schedule needs
///                         no headline, so an empty title is a finished note's
///                         shape, not a half-filled draft
///   body       String     the note itself. May be empty for the same reason
///   imageUrl   String?    public URL of one image in Supabase Storage, or
///                         null. Firestore holds the link and not the bytes:
///                         a document caps at 1 MiB and a photo does not fit
///   authorName String     display name captured at write time, not looked up
///                         later: a profile rename must not rewrite history,
///                         and a deleted profile must not blank the author
///   authorUid  String     who wrote it, so a lecturer can delete their own
///                         without holding admin. Also what the rules compare
///                         against, which is why it is stored and not derived
///   createdAt  Timestamp  server time, never a client clock
///
/// Nested under the folder rather than a flat `folder_announcements` collection
/// with a `folderId` field: every read is "the announcements of one folder", so
/// the folder id is a path segment the rules can check with `get()` on the
/// parent, and no composite index is needed for the listing.
class FolderAnnouncement {
  final String id;
  final String title;
  final String body;

  /// Public URL of the image attached to this note, or null for a text-only
  /// one. The bytes live in Supabase Storage (see `SupabaseStorageService`),
  /// and this is the link to them.
  final String? imageUrl;

  final String authorName;
  final String authorUid;

  /// When it was posted.
  ///
  /// Non-null, with `DateTime.now()` standing in for a missing or not-yet-
  /// acknowledged timestamp. A pending write echoes back locally with
  /// `createdAt == null` — `FieldValue.serverTimestamp()` resolves on the
  /// server — and a card that has to render "no date" for the one frame between
  /// the tap and the acknowledgement would flicker for no reason. The server's
  /// value replaces it on the next snapshot.
  final DateTime createdAt;

  const FolderAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.authorName,
    required this.authorUid,
    required this.createdAt,
    this.imageUrl,
  });

  /// True when there is an image to render.
  ///
  /// Null and `''` both mean "no image": the service writes null, but a
  /// document typed by hand in the console can hold the empty string, and the
  /// card must not build a `CachedNetworkImage` for it either way.
  bool get hasImage => (imageUrl ?? '').trim().isNotEmpty;

  /// What a list, a dialog or a tooltip calls this note.
  ///
  /// The title is optional, so every place that names one note has to survive
  /// an empty one — `'سيُحذف «${announcement.title}»'` would read `«»` on a
  /// photo post. Falls back to the note's own first line, then to a word that
  /// is true of every note on this page.
  String get displayTitle {
    final cleanTitle = title.trim();
    if (cleanTitle.isNotEmpty) return cleanTitle;
    for (final line in body.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return 'إعلان مصوّر';
  }

  /// Longest headline the composer accepts. Long enough for
  /// "تعديل في مفردات المقرر", short enough to stay one line on the card.
  static const int maxTitleLength = 120;

  /// Longest note. Generous, because this is where the actual content goes.
  static const int maxBodyLength = 2000;

  /// Longest image URL. Far more than a Supabase public URL needs, and far less
  /// than a base64 payload — the field is a link, and this bound is what keeps
  /// it one. The Firestore rule repeats the same number.
  static const int maxImageUrlLength = 512;

  /// The one rule the composer and the service both apply, or null when the
  /// draft is publishable.
  ///
  /// Lives on the model for the same reason `TimetableEntry.validationMessage`
  /// does: the composer shows it inline before it lets the write through, and
  /// the service throws it for a caller that skipped the form. Two copies would
  /// be two wordings for one rule, and one of them would drift.
  static String? validationMessage({
    required String title,
    required String body,
    String? imageUrl,
  }) {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    final cleanImageUrl = (imageUrl ?? '').trim();

    if (cleanTitle.length > maxTitleLength) {
      return 'العنوان طويل جداً (الحد $maxTitleLength حرفاً)';
    }
    if (cleanBody.length > maxBodyLength) {
      return 'نص الإعلان طويل جداً (الحد $maxBodyLength حرفاً)';
    }
    if (cleanImageUrl.length > maxImageUrlLength) {
      return 'رابط الصورة طويل جداً';
    }
    // The rule is on the draft as a whole, not on each field. A note may be a
    // headline, a paragraph, a photo, or any two of the three — the professor
    // posting a picture of the week's schedule has nothing to type. What is
    // refused is a document with nothing in it: it renders as an empty card,
    // and the one who wrote it never learns why nobody answered.
    if (cleanTitle.isEmpty && cleanBody.isEmpty && cleanImageUrl.isEmpty) {
      return 'اكتب نصاً أو أرفق صورة';
    }
    return null;
  }

  /// A stored field as a trimmed string, or null when there is nothing in it.
  static String? _nonEmpty(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  factory FolderAnnouncement.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final raw = data['createdAt'];
    return FolderAnnouncement(
      id: id,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      imageUrl: _nonEmpty(data['imageUrl']),
      authorName: (data['authorName'] ?? '').toString(),
      authorUid: (data['authorUid'] ?? '').toString(),
      createdAt: raw is Timestamp ? raw.toDate() : DateTime.now(),
    );
  }

  /// The create payload. `id` is the document's, and `createdAt` is the
  /// server's, so neither is written here.
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'body': body,
      // Written even when null, so the rules' `is string` and size checks
      // always have a key to read instead of one they would have to deny for
      // being absent.
      'imageUrl': hasImage ? imageUrl!.trim() : null,
      'authorName': authorName,
      'authorUid': authorUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
