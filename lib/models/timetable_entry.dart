import 'package:cloud_firestore/cloud_firestore.dart';

import 'lecture_slot.dart';

/// One recurring lecture in the shared timetable.
///
/// Recurring weekly rather than dated, because that is what a timetable is: a
/// lecture at 10:30 on Sunday is next Sunday too, and an admin should enter it
/// once instead of every week. The concrete date is supplied by whoever asks,
/// via [lectureOn] — nothing in here stores a `DateTime` for "the day", because
/// a stored date would silently expire.
class TimetableEntry {
  TimetableEntry({
    required this.id,
    required this.title,
    required this.room,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    this.updatedBy = '',
  });

  /// Firestore document id. Empty only for an entry that has not been written yet.
  final String id;

  /// Course or session name.
  final String title;

  /// Room or hall.
  final String room;

  /// `DateTime.monday` (1) through `DateTime.sunday` (7). The same numbering
  /// `DateTime` uses, so no conversion table is needed anywhere.
  final int weekday;

  /// Minutes from midnight, 0..1440. An int rather than a `TimeOfDay` because
  /// `TimeOfDay` is a UI type that cannot be stored, and converting at the edge
  /// keeps the arithmetic (sorting, duration, overlap checks) in plain ints.
  final int startMinutes;

  /// Minutes from midnight, strictly after [startMinutes].
  final int endMinutes;

  /// Display name of whoever last wrote this, shown in the admin's edit form so
  /// a shared table has an obvious person to ask about a row.
  final String updatedBy;

  /// How long this lecture runs, in minutes.
  int get durationMinutes => endMinutes - startMinutes;

  TimetableEntry copyWith({
    String? id,
    String? title,
    String? room,
    int? weekday,
    int? startMinutes,
    int? endMinutes,
    String? updatedBy,
  }) {
    return TimetableEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      room: room ?? this.room,
      weekday: weekday ?? this.weekday,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  /// This entry as it falls on [day], or null when [day] is not its weekday.
  ///
  /// Returning null rather than an entry for the wrong day is deliberate: the
  /// caller groups by day and would otherwise render a Monday lecture under
  /// Tuesday's heading, which is worse than rendering nothing.
  LectureSlot? lectureOn(DateTime day) {
    if (day.weekday != weekday) return null;
    return LectureSlot(
      title: title,
      time: timeLabel,
      room: room,
      startsAt: DateTime(
        day.year,
        day.month,
        day.day,
        startMinutes ~/ 60,
        startMinutes % 60,
      ),
    );
  }

  /// The chip's text: the whole range, e.g. `10:30 - 12:00`.
  ///
  /// A range rather than the start alone because a timetable reader is looking
  /// for when the session *finishes* — that is the number that decides whether
  /// the next one is possible. `LectureSlot.time` is a display string, so this
  /// is where a two-field model becomes one without the row knowing.
  String get timeLabel => endMinutes > startMinutes
      ? '${formatMinutes(startMinutes)} - ${formatMinutes(endMinutes)}'
      : formatMinutes(startMinutes);

  /// `10:30` from 630. Written 24-hour with a leading zero, matching the way the
  /// rest of the app's Arabic UI writes times and sorting lexically.
  static String formatMinutes(int minutes) {
    final m = minutes.clamp(0, 24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Parses `10:30`, `10.30`, or a bare `1030` into minutes, or null when it is
  /// not a time. Deliberately lenient about the separator because an admin
  /// typing on a keyboard with an Arabic layout will not always produce a colon,
  /// and refusing to save over a colon is not a useful kind of strict.
  static int? parseTime(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final parts = text.split(RegExp(r'[:.\s]'));
    if (parts.length == 1) {
      // Bare digits: `930` is 09:30, `1030` is 10:30, `830` is 08:30.
      if (!RegExp(r'^\d{3,4}$').hasMatch(text)) return null;
      final padded = text.padLeft(4, '0');
      return _minutesOf(
        int.parse(padded.substring(0, 2)),
        int.parse(padded.substring(2)),
      );
    }
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return _minutesOf(h, m);
  }

  static int? _minutesOf(int hours, int minutes) {
    if (hours < 0 || hours > 24 || minutes < 0 || minutes > 59) return null;
    // 24:00 is the end of the day and the last value `fromFirestore` accepts;
    // `24:30` is the same day plus half an hour, which no lecture is. Bounding the
    // hour and the minute independently lets that one through as 1470, and the row
    // then reads back from Firestore clamped to 1440 — a time the admin typed
    // silently becoming a different one. The parser is the place to refuse it,
    // because nothing downstream can tell the two apart once they are ints.
    if (hours == 24 && minutes > 0) return null;
    return hours * 60 + minutes;
  }

  /// The Arabic sentence that blocks saving this entry, or null when it may be
  /// written.
  ///
  /// These are the two sentences `TimetableService.saveEntry` throws, kept in the
  /// model so the admin's editor can show them *inline, before* the write is
  /// attempted, and the service can still refuse the write with the same words.
  /// Spelling them out again in the form would show an admin two different
  /// wordings for one rule, and leave one copy to drift the next time this changes.
  ///
  /// Takes the three fields it needs rather than a whole [TimetableEntry] because
  /// the editor validates a form that is not an entry yet — it has two text
  /// fields that may not parse into times at all.
  static String? validationMessage({
    required String title,
    required int startMinutes,
    required int endMinutes,
  }) {
    if (title.trim().isEmpty) return 'اسم المحاضرة مطلوب';
    if (endMinutes <= startMinutes) {
      return 'وقت الانتهاء يجب أن يكون بعد وقت البداية';
    }
    return null;
  }

  /// The weekday's Arabic name, numbered the way [DateTime.weekday] numbers it.
  ///
  /// Empty for out-of-range input rather than throwing: this is read from a widget
  /// build, and a row hand-written in the Firestore console with `weekday: 9`
  /// should draw a blank heading, not take the editor down. [fromFirestore]
  /// already refuses such a row outright, so this is the second layer, not the
  /// first one.
  static String weekdayLabel(int weekday) =>
      weekday >= 1 && weekday <= 7 ? weekdayNames[weekday - 1] : '';

  /// The week spelled out, indexed by `weekday - 1`.
  ///
  /// Public because the editor builds its day picker from it, and the day list
  /// must be derived from the same numbering `TimetableEntry` stores — a second
  /// hand-typed list in a second order is how Sunday ends up filed under Monday.
  /// Starts at Monday because that is where `DateTime` starts.
  static const List<String> weekdayNames = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  /// The Firestore document. `createdAt`/`updatedAt` are server timestamps
  /// rather than client times, so two admins in different time zones cannot
  /// write a row that claims to be from the future.
  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'title': title,
    'room': room,
    'weekday': weekday,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'updatedBy': updatedBy,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Reads a document back, tolerating a missing body and wrongly-typed fields.
  ///
  /// [data] is nullable so a call site can hand over `doc.data()` without
  /// checking it: a document that exists but carries no data is not a lecture, and
  /// is treated exactly like one missing its title. Every other field is validated
  /// rather than cast, because a rule change or a hand edit in the console should
  /// degrade one row to "not shown" instead of taking the whole schedule down with
  /// a cast error inside a stream.
  static TimetableEntry? fromFirestore(String id, Map<String, dynamic>? data) {
    // Nullable so this call site can hand over `doc.data()` without checking it:
    // a snapshot document that exists but carries no data is not a lecture, and
    // is treated exactly like one missing its title.
    if (data == null) return null;
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;

    final weekday = (data['weekday'] as num?)?.toInt();
    if (weekday == null || weekday < 1 || weekday > 7) return null;

    final start = (data['startMinutes'] as num?)?.toInt();
    if (start == null || start < 0 || start > 24 * 60) return null;

    // An entry with no end is a point in time, not a lecture: fall back to a
    // nominal hour rather than rendering a zero-length range.
    var end = (data['endMinutes'] as num?)?.toInt() ?? start + 60;
    if (end > 24 * 60) end = 24 * 60;
    if (end <= start) end = (start + 60).clamp(0, 24 * 60);

    return TimetableEntry(
      id: id,
      title: title,
      room: (data['room'] as String?)?.trim() ?? '',
      weekday: weekday,
      startMinutes: start,
      endMinutes: end,
      updatedBy: (data['updatedBy'] as String?)?.trim() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimetableEntry &&
      other.id == id &&
      other.title == title &&
      other.room == room &&
      other.weekday == weekday &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes &&
      other.updatedBy == updatedBy;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    room,
    weekday,
    startMinutes,
    endMinutes,
    updatedBy,
  );

  @override
  String toString() =>
      'TimetableEntry($id, $title, wd=$weekday, '
      '${formatMinutes(startMinutes)}-${formatMinutes(endMinutes)})';
}
