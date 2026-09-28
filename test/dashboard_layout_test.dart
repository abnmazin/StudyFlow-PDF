import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/isar_models.dart';
import 'package:studyflow_pdf/models/lecture_slot.dart';
import 'package:studyflow_pdf/widgets/dashboard/dashboard_palette.dart';
import 'package:studyflow_pdf/widgets/dashboard/dashboard_quick_actions.dart';
import 'package:studyflow_pdf/widgets/dashboard/dashboard_reading_stats.dart';
import 'package:studyflow_pdf/widgets/dashboard/dashboard_tasks_schedule.dart';

/// Fixtures, so the tests read as behaviour rather than as data.
class LectureFixture {
  const LectureFixture._();

  /// Long enough to force the title to wrap at every width under test, and mixed
  /// script so the row is exercised the way Arabic content actually behaves.
  static final long = LectureSlot(
    title:
        'محاضرة في مقدمة إلى التعلم العميق مع تطبيقات عملية على الشبكات العصبية وحالات الاستخدام في التعرف على الصور',
    time: '10:30',
    room: 'قاعة 204',
    startsAt: DateTime(2026, 9, 28, 10, 30),
  );

  static final short = LectureSlot(
    title: 'الرياضيات 3',
    time: '08:00',
    room: 'قاعة 12',
    startsAt: DateTime(2026, 9, 28, 8),
  );
}

/// Locks the design's CRITICAL baseline rule against the widget that has to
/// hold it.
///
/// Widget-level on purpose: the rule is a property of the render tree, and a
/// plain `expect` over the widget's own properties would pass while the row
/// still overflowed or pushed the time off the card.
void main() {
  const narrow = Size(1000, 800);

  Future<void> pumpLecture(WidgetTester tester, {required double width}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                // The row needs a bounded height: an unbounded one would let it
                // take whatever it likes and hide a layout bug.
                child: LectureRow(lecture: LectureFixture.long),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the time sits on the title baseline, with no box around it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(narrow);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLecture(tester, width: 300);

    final titleFinder = find.textContaining('التعلم');
    final timeFinder = find.text('10:30');

    // Both are asked where their alphabetic baseline lands on screen, measured
    // against their own font size — 14px for the title, 12px for the time. They
    // must answer the same number, which is the constraint itself: the two share
    // one line of text because the row aligns on baselines, not on centres.
    expect(
      baselineOf(tester, timeFinder),
      closeTo(baselineOf(tester, titleFinder), 0.5),
    );

    // And the label is bare. The chip that used to carry it was a bordered box:
    // with the room dropped from the row, a box around a single label reads as a
    // button, which the row is not.
    expect(find.byKey(const ValueKey('lecture-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-chip')), findsNothing);
  });

  testWidgets('a long title cannot push the chip off a 200px card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(narrow);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLecture(tester, width: 200);

    // The assertion is that nothing overflows: a `RenderFlex` that runs out of
    // room reports during the pump. `takeException` is checked first because an
    // `expect` on it alone prints "Expected: null" with no indication of which
    // flex failed, and the widths below are what make the report actionable.
    final overflow = tester.takeException();
    if (overflow != null) {
      final flexes = tester.allRenderObjects
          .whereType<RenderFlex>()
          .map((f) {
            final kids = <RenderBox>[];
            f.visitChildren((c) {
              if (c is RenderBox) kids.add(c);
            });
            final widths = kids
                .map((k) => k.size.width.toStringAsFixed(1))
                .join(',');
            return '${f.runtimeType} width=${f.size.width} dir=${f.direction} '
                'children=[$widths]';
          })
          .join(' | ');
      fail('Layout overflowed: $overflow — $flexes');
    }

    final timeRight = tester.getBottomRight(
      find.byKey(const ValueKey('lecture-time')),
    );
    final rowRight = tester.getBottomRight(
      find.byKey(const ValueKey('lecture-row')),
    );

    // The time is still inside the row. This is the `Expanded` half of the rule:
    // without it a long title claims the row's full width and the time lands
    // outside the card.
    expect(timeRight.dx, lessThanOrEqualTo(rowRight.dx + 0.5));
  });

  testWidgets('a short lecture keeps its time beside the title', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(narrow);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: LectureRow(lecture: LectureFixture.short),
              ),
            ),
          ),
        ),
      ),
    );

    final titleFinder = find.text('الرياضيات 3');
    final timeFinder = find.byKey(const ValueKey('lecture-time'));

    // In RTL the title is on the right and the time on the left, so the time's
    // left edge sits to the left of the title's. This is the case `center`
    // alignment would also pass, which is exactly why the long-title test above
    // exists.
    expect(
      tester.getTopLeft(timeFinder).dx,
      lessThan(tester.getTopLeft(titleFinder).dx),
    );

    // And they read as one line: the two boxes' centres are close enough that
    // the time does not look like it is hanging below the title.
    final timeRect = tester.getRect(timeFinder);
    final titleRect = tester.getRect(titleFinder);
    expect((timeRect.center.dy - titleRect.center.dy).abs(), lessThan(24));
  });

  // The row is never laid out on its own in the app: `DashboardTasksAndSchedule`
  // puts the schedule card inside an `IntrinsicHeight`, and equalising the two
  // cards means asking the card for its intrinsic height — which walks into
  // this row and asks every child for a *dry* baseline.
  //
  // A childless `DecoratedBox` cannot answer that. `RenderProxyBoxMixin`
  // substitutes `RenderBox.computeDryBaseline`, which throws, and the pump
  // cascades from there into `hasSize` failures up the tree. The tests above
  // miss it because they lay the row out directly, where the baseline is
  // computed wet from the already-laid-out child and a plain box is never asked.
  testWidgets('the row measures under IntrinsicHeight without throwing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: LectureRow(lecture: LectureFixture.long)),
                      const SizedBox(width: 32),
                      // Stand-in for the tasks card, which needs an AppProvider
                      // this test has no reason to build.
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The framework's own report is the assertion: it is the exception the app
    // showed as a red rendering block, so `null` here is the whole test.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('lecture-time')), findsOneWidget);
  });

  testWidgets('the five service tiles share one row and one height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(width: 1200, child: DashboardQuickActions()),
          ),
        ),
      ),
    );

    final tiles = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.key is ValueKey<String>,
    );
    expect(tiles, findsNWidgets(5), reason: 'all five fit on one line');

    // Equal height is the rule `Wrap` could not give: the tiles are wrapped in
    // `IntrinsicHeight` for exactly this, and the longest label is what makes it
    // observable rather than accidental.
    //
    // Compared with a tolerance because the test device rounds layout to
    // physical pixels, so five tiles laid out from one fractional width come
    // back differing by a fraction of a logical pixel. `set` would call that a
    // failure; the eye would not.
    const slop = 0.5;
    final first = tester.getRect(tiles.first);
    for (var i = 0; i < 5; i++) {
      final rect = tester.getRect(tiles.at(i));
      expect(
        rect.height,
        moreOrLessEquals(first.height, epsilon: slop),
        reason: 'tile $i took a different height from its row',
      );
      expect(
        rect.width,
        moreOrLessEquals(first.width, epsilon: slop),
        reason: 'tile $i is not the same width as the rest of its row',
      );
    }

    // The hover fill is a real state change, not a comment: it is the only thing
    // that tells a reader a tile is clickable before they click it.
    expect(
      _fillOf(tester, tiles.first),
      DashboardColors.accent,
      reason: 'the first tile is the primary blue one',
    );

    final hoverTarget = tiles.at(1);
    final before = _fillOf(tester, hoverTarget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(hoverTarget));
    await tester.pumpAndSettle();

    expect(_fillOf(tester, hoverTarget), isNot(before));
    expect(_fillOf(tester, hoverTarget), DashboardColors.hover);
  });

  testWidgets('the streak card fits its fixed height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A streak long enough to be four digits, because the figure is in a
    // `FittedBox` and the bug was never about width: it was the 1.4 leading the
    // app's theme puts on every `TextStyle`, which turned a 26px number into
    // 36px of a card that has 88px for three rows.
    final days = <ReadingDay>[];
    for (var i = 0; i < 7; i++) {
      final day = ReadingDay()
        ..dateKey = DateTime(2026, 9, 28 - i).toIso8601String().substring(0, 10)
        // Above the threshold, so the strip renders its check icon and the bold
        // weekday initial — the tallest form it has.
        ..focusSeconds = 1200
        ..pagesAdvanced = 10;
      days.add(day);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 1200,
              child: DashboardReadingStats(isWide: true, days: days),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The assertion that matters is the one Flutter makes for us: an overflow
    // inside a `RenderFlex` is a framework exception, and a failed test is the
    // only way this ever shows up again.
    expect(tester.takeException(), isNull);

    // And the cards must still be the 130px the design specifies, rather than
    // being silently grown to fit the content.
    final card = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == kStatCardHeight,
    );
    expect(card, findsNWidgets(4));
  });
}

/// The fill of the `BoxDecoration` on a tile's own `Container`.
///
/// Read through the element rather than by searching for `Container` globally,
/// because `InkWell` and `Material` below the tile build containers too and a
/// global search picks the wrong one.
Color _fillOf(WidgetTester tester, Finder tile) {
  final container = tester.widget<Container>(
    find.descendant(of: tile, matching: find.byType(Container)).first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

/// The screen-space y of a [Text] widget's first-line alphabetic baseline.
///
/// `RenderBox.getDistanceToBaseline` cannot be used here: it asserts that it is
/// called during layout, and a test has no such moment. What is available
/// afterwards is the laid-out paragraph plus the public font metrics, so the
/// baseline is the paragraph's top plus the first line's baseline offset for
/// that exact style.
///
/// Each widget is measured against its own style, which matters because the
/// title is 14px and the chip's time is 12px: a shared offset would make the
/// two differ by exactly the amount under test.
double baselineOf(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final text = tester.widget<Text>(finder);
  final direction = Directionality.of(tester.element(finder));
  final painter = TextPainter(
    text: TextSpan(text: text.data ?? '', style: text.style),
    textDirection: direction,
    textScaler: MediaQuery.textScalerOf(tester.element(finder)),
    maxLines: text.maxLines,
  )..layout();
  return paragraph.localToGlobal(Offset.zero).dy +
      painter.computeLineMetrics().first.baseline;
}
