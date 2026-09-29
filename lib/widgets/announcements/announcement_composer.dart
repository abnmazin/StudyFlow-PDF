import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/folder_announcement.dart';
import '../../utils/image_upload_helper.dart';

/// The publish bar on the announcements page.
///
/// It sits *under* the list, not over it: the page's job is to show the notes,
/// and a composer on top pushes the newest one — the one the reader came for —
/// below the fold. At the bottom the eye still finds the notes first, which is
/// the order they are wanted in.
///
/// Collapsed it is one row, and tapping it opens the fields plus an attach
/// control. It starts collapsed on purpose: open, it holds four lines of height
/// for the sake of a control that is used once a week.
///
/// Only rendered for staff. Whether the reader *may* publish is decided by the
/// caller (`AppProvider.canPublishAnnouncement`, which is the same
/// `AppUser.isLecturer` the Firestore rules check), so this widget never has to
/// know about roles.
class AnnouncementComposer extends StatefulWidget {
  /// Names the folder in the bar, so it is obvious where the note will land.
  final String folderName;

  /// True while a publish is in flight. The button shows a spinner and stops
  /// accepting taps, rather than letting a second write start on top of the
  /// first.
  final bool isPublishing;

  /// Picks one image and returns its uploaded URL, or null when the dialog was
  /// dismissed.
  ///
  /// A field defaulting to `pickAndUploadImage`, not a hard call to it: the
  /// real one opens a native dialog and talks to Supabase Storage, and a widget
  /// test can reach neither. The states worth holding in place here are what
  /// the bar does with the answer.
  final Future<String?> Function() pickImage;

  /// Throws to report a failure. The composer catches it, prints the message
  /// under the fields, and leaves the draft in place so nothing typed is lost.
  /// The third argument is the attached image's URL, or null for a text-only
  /// note.
  final Future<void> Function(String title, String body, String? imageUrl)
  onPublish;

  const AnnouncementComposer({
    super.key,
    required this.folderName,
    required this.isPublishing,
    required this.onPublish,
    this.pickImage = pickAndUploadImage,
  });

  @override
  State<AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<AnnouncementComposer> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  bool _expanded = false;
  String? _error;

  /// The uploaded URL of the image attached to the draft, or null.
  ///
  /// A URL and not a `File`: the image is in Supabase Storage before anything
  /// shows it, so the draft holds exactly what the published note will hold and
  /// the preview is the picture that will actually appear.
  String? _imageUrl;

  bool _isUploadingImage = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// The sentence to show under the fields for [error].
  ///
  /// Read off the object rather than trimmed off `toString()`, because those
  /// wrappers do not share their class name: `UnsupportedError('…').toString()`
  /// is `"Unsupported operation: …"` and `ArgumentError('…').toString()` is
  /// `"Invalid argument(s): …"`. Matching on the type is what makes this
  /// survive a rewording of the framework's prefix.
  static String _messageOf(Object error) {
    // `UnsupportedError.message` is nullable in this SDK, so every branch is
    // funnelled through one nullable local rather than cast at each return.
    String? message;
    if (error is ArgumentError) {
      message = error.message == null ? null : '${error.message}';
    } else if (error is StateError) {
      message = error.message;
    } else if (error is UnsupportedError) {
      message = error.message;
    }
    if (message != null && message.isNotEmpty) return message;
    return error.toString();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    // The model's rule, not a copy of it — the service applies the same one and
    // would otherwise have to reject what the form just accepted.
    final invalid = FolderAnnouncement.validationMessage(
      title: title,
      body: body,
      imageUrl: _imageUrl,
    );
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() => _error = null);
    try {
      await widget.onPublish(title, body, _imageUrl);
      if (!mounted) return;
      _titleController.clear();
      _bodyController.clear();
      setState(() {
        _expanded = false;
        // Cleared with the text: the next note starts from nothing, and an
        // image left in `_imageUrl` would attach itself to a note written
        // after the reader had already forgotten about it.
        _imageUrl = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageOf(e));
    }
  }

  /// Asks for an image and keeps its uploaded URL until the note is published
  /// or the reader removes it.
  ///
  /// The wait lives here rather than on the page so the spinner sits on the
  /// button that was pressed. A dismissed dialog answers null and changes
  /// nothing — the draft keeps whatever it had.
  Future<void> _pickImage() async {
    if (_isUploadingImage || widget.isPublishing) return;

    setState(() {
      _isUploadingImage = true;
      _error = null;
    });
    try {
      final url = await widget.pickImage();
      if (!mounted) return;
      if (url != null && url.trim().isNotEmpty) {
        setState(() => _imageUrl = url.trim());
      }
    } catch (e) {
      // Reported rather than swallowed: a button that does nothing and says
      // nothing is the one failure a reader cannot work around.
      if (!mounted) return;
      setState(() => _error = _messageOf(e));
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  /// The attach control and, once something is attached, its preview.
  ///
  /// A thumbnail rather than a filename: the question a poster asks before
  /// publishing is "is this the picture I meant", and `IMG_4821.jpg` never
  /// answers it. Removing is one tap on the picture itself, because that is
  /// where the eye already is and a form with no undo has to make the way out
  /// obvious.
  Widget _buildImageRow(ColorScheme scheme) {
    final url = _imageUrl;
    final busy = _isUploadingImage || widget.isPublishing;

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : _pickImage,
          icon: _isUploadingImage
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.imagePlus, size: 15),
          label: Text(
            _isUploadingImage
                ? 'جارٍ رفع الصورة…'
                : (url == null ? 'إرفاق صورة' : 'تغيير الصورة'),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        if (url != null) ...[
          const SizedBox(width: 12),
          Tooltip(
            message: 'إزالة الصورة',
            child: InkWell(
              // Dropping the URL is the whole of "removed": the file is already
              // in the bucket, and sweeping an orphan out of storage is a job
              // for something that runs on a schedule, not for a form that may
              // still be cancelled.
              onTap: busy ? null : () => setState(() => _imageUrl = null),
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      // The query string carries a per-request token, so a cache
                      // key built from the whole URL would miss the disk cache
                      // on every rebuild and re-download the same picture.
                      cacheKey: url.contains('?') ? url.split('?').first : url,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Icon(
                        LucideIcons.imageOff,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // The X sits on the corner of the picture it undoes.
                  Positioned(
                    top: -5,
                    left: -5,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.surfaceContainerHigh,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        LucideIcons.x,
                        size: 11,
                        color: scheme.onError,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      // Bottom padding, not top: the bar closes the page from underneath now,
      // so its air belongs between it and the window's edge. The list above it
      // has its own padding and does not need a gap added here.
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      // `AnimatedSize` rather than an `AnimatedCrossFade`: the two states are
      // the same container at two heights, and the bar should grow into the
      // form rather than swap one widget for another.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        // It grows upwards, away from the bottom edge it is anchored to. With
        // `topCenter` the open form would hang down over the edge instead of
        // pushing the bar's own row down out of the way.
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: _expanded
              ? _buildExpanded(context, scheme)
              : _buildBar(scheme),
        ),
      ),
    );
  }

  Widget _buildBar(ColorScheme scheme) {
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(LucideIcons.megaphone, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'نشر إعلان جديد في «${widget.folderName}»',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              // Points up, where the form opens to.
              LucideIcons.chevronUp,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.megaphone, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'إعلان جديد في «${widget.folderName}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.isPublishing
                    ? null
                    : () => setState(() {
                        _expanded = false;
                        _error = null;
                      }),
                icon: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                tooltip: 'إلغاء',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            enabled: !widget.isPublishing,
            textInputAction: TextInputAction.next,
            maxLength: FolderAnnouncement.maxTitleLength,
            style: TextStyle(fontSize: 14, color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: 'عنوان الإعلان (اختياري)',
              // The counter would reserve a line under the field for a number
              // nobody reads; the model's limit is still enforced by
              // `maxLength` and reported by `validationMessage`.
              counterText: '',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bodyController,
            enabled: !widget.isPublishing,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: 'نص الإعلان…',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildImageRow(scheme),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_error != null)
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: widget.isPublishing ? null : _submit,
                icon: widget.isPublishing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.send, size: 16),
                label: Text(
                  widget.isPublishing ? 'جارٍ النشر…' : 'نشر',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
