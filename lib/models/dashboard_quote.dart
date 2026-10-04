import 'package:cloud_firestore/cloud_firestore.dart';

/// One aphorism or quotation on the dashboard's quote panel.
///
/// Authored by an admin in Firestore and read by every signed-in user, which is
/// why it is not an Isar model: an Isar quote would exist only on the disk of
/// the machine that wrote it, and the panel is meant to say the same thing to
/// everybody at the same time.
///
/// [pinned] is the admin's override. The panel rotates through the unpinned
/// quotes on a timer; a pinned quote is the one that stays, so a dean can leave
/// one sentence on every student's dashboard until they take it down. One
/// pinned quote at a time is enforced by `QuoteService.setPinned`, which clears
/// the others in the same write batch — a second pinned document would leave the
/// panel with no rule about which of the two wins.
class DashboardQuote {
  DashboardQuote({
    required this.id,
    required this.text,
    required this.author,
    this.pinned = false,
    this.updatedBy = '',
  });

  /// Firestore document id. Empty only for a quote that has not been written yet.
  final String id;

  /// The quotation itself. The panel is a few lines tall, so the limit is what
  /// keeps a paragraph from being truncated mid-sentence into something that
  /// looks like a fault rather than a quotation.
  final String text;

  /// Who said it, printed under the quotation. Required, not optional: an
  /// unattributed aphorism on a study dashboard reads as an unattributed claim,
  /// and there is no honest way to render one blank.
  final String author;

  /// Whether the admin has frozen this quote on the panel.
  final bool pinned;

  /// Display name of whoever last wrote it, so a shared list of quotations has
  /// the same obvious person to ask about a row that the timetable has.
  final String updatedBy;

  /// Ceilings the Firestore rule mirrors field for field. They live here so the
  /// admin's editor and the boundary cannot disagree about one limit.
  static const int maxTextLength = 280;
  static const int maxAuthorLength = 80;

  DashboardQuote copyWith({
    String? id,
    String? text,
    String? author,
    bool? pinned,
    String? updatedBy,
  }) {
    return DashboardQuote(
      id: id ?? this.id,
      text: text ?? this.text,
      author: author ?? this.author,
      pinned: pinned ?? this.pinned,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  /// The sentence the editor shows when a quote cannot be saved, or null when it
  /// can.
  ///
  /// Both fields are required, and an author of "—" or a blank line is not an
  /// author: the panel prints this string under the quotation, so it has to say
  /// who the quotation belongs to.
  static String? validationMessage({
    required String text,
    required String author,
  }) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return 'اكتب نص الاقتباس';
    if (cleanText.length > maxTextLength) {
      return 'نص الاقتباس أطول من $maxTextLength حرفاً';
    }

    final cleanAuthor = author.trim();
    if (cleanAuthor.isEmpty) return 'اكتب اسم المؤلف أو الحكم';
    if (cleanAuthor.length > maxAuthorLength) {
      return 'اسم المؤلف أطول من $maxAuthorLength حرفاً';
    }
    return null;
  }

  /// The Firestore document. `createdAt`/`updatedAt` are server timestamps
  /// rather than client times, so two admins in different time zones cannot
  /// write a quote that claims to be from the future.
  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'text': text,
    'author': author,
    'pinned': pinned,
    'updatedBy': updatedBy,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Reads a document back, tolerating a missing body and wrongly-typed fields.
  ///
  /// Every field is validated rather than cast, for the reason
  /// `TimetableEntry.fromFirestore` gives: a hand edit in the console should
  /// degrade one quote to "not shown" instead of taking the whole panel down
  /// with a cast error inside a stream.
  static DashboardQuote? fromFirestore(String id, Map<String, dynamic>? data) {
    if (data == null) return null;
    final text = (data['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;

    final author = (data['author'] as String?)?.trim() ?? '';
    if (author.isEmpty) return null;

    return DashboardQuote(
      id: id,
      text: text,
      author: author,
      pinned: data['pinned'] == true,
      updatedBy: (data['updatedBy'] as String?)?.trim() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardQuote &&
      other.id == id &&
      other.text == text &&
      other.author == author &&
      other.pinned == pinned &&
      other.updatedBy == updatedBy;

  @override
  int get hashCode => Object.hash(id, text, author, pinned, updatedBy);

  @override
  String toString() => 'DashboardQuote($id, ${text.length} chars, pinned=$pinned)';
}