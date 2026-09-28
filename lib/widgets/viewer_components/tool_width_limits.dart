import '../../models/models.dart';

/// The one definition of how wide a drawing stroke may be.
///
/// Every stroke-width slider in the viewer reads its bounds from here — the side
/// rail, the right panel, and the floating drawing toolbar — and brings the value
/// it hands to `Slider` inside them first.
///
/// Each surface keeping its own numbers broke twice:
///
/// * `Slider` asserts `value >= min && value <= max`. The rail allowed a 30px
///   highlighter while the right panel capped the same tool at 20, so widening
///   the highlighter in the rail turned the panel into a red screen the next time
///   it was opened.
/// * Short of crashing, the two sliders disagreed about one value. A pen set to
///   15 in the panel was clamped to 12 by the rail, which then drew the thumb
///   pinned at the end of its track beside a label reading "15.0" — the same
///   number the panel showed three quarters of the way along its own track.
///
/// The bounds are the union of what the surfaces allowed, never a subset.
/// Narrowing a range would reach back into widths already stored in saved
/// annotations and in the viewer's own per-tool state, and the clamp at the point
/// of use would then rewrite them without being asked.
class ToolWidthLimits {
  const ToolWidthLimits._();

  /// Thinnest stroke any tool can take.
  static const double min = 1.0;

  /// The pen and every shape that draws with a stroke.
  ///
  /// 20 is the right panel's old upper bound — the wider of the two the pen had,
  /// so no width a user could already reach stops being reachable.
  static const double strokeMax = 20.0;

  /// The highlighter, the one tool whose top end is not a pen's.
  ///
  /// 30 is the rail's old upper bound. The viewer's own default highlighter is
  /// 15, so capping it at a pen's 20 would leave the tool one drag from its
  /// ceiling.
  static const double highlightMax = 30.0;

  /// Upper bound for [tool]'s stroke width.
  static double maxFor(ToolType tool) =>
      tool == ToolType.highlight ? highlightMax : strokeMax;

  /// [width] brought inside [tool]'s bounds.
  ///
  /// Call this before handing a width to a `Slider`. Without it the framework's
  /// assert becomes the message the user reads, as a red screen.
  static double clampFor(ToolType tool, double width) =>
      width.clamp(min, maxFor(tool));

  /// Whole-pixel stops, so every surface offers the same drag.
  ///
  /// The rail snapped to integers while the panel moved continuously, which made
  /// the same gesture mean two different things in the two places.
  static int divisionsFor(ToolType tool) => (maxFor(tool) - min).round();
}
