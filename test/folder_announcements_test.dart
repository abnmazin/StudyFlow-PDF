import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/folder_announcement.dart';
import 'package:studyflow_pdf/models/university_folder.dart';
import 'package:studyflow_pdf/utils/relative_date.dart';
import 'package:studyflow_pdf/widgets/announcements/announcement_composer.dart';
import 'package:studyflow_pdf/widgets/announcements/folder_announcements_view.dart';

/// The announcements page that replaces the dashboard when a folder under
/// "المكتبة الجامعية" is opened in the sidebar, and the publish bar on it.
///
/// The page reads no provider and owns no subscription — `AppProvider` holds
/// the live Firestore stream and hands the result down as props — so all of
/// this runs with no Isar and no Firebase behind it. What is worth holding in
/// place is the model rule the composer and the service both apply, and the
/// states the page has to tell apart.
UniversityFolder _folder(String id, {String name = 'انظمة القدرة'}) {
  return UniversityFolder(
    id: id,
    universityId: 'uni-1',
    name: name,
    createdBy: 'admin',
    createdAt: DateTime(2025, 1, 1),
  );
}

FolderAnnouncement _note(
  String id, {
  String title = 'تأجيل المحاضرة',
  String body = 'ستُقام محاضرة هذا الأسبوع يوم الخميس.',
  String authorName = 'د. أحمد الشريف',
  String authorUid = 'uid-lecturer',
  DateTime? createdAt,
  String? imageUrl,
}) {
  return FolderAnnouncement(
    id: id,
    title: title,
    body: body,
    authorName: authorName,
    authorUid: authorUid,
    createdAt: createdAt ?? DateTime(2026, 9, 29, 10, 0),
    imageUrl: imageUrl,
  );
}

void main() {
  group('FolderAnnouncement.validationMessage', () {
    test('a draft with nothing in it is refused', () {
      // The rule is on the draft, not on each field. What is refused is the
      // document that would render as an empty card: whoever wrote it would
      // never find out why nobody answered.
      expect(
        FolderAnnouncement.validationMessage(title: '', body: ''),
        'اكتب نصاً أو أرفق صورة',
      );
      expect(
        FolderAnnouncement.validationMessage(title: '  ', body: '   '),
        'اكتب نصاً أو أرفق صورة',
      );
      // Whitespace is not an image to publish around either.
      expect(
        FolderAnnouncement.validationMessage(
          title: '',
          body: '  ',
          imageUrl: ' ',
        ),
        'اكتب نصاً أو أرفق صورة',
      );
    });

    test('a title, a body or an image is each enough on its own', () {
      // The professor posting a picture of the week's schedule has nothing to
      // type, and the one posting a single line has nothing to attach.
      expect(
        FolderAnnouncement.validationMessage(title: '', body: 'نص'),
        isNull,
      );
      expect(
        FolderAnnouncement.validationMessage(title: 'عنوان', body: '   '),
        isNull,
      );
      expect(
        FolderAnnouncement.validationMessage(
          title: '',
          body: '',
          imageUrl: ' https://cdn.example.com/images/1.png ',
        ),
        isNull,
      );
    });

    test('the image URL is bounded like the other fields', () {
      // A URL, not a payload: the field is a link, and the Firestore rule
      // repeats this same ceiling.
      expect(
        FolderAnnouncement.validationMessage(
          title: 'عنوان',
          body: '',
          imageUrl: 'h' * (FolderAnnouncement.maxImageUrlLength + 1),
        ),
        'رابط الصورة طويل جداً',
      );
      expect(
        FolderAnnouncement.validationMessage(
          title: 'عنوان',
          body: '',
          imageUrl: 'h' * FolderAnnouncement.maxImageUrlLength,
        ),
        isNull,
      );
    });

    test('the length limits are enforced', () {
      final longTitle = 'ع' * (FolderAnnouncement.maxTitleLength + 1);
      final longBody = 'ن' * (FolderAnnouncement.maxBodyLength + 1);

      expect(
        FolderAnnouncement.validationMessage(title: longTitle, body: 'نص'),
        isNotNull,
      );
      expect(
        FolderAnnouncement.validationMessage(title: 'عنوان', body: longBody),
        isNotNull,
      );
      // Exactly at the limit is allowed — an off-by-one here would refuse a
      // note that the composer's own `maxLength` lets through.
      expect(
        FolderAnnouncement.validationMessage(
          title: 'ع' * FolderAnnouncement.maxTitleLength,
          body: 'ن',
        ),
        isNull,
      );
    });

    test('a filled draft passes', () {
      expect(
        FolderAnnouncement.validationMessage(
          title: 'موعد الاختبار النصفي',
          body: 'الاختبار يوم الأحد القادم.',
        ),
        isNull,
      );
    });
  });

  group('FolderAnnouncement.fromFirestore', () {
    test('reads every field the card prints', () {
      final note = FolderAnnouncement.fromFirestore('a1', {
        'title': 'تعديل في مفردات المقرر',
        'body': 'حُذف الفصل التاسع.',
        'authorName': 'د. أحمد الشريف',
        'authorUid': 'uid-lecturer',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 20, 8, 30)),
      });

      expect(note.id, 'a1');
      expect(note.title, 'تعديل في مفردات المقرر');
      expect(note.body, 'حُذف الفصل التاسع.');
      expect(note.authorName, 'د. أحمد الشريف');
      expect(note.authorUid, 'uid-lecturer');
      expect(note.createdAt, DateTime(2026, 9, 20, 8, 30));
    });

    test('a missing timestamp reads as now rather than throwing', () {
      // A pending write echoes back locally with no server timestamp. A card
      // that had to render "no date" for that frame would flicker for no
      // reason, so the fallback is a real date.
      final before = DateTime.now();
      final note = FolderAnnouncement.fromFirestore('a1', {
        'title': 'عنوان',
        'body': 'نص',
        'authorName': 'د. أحمد',
        'authorUid': 'uid-1',
        'createdAt': null,
      });

      expect(
        note.createdAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        note.createdAt.isAfter(before.add(const Duration(seconds: 5))),
        isFalse,
      );
    });

    test('a document missing every field does not throw', () {
      final note = FolderAnnouncement.fromFirestore('a1', const {});
      expect(note.title, isEmpty);
      expect(note.body, isEmpty);
      expect(note.authorUid, isEmpty);
    });

    test('the image URL is read, and an empty one is no image', () {
      final withImage = FolderAnnouncement.fromFirestore('a1', const {
        'title': 'جدول الاختبارات',
        'body': '',
        'imageUrl': '  https://cdn.example.com/images/2.png  ',
        'authorName': 'د. أحمد',
        'authorUid': 'uid-1',
      });
      expect(withImage.imageUrl, 'https://cdn.example.com/images/2.png');
      expect(withImage.hasImage, isTrue);

      // `''` is what a document typed by hand in the console holds, and it has
      // to mean the same as the null the client writes.
      final empty = FolderAnnouncement.fromFirestore('a1', const {
        'title': 'عنوان',
        'body': 'نص',
        'imageUrl': '',
      });
      expect(empty.imageUrl, isNull);
      expect(empty.hasImage, isFalse);

      // And a note written before the field existed simply has no key.
      final legacy = FolderAnnouncement.fromFirestore('a1', const {
        'title': 'عنوان',
        'body': 'نص',
      });
      expect(legacy.hasImage, isFalse);
    });

    test('displayTitle names a note whose title is empty', () {
      // A photo-only note has no title at all — the delete dialog has to call
      // it something rather than `«»`.
      final photoOnly = FolderAnnouncement.fromFirestore('a1', const {
        'title': '',
        'body': '',
        'imageUrl': 'https://cdn.example.com/images/3.png',
      });
      expect(photoOnly.displayTitle, 'إعلان مصوّر');

      // Or falls back to the note's own first real line.
      final untitled = FolderAnnouncement.fromFirestore('a1', const {
        'title': '   ',
        'body': '\n  ستُقام المحاضرة يوم الخميس.  \nالمكان: القاعة 3',
      });
      expect(untitled.displayTitle, 'ستُقام المحاضرة يوم الخميس.');
    });

    test('toFirestore writes the image key even when there is no image', () {
      // The rules read `imageUrl`, so the key has to be there to be read: an
      // absent key would make the "one of the three is filled" test fail on
      // what is really just a text note.
      final withoutImage = _note('a1').toFirestore();
      expect(withoutImage.containsKey('imageUrl'), isTrue);
      expect(withoutImage['imageUrl'], isNull);

      final withImage = _note(
        'a1',
        imageUrl: ' https://cdn.example.com/images/4.png ',
      ).toFirestore();
      expect(withImage['imageUrl'], 'https://cdn.example.com/images/4.png');
    });
  });
  group('formatRelativeDate', () {
    final now = DateTime(2026, 9, 29, 17, 14);

    test('today is named rather than dated', () {
      expect(
        formatRelativeDate(DateTime(2026, 9, 29, 9, 5), now: now),
        'اليوم 9:05 ص',
      );
    });

    test('yesterday is named, even two hours after it', () {
      // Compared by calendar day, not elapsed hours: 23:00 last night is "أمس"
      // at 01:00 today, and a difference-in-hours implementation would say
      // "اليوم".
      expect(
        formatRelativeDate(
          DateTime(2026, 9, 28, 23, 0),
          now: DateTime(2026, 9, 29, 1, 0),
        ),
        'أمس 11:00 م',
      );
    });

    test('the rest of the first week counts days', () {
      expect(
        formatRelativeDate(DateTime(2026, 9, 24, 8, 0), now: now),
        'منذ 5 أيام',
      );
    });

    test('past a week it becomes a plain date', () {
      expect(
        formatRelativeDate(DateTime(2026, 8, 20, 8, 0), now: now),
        '20/8/2026',
      );
    });

    test('a stamp in the future is not rendered as a negative day count', () {
      // Only a clock skew or a hand-typed document produces one, but "-1 أيام"
      // on screen is worse than reading it as today.
      expect(
        formatRelativeDate(DateTime(2026, 9, 30, 8, 0), now: now),
        'اليوم 8:00 ص',
      );
    });
  });

  group('formatClock', () {
    test('morning and afternoon are told apart', () {
      expect(formatClock(DateTime(2026, 9, 29, 9, 5)), '9:05 ص');
      expect(formatClock(DateTime(2026, 9, 29, 14, 30)), '2:30 م');
    });

    test('midnight and noon are twelve, not zero', () {
      // The one place a plain `hour % 12` prints `0:00`, which is the bug this
      // test exists to catch.
      expect(formatClock(DateTime(2026, 9, 29, 0, 0)), '12:00 ص');
      expect(formatClock(DateTime(2026, 9, 29, 12, 0)), '12:00 م');
      expect(formatClock(DateTime(2026, 9, 29, 12, 45)), '12:45 م');
    });

    test('the hour has no leading zero and the minute keeps its pair', () {
      // `9:05`, not `09:05` and not `9:5`: a 12-hour clock is read aloud, and
      // the column the leading zero would align does not exist here.
      expect(formatClock(DateTime(2026, 9, 29, 1, 5)), '1:05 ص');
      expect(formatClock(DateTime(2026, 9, 29, 23, 59)), '11:59 م');
    });
  });

  group('FolderAnnouncementsView', () {
    Future<void> pump(
      WidgetTester tester, {
      List<FolderAnnouncement> announcements = const [],
      bool isLoading = false,
      bool hasError = false,
      bool canPublish = false,
      bool isPublishing = false,
      bool Function(FolderAnnouncement)? canDelete,
      VoidCallback? onBackToDashboard,
      VoidCallback? onRetry,
      Future<void> Function(String, String, String?)? onPublish,
      ValueChanged<String>? onDelete,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FolderAnnouncementsView(
              folder: _folder('f1', name: 'انظمة القدرة'),
              announcements: announcements,
              isLoading: isLoading,
              hasError: hasError,
              canPublish: canPublish,
              isPublishing: isPublishing,
              canDelete: canDelete ?? (a) => false,
              onBackToDashboard: onBackToDashboard,
              onRetry: onRetry,
              onPublish: onPublish,
              onDelete: onDelete,
            ),
          ),
        ),
      );
    }

    testWidgets('names the folder and prints its notes', (tester) async {
      final notes = [
        _note('a1', title: 'تأجيل المحاضرة'),
        _note(
          'a2',
          title: 'موعد الاختبار النصفي',
          authorName: 'م. سارة العتيبي',
        ),
      ];

      await pump(tester, announcements: notes);

      expect(tester.takeException(), isNull);
      expect(find.text('انظمة القدرة'), findsOneWidget);
      expect(find.text('إعلانات المادة'), findsOneWidget);
      expect(find.text('تأجيل المحاضرة'), findsOneWidget);
      expect(find.text('موعد الاختبار النصفي'), findsOneWidget);
      expect(find.text('2 إعلان'), findsOneWidget);
      expect(find.textContaining('د. أحمد الشريف'), findsOneWidget);
    });
    testWidgets('loading is not the same answer as empty', (tester) async {
      // The one that matters: "لا توجد إعلانات" drawn before the first snapshot
      // is a wrong answer wearing the clothes of a right one.
      await pump(tester, isLoading: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('لا توجد إعلانات لهذه المادة بعد'), findsNothing);
    });

    testWidgets('a refused read is not the same answer as empty', (
      tester,
    ) async {
      var retries = 0;
      await pump(tester, hasError: true, onRetry: () => retries++);

      expect(find.text('تعذّر تحميل الإعلانات'), findsOneWidget);
      expect(find.text('لا توجد إعلانات لهذه المادة بعد'), findsNothing);

      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('an empty folder gets the empty state', (tester) async {
      await pump(tester);

      expect(find.text('لا توجد إعلانات لهذه المادة بعد'), findsOneWidget);
      // The folder is still named, so the page never reads as an error.
      expect(find.text('انظمة القدرة'), findsOneWidget);
      // And the chip does not claim "0 إعلان" — it is absent, not zero.
      expect(find.text('0 إعلان'), findsNothing);
    });

    testWidgets('the publish bar is staff-only', (tester) async {
      await pump(tester, canPublish: false, onPublish: (_, _, _) async {});
      expect(find.byType(AnnouncementComposer), findsNothing);
      // A student is told to wait; a professor is told where the control is.
      // The two sentences differ on purpose.
      expect(find.textContaining('ستظهر هنا'), findsOneWidget);

      await pump(tester, canPublish: true, onPublish: (_, _, _) async {});
      expect(find.byType(AnnouncementComposer), findsOneWidget);
      expect(find.textContaining('ابدأ بنشر'), findsOneWidget);
    });

    testWidgets('the publish bar sits under the list, not over it', (
      tester,
    ) async {
      await pump(
        tester,
        announcements: [_note('a1')],
        canPublish: true,
        onPublish: (_, _, _) async {},
      );

      // Position, not just presence: the same widget above the list is the
      // layout this replaced, and `findsOneWidget` cannot tell the two apart.
      final listBottom = tester.getBottomLeft(find.byType(ListView)).dy;
      final barTop = tester.getTopLeft(find.byType(AnnouncementComposer)).dy;
      expect(barTop, greaterThanOrEqualTo(listBottom));

      // And the notes are still the first thing on the page, under the header.
      expect(
        tester.getTopLeft(find.text('تأجيل المحاضرة')).dy,
        lessThan(barTop),
      );
    });

    testWidgets('the delete control follows the per-note rule', (tester) async {
      final notes = [_note('a1'), _note('a2', authorUid: 'uid-someone-else')];

      // A reader handed no rule removes nothing, and is not shown a disabled
      // control for an action that cannot succeed.
      await pump(tester, announcements: notes);
      expect(find.byTooltip('حذف الإعلان'), findsNothing);

      // Only the note the rule allows.
      await pump(
        tester,
        announcements: notes,
        canDelete: (a) => a.id == 'a2',
        onDelete: (_) {},
      );
      expect(find.byTooltip('حذف الإعلان'), findsOneWidget);
    });
    testWidgets('deleting asks first, and only reports on confirm', (
      tester,
    ) async {
      final deleted = <String>[];
      await pump(
        tester,
        announcements: [_note('a1')],
        canDelete: (a) => true,
        onDelete: deleted.add,
      );

      await tester.tap(find.byTooltip('حذف الإعلان'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty, reason: 'the dialog gates the call');

      // Cancelling leaves the note alone — the dialog is the only thing between
      // a mis-tap and a note deleted for every other reader.
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      expect(find.text('تأجيل المحاضرة'), findsOneWidget);

      await tester.tap(find.byTooltip('حذف الإعلان'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();
      expect(deleted, ['a1']);
    });

    testWidgets('the way back to the dashboard is optional', (tester) async {
      await pump(tester);
      expect(find.byTooltip('العودة إلى الرئيسية'), findsNothing);

      var backTaps = 0;
      await pump(tester, onBackToDashboard: () => backTaps++);
      await tester.tap(find.byTooltip('العودة إلى الرئيسية'));
      await tester.pump();
      expect(backTaps, 1);
    });

    testWidgets('a note with a picture draws it under its text', (
      tester,
    ) async {
      await pump(
        tester,
        announcements: [
          _note(
            'a1',
            body: 'جدول الاختبارات النهائية:',
            imageUrl: 'https://cdn.example.com/images/10.png',
          ),
        ],
      );

      // Asserted on the URL rather than on the pixels: in a widget test the
      // fetch fails, so what is on screen is the error state — and which
      // picture was asked for is the part that has to be right.
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://cdn.example.com/images/10.png');

      expect(
        tester.getTopLeft(find.byType(CachedNetworkImage)).dy,
        greaterThan(
          tester.getTopLeft(find.text('جدول الاختبارات النهائية:')).dy,
        ),
      );
    });

    testWidgets('a note without a picture draws no image at all', (
      tester,
    ) async {
      await pump(tester, announcements: [_note('a1')]);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('a picture-only note is named, not printed as «»', (
      tester,
    ) async {
      final deleted = <String>[];
      await pump(
        tester,
        announcements: [
          _note('a1', title: '', body: '', imageUrl: 'https://cdn/1.png'),
        ],
        canDelete: (a) => true,
        onDelete: deleted.add,
      );

      await tester.tap(find.byTooltip('حذف الإعلان'));
      // `pump`, not `pumpAndSettle`: the attached picture's placeholder is a
      // spinner, and a spinner is an animation that never ends.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('إعلان مصوّر'), findsOneWidget);

      await tester.tap(find.text('حذف'));
      await tester.pump();
      expect(deleted, ['a1']);
    });
  });

  group('AnnouncementComposer', () {
    Future<void> pumpComposer(
      WidgetTester tester, {
      required Future<void> Function(String, String, String?) onPublish,
      bool isPublishing = false,
      // Injected in every test. The real picker opens a native file dialog and
      // uploads to Supabase Storage, and neither exists here; defaulting it to
      // a pick that answers null — "the dialog was closed" — keeps the tests
      // that are not about images from reaching for either.
      Future<String?> Function()? pickImage,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnnouncementComposer(
                folderName: 'انظمة القدرة',
                isPublishing: isPublishing,
                onPublish: onPublish,
                pickImage: pickImage ?? () async => null,
              ),
            ),
          ),
        ),
      );
    }

    /// Opens the collapsed bar.
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.textContaining('نشر إعلان جديد'));
      await tester.pumpAndSettle();
    }

    /// Attaches an image through the button, and lands on the frame the preview
    /// appears on.
    ///
    /// `pump`, not `pumpAndSettle`: the preview's placeholder is a spinner, and
    /// a spinner is an animation that never ends — settling here would time out
    /// instead of showing the thumbnail.
    Future<void> tapAttach(WidgetTester tester) async {
      await tester.tap(find.text('إرفاق صورة'));
      await tester.pump();
      await tester.pump();
    }

    /// Publishes, and lets the bar's collapse play out.
    Future<void> tapPublish(WidgetTester tester) async {
      await tester.tap(find.text('نشر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('starts as a bar and opens on tap', (tester) async {
      await pumpComposer(tester, onPublish: (_, _, _) async {});

      expect(find.textContaining('نشر إعلان جديد'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await open(tester);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('an empty draft is refused with the model wording', (
      tester,
    ) async {
      var calls = 0;
      await pumpComposer(
        tester,
        onPublish: (_, _, _) async {
          calls++;
        },
      );
      await open(tester);

      await tester.tap(find.text('نشر'));
      await tester.pumpAndSettle();

      expect(calls, 0, reason: 'no write for a draft the model rejects');
      expect(find.text('اكتب نصاً أو أرفق صورة'), findsOneWidget);
      // Still open, so nothing typed is lost while the reader fixes it.
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('publishing sends the trimmed draft and resets the bar', (
      tester,
    ) async {
      final sent = <String>[];
      await pumpComposer(
        tester,
        onPublish: (title, body, _) async => sent.add('$title|$body'),
      );
      await open(tester);

      await tester.enterText(find.byType(TextField).first, '  موعد الاختبار  ');
      await tester.enterText(find.byType(TextField).last, '  الأحد القادم.  ');
      await tester.tap(find.text('نشر'));
      await tester.pumpAndSettle();

      expect(sent, ['موعد الاختبار|الأحد القادم.']);
      // Collapsed again and empty, so the next note does not start from the
      // previous one's text.
      expect(find.textContaining('نشر إعلان جديد'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a failed publish keeps the draft and reports the reason', (
      tester,
    ) async {
      await pumpComposer(
        tester,
        onPublish: (_, _, _) async =>
            throw UnsupportedError('نشر الإعلانات متاح للأستاذ والمدير فقط'),
      );
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'عنوان');
      await tester.enterText(find.byType(TextField).last, 'نص');
      await tester.tap(find.text('نشر'));
      await tester.pumpAndSettle();

      // The exception's class name is stripped: the reader gets the sentence,
      // not `UnsupportedError: ` in front of it.
      expect(
        find.text('نشر الإعلانات متاح للأستاذ والمدير فقط'),
        findsOneWidget,
      );
      expect(find.text('عنوان'), findsOneWidget);
    });

    testWidgets('a note may be the picture alone', (tester) async {
      final sent = <String>[];
      await pumpComposer(
        tester,
        onPublish: (title, body, imageUrl) async =>
            sent.add('[${title.trim()}][${body.trim()}][$imageUrl]'),
        pickImage: () async => 'https://cdn.example.com/images/7.png',
      );
      await open(tester);

      // Nothing typed and nothing to reject: the post is the photo.
      await tapAttach(tester);
      await tapPublish(tester);

      expect(sent, ['[][][https://cdn.example.com/images/7.png]']);
      expect(find.byType(TextField), findsNothing, reason: 'the bar reset');
    });

    testWidgets('an attached picture is previewed, and can be removed', (
      tester,
    ) async {
      final sent = <String>[];
      await pumpComposer(
        tester,
        onPublish: (_, _, imageUrl) async => sent.add(imageUrl ?? 'بلا صورة'),
        pickImage: () async => 'https://cdn.example.com/images/8.png',
      );
      await open(tester);

      await tapAttach(tester);
      // The control offers a change rather than a first attach, the picture
      // itself is on screen, and the picture carries the way out.
      expect(find.text('تغيير الصورة'), findsOneWidget);
      final preview = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(preview.imageUrl, 'https://cdn.example.com/images/8.png');
      expect(find.byTooltip('إزالة الصورة'), findsOneWidget);

      await tester.tap(find.byTooltip('إزالة الصورة'));
      await tester.pump();
      expect(find.byTooltip('إزالة الصورة'), findsNothing);
      expect(find.text('إرفاق صورة'), findsOneWidget);

      // Removed means removed: the note goes out as text.
      await tester.enterText(find.byType(TextField).first, 'عنوان');
      await tapPublish(tester);
      expect(sent, ['بلا صورة']);
    });

    testWidgets('a dismissed picker changes nothing', (tester) async {
      await pumpComposer(
        tester,
        onPublish: (_, _, _) async {},
        pickImage: () async => null,
      );
      await open(tester);

      await tapAttach(tester);

      // No preview and no complaint: closing a dialog is not a failure.
      expect(find.text('إرفاق صورة'), findsOneWidget);
      expect(find.byTooltip('إزالة الصورة'), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('a failed upload is reported and keeps the draft', (
      tester,
    ) async {
      await pumpComposer(
        tester,
        onPublish: (_, _, _) async {},
        pickImage: () async =>
            throw StateError('تعذّر رفع الصورة، حاول مرة أخرى'),
      );
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'عنوان');
      await tapAttach(tester);

      // Said out loud: a button that does nothing and says nothing is the one
      // failure a reader cannot work around.
      expect(find.text('تعذّر رفع الصورة، حاول مرة أخرى'), findsOneWidget);
      expect(find.text('تغيير الصورة'), findsNothing);
      expect(find.text('عنوان'), findsOneWidget);
    });

    testWidgets('while an upload runs the bar says so and refuses more', (
      tester,
    ) async {
      // Held open on purpose: the only way to look at the bar mid-upload is to
      // stop the upload mid-flight.
      final gate = Completer<String?>();
      await pumpComposer(
        tester,
        onPublish: (_, _, _) async {},
        pickImage: () => gate.future,
      );
      await open(tester);

      await tester.tap(find.text('إرفاق صورة'));
      await tester.pump();
      expect(find.text('جارٍ رفع الصورة…'), findsOneWidget);

      // A second tap cannot start a second upload on top of the first.
      await tester.tap(find.text('جارٍ رفع الصورة…'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete('https://cdn.example.com/images/11.png');
      await tester.pump();
      await tester.pump();
      expect(find.text('تغيير الصورة'), findsOneWidget);
    });
  });
}
