import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/folder_announcement.dart';
import '../../models/university_folder.dart';
import '../../utils/relative_date.dart';
import '../dashboard/dashboard_palette.dart';
import 'announcement_composer.dart';

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
          // Under the list, and after it in the tree as well as on screen: the
          // notes are what the page is for, and the control that adds one is
          // used once a week. The order here is the order the reader sees.
          if (canPublish && onPublish != null)
            AnnouncementComposer(
              folderName: folder.name,
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
      // Same padding as the dashboard's content, so switching between the two
      // does not shift the left edge of anything.
      padding: const EdgeInsets.all(kDashboardPagePadding),
      itemCount: announcements.length,
      itemBuilder: (context, index) {
        final announcement = announcements[index];
        return Padding(
          // A gap under every card but the last, rather than a separator item,
          // so the count stays the notes' count.
          padding: EdgeInsets.only(
            bottom: index == announcements.length - 1 ? 0 : 14,
          ),
          child: _AnnouncementCard(
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

/// One note, as a card: who wrote it and when across the top, the body under
/// it. The card is the same rounded, outlined surface the dashboard's cards
/// use, so the two pages do not look like two different apps.
class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement, this.onDelete});

  final FolderAnnouncement announcement;

  /// Null when this reader may not remove this note, which also hides the
  /// control. There is no disabled trash icon: an action that cannot succeed
  /// should not be offered.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.graduationCap,
                  size: 17,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Skipped rather than rendered empty: a note that is only a
                    // picture would otherwise open with a blank bold line and a
                    // gap where a headline should be.
                    if (announcement.title.trim().isNotEmpty) ...[
                      Text(
                        announcement.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    // Author and date on one line: on a wide window the two
                    // belong together, and reading them as a pair is faster
                    // than scanning two separate columns.
                    Text(
                      '${announcement.authorName} · '
                      '${formatRelativeDate(announcement.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  tooltip: 'حذف الإعلان',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (announcement.body.trim().isNotEmpty)
            Text(
              announcement.body,
              // Taller than default: these are read as prose, not as labels.
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (announcement.hasImage) ...[
            const SizedBox(height: 14),
            _AnnouncementImage(url: announcement.imageUrl!),
          ],
        ],
      ),
    );
  }
}

/// The image attached to a note.
///
/// A fixed height with `BoxFit.contain`. A `ListView` gives each item unbounded
/// height, so an image left to size itself would push the next card off screen
/// on a portrait photo; and `cover` would crop a lecture schedule exactly where
/// its last row is. `contain` at a fixed height shows all of it, letterboxed.
class _AnnouncementImage extends StatefulWidget {
  const _AnnouncementImage({required this.url});

  final String url;

  /// Tall enough to read a schedule on, short enough to leave the top of the
  /// next card visible on a laptop window.
  static const double height = 300;

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
    final scheme = Theme.of(context).colorScheme;
    final url = widget.url;
    // The query string carries a per-request token, so a key built from the
    // whole URL would miss the disk cache on every rebuild and re-download the
    // same picture — the same treatment `DraggableTextWidget` gives an
    // attachment.
    final stableCacheKey = url.contains('?') ? url.split('?').first : url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: _AnnouncementImage.height,
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: stableCacheKey,
          key: ValueKey('$stableCacheKey-$_retryCount'),
          fit: BoxFit.contain,
          placeholder: (context, url) => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) =>
              _ImageError(onRetry: () => setState(() => _retryCount++)),
        ),
      ),
    );
  }
}

/// What a note shows when its image will not load: a reason and a way to ask
/// again. A blank rectangle would read as "the professor attached nothing".
class _ImageError extends StatelessWidget {
  const _ImageError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.imageOff, size: 24, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'فشل تحميل الصورة',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
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
