import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/folder_announcement.dart';
import '../../models/university_folder.dart';
import '../../utils/relative_date.dart';
// Still imported for `kDashboardNavBarHeight`: the header keeps matching the
// dashboard's navbar height so the two pages line up when the content swaps.
import '../dashboard/dashboard_palette.dart';
import 'announcement_composer.dart';
import 'image_lightbox.dart';

/// The page that takes over the main content area when a folder under
/// "المكتبة الجامعية" is opened in the sidebar.
///
/// It is a sibling of `DashboardPage`, not a section of it: opening a folder
/// replaces the dashboard rather than pushing a route, so the sidebar stays
/// visible and the same click that expands the folder is the click that swaps
/// the page. The slot it fills is the one `_buildNoFilePlaceholder` leaves
/// empty while no PDF is open.
///
/// Everything it renders arrives as a prop. It reads no provider and owns no
/// subscription — `AppProvider` holds the live stream, and
/// `_buildNoFilePlaceholder` hands the result down. That is what keeps this
/// widget pumpable in a test with no Isar and no Firebase behind it.
///
/// Colours come from `Theme.of(context)` and nothing else — the surfaces, the
/// border and the accent all follow the app theme, so the page reads the same
/// in the dark theme the screenshots were taken in and in light mode.
class FolderAnnouncementsView extends StatelessWidget {
  /// The folder whose announcements are on screen. Also what the header names,
  /// so the reader can tell at a glance which subject they are looking at.
  final UniversityFolder folder;

  /// Newest first, as the service returns them.
  final List<FolderAnnouncement> announcements;

  /// True until the first snapshot arrives. Kept separate from "the list is
  /// empty" because a denied read and an empty folder must not look alike.
  final bool isLoading;

  /// True when the live subscription reported an error.
  final bool hasError;

  /// Whether to show the publish bar. Comes from `AppUser.isLecturer`, the same
  /// check the Firestore rules make.
  final bool canPublish;

  /// True while a publish is in flight.
  final bool isPublishing;

  /// Whether a given note may be removed by this reader. A function rather than
  /// a bool because the rule is per-note — an admin removes anything, a lecturer
  /// only their own — and the decision belongs in `AppProvider`, next to the
  /// role it is derived from, not duplicated here.
  final bool Function(FolderAnnouncement announcement) canDelete;

  /// Leaves the announcements and goes back to the dashboard.
  final VoidCallback? onBackToDashboard;

  /// Re-opens the stream after a failure.
  final VoidCallback? onRetry;

  /// Throws to report a failure; the composer catches it and prints the message.
  /// The third argument is the URL of an image the composer has already
  /// uploaded, or null for a text-only note.
  final Future<void> Function(String title, String body, String? imageUrl)?
  onPublish;

  /// Called after the confirmation dialog is accepted.
  final ValueChanged<String>? onDelete;

  const FolderAnnouncementsView({
    super.key,
    required this.folder,
    this.announcements = const [],
    this.isLoading = false,
    this.hasError = false,
    this.canPublish = false,
    this.isPublishing = false,
    this.canDelete = _neverDelete,
    this.onBackToDashboard,
    this.onRetry,
    this.onPublish,
    this.onDelete,
  });

  /// The default for [canDelete]: a reader who was not handed a rule removes
  /// nothing. A static method rather than a closure so it can be a default.
  static bool _neverDelete(FolderAnnouncement announcement) => false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      // The dashboard's own slot is dark whatever the app theme is; using the
      // scaffold colour keeps this page from flashing a different dark than the
      // page it replaced.
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          _AnnouncementsHeader(
            folder: folder,
            count: announcements.length,
            onBackToDashboard: onBackToDashboard,
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(child: _buildBody(context)),
          // Pinned to the bottom edge, the way a chat input is: the newest note
          // in a channel sits directly above it, so posting is always one field
          // away from reading. It closes the page rather than floating.
          if (canPublish && onPublish != null)
            AnnouncementComposer(
              isPublishing: isPublishing,
              onPublish: onPublish!,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (hasError) {
      return _ErrorState(onRetry: onRetry);
    }
    if (isLoading) {
      // A spinner rather than the empty state: "لا توجد إعلانات" before the
      // first snapshot would be a wrong answer dressed as a right one.
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (announcements.isEmpty) {
      return _EmptyState(folderName: folder.name, canPublish: canPublish);
    }

    return ListView.builder(
      // `reverse: true` puts the newest note at the bottom, against the composer
      // — the order of every chat app, and the order a channel is read in. The
      // service hands the notes newest-first, and `reverse` reads that list
      // bottom-up, so index 0 (the newest) lands lowest with no index arithmetic.
      reverse: true,
      // Tighter than the dashboard's page padding: a channel is a wall of
      // bubbles, not a set of cards with air around each one.
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: announcements.length,
      itemBuilder: (context, index) {
        final announcement = announcements[index];
        return Padding(
          // A gap between bubbles rather than a separator item, so the count
          // stays the notes' count. Symmetric, because the reversed list reads
          // the same either way from an RTL layout.
          padding: const EdgeInsets.only(bottom: 8),
          child: _AnnouncementBubble(
            announcement: announcement,
            onDelete: canDelete(announcement) && onDelete != null
                ? () => _confirmDelete(context, announcement)
                : null,
          ),
        );
      },
    );
  }

  /// Deleting a shared note is not undoable from this screen, so it asks first.
  Future<void> _confirmDelete(
    BuildContext context,
    FolderAnnouncement announcement,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text(
          'حذف الإعلان',
          style: TextStyle(fontSize: 16, color: scheme.onSurface),
        ),
        content: Text(
          // `displayTitle`, not `title`: the title may be empty on a note that
          // is only a picture, and `«»` names nothing in a confirmation.
          'سيُحذف «${announcement.displayTitle}» لكل من يقرأ هذا المجلد.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete?.call(announcement.id);
  }
}

/// The pinned bar at the top of the page. Height matches the dashboard's navbar
/// so the two pages' headers line up when the content swaps.
class _AnnouncementsHeader extends StatelessWidget {
  const _AnnouncementsHeader({
    required this.folder,
    required this.count,
    this.onBackToDashboard,
  });

  final UniversityFolder folder;
  final int count;
  final VoidCallback? onBackToDashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: kDashboardNavBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          if (onBackToDashboard != null) ...[
            Tooltip(
              message: 'العودة إلى الرئيسية',
              child: InkWell(
                onTap: onBackToDashboard,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  // Points right, which is "back" on an RTL layout.
                  child: Icon(
                    LucideIcons.arrowRight,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary.withOpacity(0.35)),
            ),
            child: Icon(LucideIcons.megaphone, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'إعلانات المادة',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                '$count إعلان',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One note, as a chat bubble: who posted it and its fixed role badge across
/// the top, the body under that, and the time tucked into the bottom corner.
///
/// A bubble rather than the outlined card this used to be, because the folder is
/// read as a channel — a stream of the professor's posts, newest against the
/// composer — and a channel is drawn in bubbles. The bubble hugs its content
/// but is capped so a wide desktop window does not stretch a two-line note
/// across the whole screen.
///
/// The one exception is a note that carries a picture: it drops the bubble, for
/// the reason written into `build` where the surface is chosen.
class _AnnouncementBubble extends StatelessWidget {
  const _AnnouncementBubble({required this.announcement, this.onDelete});

  final FolderAnnouncement announcement;

  /// Null when this reader may not remove this note, which also hides the
  /// control. There is no disabled trash icon: an action that cannot succeed
  /// should not be offered.
  final VoidCallback? onDelete;

  /// The widest a bubble may grow.
  ///
  /// Past this a single line of prose is hard to scan — the eye loses the start
  /// of the next line — so the bubble stops growing and the text wraps instead.
  static const double maxWidth = 640;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Align(
      // Start is the right edge under RTL, where a channel's posts sit. Only the
      // top-start corner is squared, so the bubble reads as having a source
      // rather than floating in the middle.
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Container(
          // A note that carries a picture is not drawn in a bubble. The picture
          // is the post, and a grey rectangle behind a photograph reads as a
          // frame around a frame — with `BoxFit.contain` drawing two of its own
          // edges inside the note's. Dropping the surface and the padding lets
          // the picture and its caption use the full width of the note, and the
          // picture is read at that size until it is tapped (`showImageLightbox`).
          padding: announcement.hasImage
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: announcement.hasImage
              ? null
              : BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.zero,
                    topEnd: Radius.circular(16),
                    bottomStart: Radius.circular(16),
                    bottomEnd: Radius.circular(16),
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                // `min` so the header hugs its text: a full-width row would
                // stretch every bubble to the cap and there would be no bubble.
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Who posted it, in the accent colour, next to a fixed
                  // «أستاذ» badge. The badge does not claim this author's role
                  // — `FolderAnnouncement` stores no role — it states a fact
                  // about the page: the Firestore rules let only a lecturer or
                  // an admin post here, so every writer on it is one.
                  Flexible(
                    child: Text(
                      announcement.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'أستاذ',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onDelete,
                      icon: Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      tooltip: 'حذف الإعلان',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              // The title is an optional headline under the author line; a
              // photo-only note simply has none and skips the row.
              if (announcement.title.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  announcement.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
              if (announcement.body.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  announcement.body,
                  // Taller than default: these are read as prose, not as labels.
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    height: 1.6,
                    color: scheme.onSurface,
                  ),
                ),
              ],
              if (announcement.hasImage) ...[
                const SizedBox(height: 10),
                _AnnouncementImage(url: announcement.imageUrl!),
              ],
              const SizedBox(height: 6),
              Align(
                // The time tucks into the end corner, where a chat app stamps
                // it: it belongs to the note, not to a header line.
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  formatRelativeDate(announcement.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The image attached to a note.
///
/// Drawn at its own aspect ratio, capped in height. A `ListView` gives each item
/// unbounded height, so a picture left to size itself would push the rest of the
/// channel off screen on a portrait photo — the cap is what keeps the feed a
/// feed. What the cap takes from a tall photo is not lost: a tap opens the same
/// picture full-screen, where it can be enlarged (`showImageLightbox`).
///
/// `contain` rather than `cover` at the cap for the same reason the note exists:
/// a lecture schedule cropped at its last row is worse than a small picture.
///
/// The cache key comes from `imageCacheKey` in `image_lightbox.dart`, shared
/// with the full-screen view so one picture is filed and fetched once.
class _AnnouncementImage extends StatefulWidget {
  const _AnnouncementImage({required this.url});

  final String url;

  /// The tallest a picture may draw in the feed.
  ///
  /// Tall enough to read a schedule on, short enough to leave the top of the
  /// next note visible on a laptop window.
  static const double maxHeight = 420;

  /// The box reserved while the picture is on its way, and the box the failure
  /// message draws in.
  ///
  /// Without it the note would be a spinner's 20px tall and then jump to a
  /// photo's height, dragging everything under it up the screen once the picture
  /// lands.
  static const double placeholderHeight = 200;

  /// The picture's corners. Nothing else shares this number on purpose: it is a
  /// photo, and a rounded edge is what separates it from the page behind it now
  /// that it has no bubble.
  static const double cornerRadius = 14;

  @override
  State<_AnnouncementImage> createState() => _AnnouncementImageState();
}

class _AnnouncementImageState extends State<_AnnouncementImage> {
  /// Bumped by the retry button, and part of the image's key.
  ///
  /// It is the only way to make `CachedNetworkImage` ask the network again:
  /// without it the widget rebuilds into the same failed cache entry, and the
  /// button looks dead.
  int _retryCount = 0;

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final cacheKey = imageCacheKey(url);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_AnnouncementImage.cornerRadius),
      child: MouseRegion(
        // Desktop-first: without this the picture is the one thing on the page
        // that gives no sign it can be pressed.
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Opaque, so the whole picture is the target and not only the pixels
          // the photo happens to draw. The retry control inside the error state
          // stays reachable: it sits deeper in the tree, and the deeper
          // recogniser is the one that wins the tap.
          behavior: HitTestBehavior.opaque,
          onTap: () => showImageLightbox(context, url: url),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: _AnnouncementImage.maxHeight,
            ),
            child: CachedNetworkImage(
              imageUrl: url,
              cacheKey: cacheKey,
              key: ValueKey('$cacheKey-$_retryCount'),
              fit: BoxFit.contain,
              placeholder: (context, url) => const SizedBox(
                width: double.infinity,
                height: _AnnouncementImage.placeholderHeight,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => SizedBox(
                width: double.infinity,
                height: _AnnouncementImage.placeholderHeight,
                child: ImageErrorView(
                  onRetry: () => setState(() => _retryCount++),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the folder has nothing posted in it yet.
///
/// The second line changes for staff: a student is told to wait, and a
/// professor is told where the control is. The same empty box with the same
/// sentence for both would leave the one person who can fix it looking for a
/// button that is on screen but unmentioned.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.folderName, required this.canPublish});

  final String folderName;
  final bool canPublish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(
                LucideIcons.megaphoneOff,
                size: 26,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد إعلانات لهذه المادة بعد',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canPublish
                  ? 'ابدأ بنشر أول إعلان من الشريط في الأسفل.'
                  : 'ستظهر هنا ملاحظات وإعلانات أستاذ «$folderName» فور نشرها.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the live subscription reported an error — a rule that is not
/// deployed, a denied read, a dead network.
///
/// Separate from the empty state on purpose. "لا توجد إعلانات" for a read that
/// was refused is not a lesser answer, it is a false one: the folder may be full
/// and the reader is told it is empty.
class _ErrorState extends StatelessWidget {
  const _ErrorState({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.cloudOff,
              size: 28,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'تعذّر تحميل الإعلانات',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'تحقّق من الاتصال ثم أعد المحاولة.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
