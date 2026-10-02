import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// The cache key a picture's URL is filed under.
///
/// The query string carries a per-request token, so a key built from the whole
/// URL would miss the disk cache on every rebuild and re-download the same
/// picture — the same treatment `DraggableTextWidget` gives an attachment.
///
/// It is a function here rather than a line in the feed because the viewer opens
/// the same picture: two copies of this rule would file one photo under two keys
/// and fetch it twice, once for the note and once for the full-screen view.
String imageCacheKey(String url) =>
    url.contains('?') ? url.split('?').first : url;

/// Opens an attached picture full-screen, where it can be enlarged.
///
/// A note draws its picture at the size it was made, capped to the note's width
/// (`_AnnouncementImage` in `folder_announcements_view.dart`) — enough to
/// recognise it, not enough to read the last row of a timetable photographed off
/// a board. This is the second half of that pair, on the same `showGeneralDialog`
/// the video player uses.
///
/// [title] is the note's headline, when it has one; it only names the picture.
Future<void> showImageLightbox(
  BuildContext context, {
  required String url,
  String? title,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'إغلاق',
    // Near-black rather than the video player's translucent grey: here the
    // picture is the whole subject, so anything showing through behind it would
    // compete with the thing being read.
    barrierColor: Colors.black.withValues(alpha: 0.9),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, secondary) => FadeTransition(
      opacity: anim,
      child: ImageLightboxDialog(url: url, title: title),
    ),
  );
}
/// The full-screen picture itself: a black page, a toolbar, and an
/// [InteractiveViewer] that fits the picture to the window and zooms from there.
///
/// Public because the `show*` helper above is thin: a test may build this
/// directly, the way `YouTubeVideoPlayerDialog` is separated from its own.
class ImageLightboxDialog extends StatefulWidget {
  const ImageLightboxDialog({super.key, required this.url, this.title});

  final String url;
  final String? title;

  /// How much one press of «+» or «−» adds or removes.
  ///
  /// A step rather than a ratio, because of the readout beside the buttons: a
  /// step reads 125%, 150%, 175%, which the eye can follow, where a ×1.25 ratio
  /// reads 125%, 156%, 195%, 244% — numbers nobody checks against anything.
  static const double zoomStep = 0.25;

  /// The smallest and largest scale allowed, gestures and buttons alike.
  ///
  /// One is the picture fitted to the window, and it stays reachable: a viewer
  /// that could shrink the picture below the fitted size would leave the reader
  /// looking at a stamp with no way back but the reset button.
  static const double minScale = 1;
  static const double maxScale = 6;

  @override
  State<ImageLightboxDialog> createState() => _ImageLightboxDialogState();
}

class _ImageLightboxDialogState extends State<ImageLightboxDialog> {
  final _controller = TransformationController();

  /// The viewer, measured when a button needs the viewport's centre — see
  /// [_zoomBy].
  final _viewerKey = GlobalKey();

  /// Same reason as the feed's counter: `CachedNetworkImage` only asks the
  /// network again when its key changes.
  int _retryCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Size get _viewportSize {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? Size.zero;
  }

  /// Adds [delta] to the current scale, keeping the viewport's centre in place.
  ///
  /// Scaling about the matrix's own origin — the top-start corner — would walk
  /// the picture towards the opposite corner on every press; after two presses
  /// the part of the schedule being read would be off the window.
  void _zoomBy(double delta) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current + delta).clamp(
      ImageLightboxDialog.minScale,
      ImageLightboxDialog.maxScale,
    );
    if ((target - current).abs() < 0.001) return;

    final size = _viewportSize;
    if (size.isEmpty) {
      // Not laid out yet. Nothing can be centred against nothing, so the picture
      // is scaled from the top-start corner and the next press is measured
      // against a real viewport.
      _controller.value = Matrix4.identity()
        ..scaleByDouble(target, target, target, 1);
      return;
    }

    // The child fills the viewer, so a scene point and a viewport point are the
    // same point at scale one: the centre can be written in viewport
    // coordinates without going through `toScene`.
    final centre = Offset(size.width / 2, size.height / 2);
    final ratio = target / current;
    _controller.value = _controller.value.clone()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, ratio, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  }

  void _resetZoom() => _controller.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final cacheKey = imageCacheKey(widget.url);

    return CallbackShortcuts(
      // Escape closes, the way every other full-screen viewer on this desktop
      // does. Bound to this dialog rather than to the app: the shortcut exists
      // only while the picture is up, and the app's own key map is untouched.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          // Opaque, not the route's barrier colour: the letterbox around a
          // contained picture belongs to the viewer, so the page behind it must
          // not show through the bars.
          color: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                _buildToolbar(context),
                Expanded(
                  child: InteractiveViewer(
                    key: _viewerKey,
                    transformationController: _controller,
                    minScale: ImageLightboxDialog.minScale,
                    maxScale: ImageLightboxDialog.maxScale,
                    // No slack around the picture: panning past its edge would
                    // show black instead of the row the drag was aimed at.
                    boundaryMargin: EdgeInsets.zero,
                    // The wheel and a pinch are handled by `InteractiveViewer`
                    // itself — a `PointerScrollEvent` is a zoom in its own
                    // `_receivedPointerSignal` — and both write to the same
                    // controller the buttons and the readout read from.
                    child: SizedBox.expand(
                      child: CachedNetworkImage(
                        imageUrl: widget.url,
                        cacheKey: cacheKey,
                        key: ValueKey('$cacheKey-lightbox-$_retryCount'),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => ImageErrorView(
                          // White, not the theme's colour: a dark theme is not
                          // what is behind this — a black viewer is.
                          foreground: Colors.white70,
                          onRetry: () => setState(() => _retryCount++),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final title = widget.title?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          // The first child is the rightmost under RTL, which is the corner this
          // app closes things in — the same corner the video player puts its
          // arrow in.
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(LucideIcons.x, color: Colors.white),
            tooltip: 'إغلاق',
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
            ),
          ] else
            const Spacer(),
          _buildZoomControls(context),
        ],
      ),
    );
  }

  Widget _buildZoomControls(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    const minPercent = 100;
    // Not `const`: `.round()` is a call, and a constant initialiser cannot hold
    // one. `maxScale` is the one source of truth for the ceiling either way.
    final maxPercent = (ImageLightboxDialog.maxScale * 100).round();

    // Bound to the controller so the readout follows the wheel and the pinch as
    // well as the buttons: all three write to the same matrix, and this is the
    // one place where they meet.
    return ValueListenableBuilder<Matrix4>(
      valueListenable: _controller,
      builder: (context, matrix, child) {
        final percent = (matrix.getMaxScaleOnAxis() * 100).round();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: percent > minPercent
                  ? () => _zoomBy(-ImageLightboxDialog.zoomStep)
                  : null,
              icon: const Icon(LucideIcons.zoomOut),
              color: Colors.white,
              disabledColor: Colors.white24,
              tooltip: 'تصغير',
            ),
            SizedBox(
              width: 52,
              child: Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            IconButton(
              onPressed: percent < maxPercent
                  ? () => _zoomBy(ImageLightboxDialog.zoomStep)
                  : null,
              icon: const Icon(LucideIcons.zoomIn),
              color: Colors.white,
              disabledColor: Colors.white24,
              tooltip: 'تكبير',
            ),
            IconButton(
              // Disabled at the fitted size, which is also the only state a pan
              // can do nothing in: with no slack around the picture there is
              // nothing to pan at scale one, so "100%" is the identity matrix.
              onPressed: percent == minPercent ? null : _resetZoom,
              icon: const Icon(LucideIcons.refreshCw),
              color: Colors.white,
              disabledColor: Colors.white24,
              tooltip: 'إعادة الحجم',
            ),
          ],
        );
      },
    );
  }
}

/// What a picture shows when it will not load: a reason and a way to ask again.
///
/// A blank rectangle would read as "the professor attached nothing". It lives
/// beside the viewer rather than in the page because both the note in the feed
/// and the full-screen view draw it — and the two sit on different backgrounds,
/// which is what [foreground] is for.
class ImageErrorView extends StatelessWidget {
  const ImageErrorView({super.key, required this.onRetry, this.foreground});

  final VoidCallback onRetry;

  /// The colour of the icon and the reason. Null follows the theme, which is
  /// right for a note in the feed; the black viewer passes white.
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = foreground ?? theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.imageOff, size: 24, color: color),
          const SizedBox(height: 8),
          Text(
            'فشل تحميل الصورة',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: color,
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text('إعادة المحاولة', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

