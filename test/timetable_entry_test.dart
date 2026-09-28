import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/timetable_entry.dart';

/// Locks the two rules the admin's schedule editor is built on: how a typed time
/// becomes minutes, and which entries may be written at all.
///
/// Plain unit tests — no Firebase, no widget. `parseTime` and
/// `validationMessage` are the parts of the timetable that can be wrong without
/// anything looking wrong: a time parsed onto the wrong hour still draws a
/// plausible card, and a rule that lets an end precede its start produces a row
/// the service refuses with a sentence the admin cannot act on.
///
/// The editor is the only caller of both, and it pre-fills its own fields from
/// `formatMinutes`, so the two have to agree — see the round trip below.
void main() {
  group('parseTime', () {
    test('reads a colon, a dot, and bare digits as the same clock time', () {
      // The leniency is deliberate: an Arabic keyboard layout does not always
      // produce a colon, and refusing to save over a separator is not a useful
      // kind of strict.
      for (final input in ['08:30', '08.30', '0830']) {
        expect(TimetableEntry.parseTime(input), 8 * 60 + 30, reason: input);
      }
    });

    test('pads a three-digit time on the left, so 930 is half past nine', () {
      // `hmm`, not `mms`. Padding on the right would turn 930 into 93 minutes
      // after midnight, which is a time that exists and is simply not the one
      // that was typed.
      expect(TimetableEntry.parseTime('930'), 9 * 60 + 30);
    });

    test('accepts both ends of the day', () {
      expect(TimetableEntry.parseTime('00:00'), 0);
      expect(TimetableEntry.parseTime('24:00'), 24 * 60);
    });

    test('refuses the hour past midnight and any minute past fifty-nine', () {
      expect(TimetableEntry.parseTime('25:00'), isNull);
      expect(TimetableEntry.parseTime('12:60'), isNull);
      // 24:01 is past the end of the day, and `fromFirestore` refuses anything
      // above 1440 on read. Accepting it here would mean the admin types 24:30,
      // the row is written, and it comes back as 24:00 with nothing said.
      expect(TimetableEntry.parseTime('24:01'), isNull);
      expect(TimetableEntry.parseTime('2430'), isNull);
    });

    test('returns null for anything that is not a time', () {
      // Each of these is a shape a keyboard can actually produce, and every one
      // has to reach the form as "not a time" rather than as a thrown error.
      for (final input in ['', '   ', 'abc', '10:3a', '30', 'half past ten']) {
        expect(TimetableEntry.parseTime(input), isNull, reason: '"$input"');
      }
    });

    test('tolerates surrounding space', () {
      expect(TimetableEntry.parseTime('  10:15  '), 10 * 60 + 15);
    });
  });

  group('formatMinutes', () {
    test('pads both halves, so a column of times sorts lexically', () {
      expect(TimetableEntry.formatMinutes(8 * 60 + 5), '08:05');
      expect(TimetableEntry.formatMinutes(0), '00:00');
      expect(TimetableEntry.formatMinutes(24 * 60), '24:00');
    });

    test('round-trips every time the editor can pre-fill', () {
      // This is the editor's edit path: an entry is opened, its times are written
      // into the fields with `formatMinutes`, and they are read back with
      // `parseTime`. If those two disagree for any input, opening a lecture and
      // saving it untouched moves the lecture — silently, and only for whoever
      // happens to use the hour that disagrees.
      for (var minutes = 0; minutes <= 24 * 60; minutes += 5) {
        expect(
          TimetableEntry.parseTime(TimetableEntry.formatMinutes(minutes)),
          minutes,
          reason: '$minutes',
        );
      }
    });
  });

  group('validationMessage', () {
    test('refuses a lecture with no name', () {
      expect(
        TimetableEntry.validationMessage(
          title: '   ',
          startMinutes: 8 * 60,
          endMinutes: 9 * 60,
        ),
        'اسم المحاضرة مطلوب',
      );
    });

    test('refuses an end that is not after the start', () {
      // Equal is invalid too. A zero-length lecture is not a short lecture, it is
      // a typo, and the card would draw an empty range for it.
      const expected = 'وقت الانتهاء يجب أن يكون بعد وقت البداية';
      expect(
        TimetableEntry.validationMessage(
          title: 'الدوائر المنطقية',
          startMinutes: 10 * 60,
          endMinutes: 10 * 60,
        ),
        expected,
      );
      expect(
        TimetableEntry.validationMessage(
          title: 'الدوائر المنطقية',
          startMinutes: 10 * 60,
          endMinutes: 9 * 60,
        ),
        expected,
      );
    });

    test('lets a well-formed lecture through', () {
      expect(
        TimetableEntry.validationMessage(
          title: 'الدوائر المنطقية',
          startMinutes: 8 * 60,
          endMinutes: 9 * 60,
        ),
        isNull,
      );
    });
  });

  group('weekdayLabel', () {
    test('names the days the way DateTime numbers them', () {
      // `TimetableEntry.weekday` stores `DateTime.weekday` unchanged, and the
      // editor's picker is generated from this list by index, so the two ends have
      // to line up or Sunday's lecture is filed under Monday.
      expect(TimetableEntry.weekdayNames.length, 7);
      expect(TimetableEntry.weekdayLabel(DateTime.monday), 'الاثنين');
      expect(TimetableEntry.weekdayNames.first, 'الاثنين');
      expect(TimetableEntry.weekdayLabel(DateTime.sunday), 'الأحد');
      expect(TimetableEntry.weekdayNames.last, 'الأحد');
    });

    test('draws nothing for a day number only a hand edit could produce', () {
      // A row typed into the Firestore console with `weekday: 9` is refused by
      // `fromFirestore`, and this is the second layer: the editor reaches it from
      // a widget build, where throwing would take the dialog down for one bad row.
      expect(TimetableEntry.weekdayLabel(0), '');
      expect(TimetableEntry.weekdayLabel(9), '');
    });
  });
}
