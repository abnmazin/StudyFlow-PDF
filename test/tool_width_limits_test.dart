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
}
