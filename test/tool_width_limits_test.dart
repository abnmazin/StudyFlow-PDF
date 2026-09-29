import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/enums.dart';
import 'package:studyflow_pdf/widgets/viewer_components/tool_width_limits.dart';

/// The viewer's stroke-width sliders — the side rail, the right panel and the
/// floating drawing toolbar — used to keep their own bounds.
///
/// That cost two things. A highlighter widened to 30 in the rail failed
/// `Slider`'s `value >= min && value <= max` assert in the panel, which capped
/// the same tool at 20 and did not clamp, so the next tap on the highlighter took
/// the screen down. Short of that, the two sliders read one width as two
/// positions: a pen at 15 sat three quarters along the panel's track and pinned
/// at the end of the rail's, each printing the same number.
///
/// The tests below hold the single definition in place, because the failure mode
/// was a red screen rather than an odd-looking number.
void main() {
  group('ToolWidthLimits', () {
    test('covers every width a surface used to allow', () {
      // The union rule. Narrowing either bound would reach into a width that is
      // already stored in a saved annotation or in the viewer's own per-tool
      // state, and the clamp at the point of use would rewrite it unasked.
      expect(ToolWidthLimits.maxFor(ToolType.pen), greaterThanOrEqualTo(20.0));
      expect(
        ToolWidthLimits.maxFor(ToolType.highlight),
        greaterThanOrEqualTo(30.0),
      );
    });

    test('every tool gets the bounds Slider needs', () {
      // `Slider` asserts `min <= max`, `value` inside them, and `divisions > 0`.
      // Walking all nine tools rather than the two the sliders branch on means a
      // tool added later cannot arrive without a bound.
      for (final tool in ToolType.values) {
        expect(ToolWidthLimits.maxFor(tool), greaterThan(ToolWidthLimits.min));
        expect(
          ToolWidthLimits.divisionsFor(tool),
          greaterThan(0),
          reason: '$tool would assert on divisions',
        );
      }
    });

    test('a clamped width is always inside its own bounds', () {
      // The precondition the framework asserts, for absurd inputs included. 30
      // reaching a tool capped at 20 is exactly the reported crash.
      const reckless = [-5.0, 0.0, 1.0, 7.5, 20.0, 30.0, 400.0];
      for (final tool in ToolType.values) {
        for (final width in reckless) {
          final clamped = ToolWidthLimits.clampFor(tool, width);
          expect(clamped, greaterThanOrEqualTo(ToolWidthLimits.min));
          expect(clamped, lessThanOrEqualTo(ToolWidthLimits.maxFor(tool)));
        }
      }
    });

    test('the highlighter is the only tool that outgrows the pen', () {
      // Guards the branch itself. If this flips, `maxFor` is being read from the
      // wrong place and the rail and the panel part company again.
      expect(
        ToolWidthLimits.maxFor(ToolType.highlight),
        greaterThan(ToolWidthLimits.maxFor(ToolType.pen)),
      );
      for (final tool in ToolType.values) {
        if (tool == ToolType.highlight) continue;
        expect(ToolWidthLimits.maxFor(tool), ToolWidthLimits.strokeMax);
      }
    });
  });

  group('the bounds a Slider is handed', () {
    Future<void> pumpSlider(
      WidgetTester tester, {
      required ToolType tool,
      required double width,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Slider(
                value: ToolWidthLimits.clampFor(tool, width),
                min: ToolWidthLimits.min,
                max: ToolWidthLimits.maxFor(tool),
                divisions: ToolWidthLimits.divisionsFor(tool),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a width every surface allows builds without asserting', (
      tester,
    ) async {
      // 30 is the width the rail gave a highlighter and the panel refused.
      for (final tool in ToolType.values) {
        await pumpSlider(tester, tool: tool, width: 30.0);
        expect(tester.takeException(), isNull, reason: '$tool at 30');
      }
    });

    testWidgets('the bounds the panel used to hard-code do assert', (
      tester,
    ) async {
      // The negative control, and the reason the clamp exists: this is the exact
      // `Slider` the right panel built for a tool that arrived at 30, and it is
      // what produced the red screen. Without this test the ones above could
      // pass on a `Slider` that never asserts at all.
      //
      // `throwsAssertionError` rather than `takeException`: `Slider` asserts in
      // its constructor, so the throw happens while this test is building the
      // widget — before `pumpWidget` is ever entered, and therefore invisible to
      // the exception the framework would have caught for it.
      expect(
        () => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Slider(
                  value: 30.0,
                  min: 1.0,
                  max: 20.0,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
        throwsAssertionError,
      );
    });
  });
}
