import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/structure.dart';
import 'package:studyflow_pdf/widgets/dashboard/dashboard_search.dart';

/// Fixtures, so the tests read as behaviour rather than as data.
///
/// `lastPage` is the interesting field: Isar defaults it to 1, so a library
/// straight out of storage is full of files that claim to be "on page one" —
/// which is why page one must not count as a place to resume from.
class Shelf {
  const Shelf._();

  static PdfItem pdf(String id, {String? name, int? lastPage}) => PdfItem(
    id: id,
    name: name ?? '$id.pdf',
    path: 'C:\\library\\$id.pdf',
    lastPage: lastPage,
  );

  /// Two folders: one the reader is working through, one untouched, plus files
  /// they never reached page two of.
  static List<ClassItem> get twoFolders => [
    ClassItem(
      id: 'os',
      name: 'أنظمة التشغيل',
      pdfs: [
        pdf('a', lastPage: 1),
        pdf('b', name: 'المحاضرة الرابعة.pdf', lastPage: 12),
        pdf('c'),
      ],
    ),
    ClassItem(
      id: 'db',
      name: 'قواعد البيانات',
      pdfs: [pdf('d', name: 'الفصل الثاني.pdf', lastPage: 40)],
    ),
  ];
}

/// The search field is the dashboard's only entry point to the user's own
/// files, and two of its properties are pure layout, invisible to a test that
/// only reads widget properties:
///
/// * the panel hangs off the field's **bottom** edge, so it cannot cover the
///   field or the bar's other controls while the list is open;
/// * an untouched field opens onto a **list**, not an empty box with a border
///   around nothing.
void main() {
  const surface = Size(1280, 900);

  /// A field inside a bar the size of the real navbar, with the dashboard's own
  /// sections under it — the layout the panel used to drop itself into the
  /// middle of.
  Future<void> openField(
    WidgetTester tester, {
    required SearchLibrary Function() library,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // The app's own locale, which is what makes the tree RTL. The panel is
        // in the app's `Overlay`, above `home`, so a `Directionality` wrapped
        // around the page would not reach it.
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 80,
                child: Center(
                  child: DashboardSearch(
                    isWide: true,
                    contentWidth: surface.width,
                    libraryOverride: library,
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
  }

  group('buildSearchSuggestions', () {
    test('leads with the file the reader is inside', () {
      final rows = buildSearchSuggestions(
        Shelf.twoFolders,
        activeClassId: 'os',
        activePdfId: 'a',
      );

      // 'a' because it is the open file, then the two files with a place saved
      // in them in the sidebar's order, then what is left over — the list is
      // never shorter than the panel needs, and always longer than the files
      // that happen to have progress.
      expect(rows.map((row) => row.pdf.id), ['a', 'b', 'd', 'c']);
      expect(rows.first.note, 'آخر ملف فتحته');
      expect(rows[1].note, 'صفحة 12');
      expect(rows[2].note, 'صفحة 40');
      expect(rows.last.note, 'لا تقدّم محفوظ');
    });

    test('falls back to the folder\'s own memory when nothing is open', () {
      final folders = Shelf.twoFolders;
      folders[0].lastActivePdfId = 'b';

      final rows = buildSearchSuggestions(folders, activeClassId: 'os');

      expect(rows.first.pdf.id, 'b');
      expect(rows.first.note, 'آخر ملف فتحته');
    });

    test('page one is not a place to resume from', () {
      // Isar hands back every file as `lastPage: 1`, and a file that was opened
      // and left on its first page has no place in it either.
      final folders = [
        ClassItem(
          id: 'os',
          name: 'أنظمة التشغيل',
          pdfs: [Shelf.pdf('a', lastPage: 1), Shelf.pdf('b')],
        ),
      ];

      final rows = buildSearchSuggestions(folders, activeClassId: 'os');

      expect(rows.map((row) => row.pdf.id), ['a', 'b']);
      expect(rows.every((row) => row.note == 'لا تقدّم محفوظ'), isTrue);
    });

    test('files with a place lead, in the sidebar\'s own order', () {
      final rows = buildSearchSuggestions(
        Shelf.twoFolders,
        activeClassId: 'db',
      );

      // 'b' is in the other folder and 'd' in the active one; both have a saved
      // page, so they come before the unstarted files of the active folder. A
      // place saved anywhere beats a file never opened.
      expect(rows.map((row) => row.pdf.id), ['b', 'd', 'a', 'c']);
    });

    test('the active folder leads once nothing anywhere has a place', () {
      final folders = Shelf.twoFolders;
      for (final folder in folders) {
        for (final pdf in folder.pdfs) {
          pdf.lastPage = 1;
        }
      }

      final rows = buildSearchSuggestions(folders, activeClassId: 'db');

      // 'd' is the only file in the active folder, so it leads; the rest keep
      // the sidebar's order.
      expect(rows.map((row) => row.pdf.id), ['d', 'a', 'b', 'c']);
    });

    test('the list is capped, and a shared file is listed once', () {
      final shared = Shelf.pdf('shared', lastPage: 5);
      final folders = [
        ClassItem(id: 'os', name: 'أنظمة التشغيل', pdfs: [shared]),
        ClassItem(id: 'db', name: 'قواعد البيانات', pdfs: [shared]),
        ClassItem(
          id: 'math',
          name: 'الرياضيات',
          pdfs: [for (var i = 0; i < 10; i++) Shelf.pdf('m$i')],
        ),
      ];

      final rows = buildSearchSuggestions(folders, max: 4);

      expect(rows.length, 4);
      expect(rows.where((row) => row.pdf.id == 'shared').length, 1);
    });

    test('an empty library has nothing to suggest', () {
      expect(buildSearchSuggestions(const []), isEmpty);
    });
  });

  group('the panel', () {
    SearchLibrary Function() twoFolders({
      String? activeClassId = 'os',
      String? activePdfId = 'b',
    }) =>
        () => (
          classes: Shelf.twoFolders,
          activeClassId: activeClassId,
          activePdfId: activePdfId,
        );

    testWidgets('opens under the field, never over it', (tester) async {
      await openField(tester, library: twoFolders());

      final field = tester.getRect(find.byType(TextField));
      final panel = tester.getRect(find.byKey(searchPanelKey));

      // The panel's own box, not its first row of text. The panel draws a header
      // above that row, which pushes the row under the field's bottom even when
      // the panel itself is hung off the field's *top* edge — the very bug this
      // guards. The old anchors put the panel's top at the field's top + 8, so
      // the panel covered the field and the rest of the bar.
      expect(panel.top, greaterThanOrEqualTo(field.bottom));
      // And hung off that edge, not parked somewhere else on the page.
      expect(panel.top, lessThanOrEqualTo(field.bottom + 20));
    });

    testWidgets('an untouched field lists the files worth resuming', (
      tester,
    ) async {
      await openField(tester, library: twoFolders());

      expect(find.text('تابع من حيث توقفت'), findsOneWidget);
      expect(find.text('أنظمة التشغيل · آخر ملف فتحته'), findsOneWidget);
      expect(find.text('قواعد البيانات · صفحة 40'), findsOneWidget);
      expect(find.text('اكتب اسم الملف للبحث في 4 ملفات'), findsOneWidget);
    });

    testWidgets('a library with no files says so instead of showing a line', (
      tester,
    ) async {
      await openField(
        tester,
        library: () => (
          classes: const <ClassItem>[],
          activeClassId: null,
          activePdfId: null,
        ),
      );

      expect(find.text('لا توجد ملفات محلية بعد'), findsOneWidget);
      expect(find.text('لا نتائج'), findsNothing);
    });

    testWidgets('a library with nothing started says what it is', (
      tester,
    ) async {
      await openField(
        tester,
        library: () => (
          classes: [
            ClassItem(id: 'os', name: 'أنظمة التشغيل', pdfs: [Shelf.pdf('a')]),
          ],
          activeClassId: 'os',
          activePdfId: null,
        ),
      );

      // One file, no progress: no promise of continuing, and a count that is
      // Arabic rather than "1 ملفات".
      expect(find.text('ملفاتك'), findsOneWidget);
      expect(find.text('تابع من حيث توقفت'), findsNothing);
      expect(find.text('اكتب اسم الملف للبحث في ملف واحد'), findsOneWidget);
    });

    testWidgets('typing replaces the suggestions with the matches', (
      tester,
    ) async {
      await openField(tester, library: twoFolders());

      await tester.enterText(find.byType(TextField), 'الفصل');
      await tester.pumpAndSettle();

      expect(find.text('الفصل الثاني.pdf'), findsOneWidget);
      // A match is one line: the folder rides beside the name, not under it.
      expect(find.text('قواعد البيانات'), findsOneWidget);
      expect(find.text('تابع من حيث توقفت'), findsNothing);
      expect(find.text('المحاضرة الرابعة.pdf'), findsNothing);
    });

    testWidgets('a query that matches nothing says so', (tester) async {
      await openField(tester, library: twoFolders());

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('لا نتائج'), findsOneWidget);
    });
  });
}
