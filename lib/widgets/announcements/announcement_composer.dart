import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/folder_announcement.dart';
import '../../utils/image_upload_helper.dart';

/// The publish bar on the announcements page: the input row of a channel.
///
/// It sits at the bottom edge and stays there, the way a chat app's input does.
/// There is no collapsed state and no title field — a channel post is one line
/// of text plus an optional picture, and the poster types it in the same place
/// every time. The folder the note lands in is named by the header directly
/// above, so the bar does not repeat it.
///
/// The whole row is one field (the message), two icon buttons (attach, send)
/// and, once a picture is chosen, its preview above them. The field grows up to
/// five lines and then scrolls, so a long note is not hidden behind a one-line
/// box.
///
/// Only rendered for staff. Whether the reader *may* publish is decided by the
/// caller (`AppProvider.canPublishAnnouncement`, which is the same
/// `AppUser.isLecturer` the Firestore rules check), so this widget never has to
/// know about roles.
class AnnouncementComposer extends StatefulWidget {
  /// True while a publish is in flight. The send button shows a spinner and
  /// stops accepting taps, rather than letting a second write start on top of
  /// the first.
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
  /// under the field, and leaves the draft in place so nothing typed is lost.
  ///
  /// The first argument is the title, kept in the signature for the model and
  /// the service even though the channel UI no longer collects one: it is sent
  /// as the empty string, which `FolderAnnouncement` treats as a finished
  /// note's shape rather than a half-filled draft. The third is the attached
  /// image's URL, or null for a text-only note.
  final Future<void> Function(String title, String body, String? imageUrl)
  onPublish;

  const AnnouncementComposer({
    super.key,
    required this.isPublishing,
    required this.onPublish,
    this.pickImage = pickAndUploadImage,
  });

  @override
  State<AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<AnnouncementComposer> {
  final TextEditingController _bodyController = TextEditingController();

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
    _bodyController.dispose();
    super.dispose();
  }

  /// The sentence to show under the field for [error].
  ///
  /// Read off the object rather than trimmed off `toString()`, because those
  /// wrappers do not share their class name: `UnsupportedError('...').toString()`
  /// is `"Unsupported operation: ..."` and `ArgumentError('...').toString()` is
  /// `"Invalid argument(s): ..."`. Matching on the type is what makes this
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
    final body = _bodyController.text.trim();

    // The model's rule, not a copy of it — the service applies the same one and
    // would otherwise have to reject what the bar just accepted. The title is
    // empty by design, so this reduces to "text or picture".
    final invalid = FolderAnnouncement.validationMessage(
      title: '',
      body: body,
      imageUrl: _imageUrl,
    );
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() => _error = null);
    try {
      await widget.onPublish('', body, _imageUrl);
      if (!mounted) return;
      _bodyController.clear();
      setState(() {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      // A surface of its own, told apart from the feed above by tone and a
      // hairline, the way a channel's input bar is its own strip. No shadow:
      // a shadow on an already-toned strip reads as a smudge.
      //
      // `surface` and not a `surfaceContainer*` step: this page follows the app
      // theme (`folder_announcements_view.dart` paints itself with
      // `scaffoldBackgroundColor`), and the container roles the app never
      // re-mapped — `High` among them, see `lib/main.dart` — still hold
      // `ThemeData.light()`'s lavender neutrals, which sit apart from the
      // slate palette. `surface` is the app's own bar colour, one step away
      // from the field inside it, which is filled with
      // `surfaceContainerHighest`.
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_imageUrl != null) ...[
            _buildImagePreview(scheme),
            const SizedBox(height: 8),
          ],
          Row(
            // The buttons stay level with the *bottom* of the field: as the note
            // grows to several lines the send button should sit by the last line
            // typed, not float beside the first. A chat input behaves this way.
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildAttachButton(scheme),
              const SizedBox(width: 8),
              Expanded(child: _buildField(scheme)),
              const SizedBox(width: 8),
              _buildSendButton(scheme),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The one field: the note itself.
  ///
  /// `minLines: 1` / `maxLines: 5` with no visible border inside a rounded
  /// pill — the shape every messaging app uses, and the shape that makes "type
  /// and press send" obvious without a label.
  Widget _buildField(ColorScheme scheme) {
    return TextField(
      controller: _bodyController,
      enabled: !widget.isPublishing,
      minLines: 1,
      maxLines: 5,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      maxLength: FolderAnnouncement.maxBodyLength,
      style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
      decoration: InputDecoration(
        hintText: 'اكتب إعلاناً...',
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        // The counter would reserve a line under the field for a number nobody
        // reads; the model's limit is still enforced by `maxLength` and reported
        // by `validationMessage`.
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
      ),
    );
  }

  /// The attach control: a paperclip-style icon, not a labelled button.
  ///
  /// Its tooltip changes once something is attached, so the same control reads
  /// as "add" before and "change" after without a word ever appearing on screen.
  Widget _buildAttachButton(ColorScheme scheme) {
    final busy = _isUploadingImage || widget.isPublishing;
    final hasImage = _imageUrl != null;

    return IconButton(
      onPressed: busy ? null : _pickImage,
      icon: _isUploadingImage
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              hasImage ? LucideIcons.imagePlus : LucideIcons.image,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
      tooltip: hasImage ? 'تغيير الصورة' : 'إرفاق صورة',
      style: IconButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(10),
      ),
    );
  }

  /// The send control. Filled with the accent so it is the one thing on the bar
  /// that reads as the action, and a spinner in its place while a write is out.
  Widget _buildSendButton(ColorScheme scheme) {
    return IconButton(
      onPressed: widget.isPublishing ? null : _submit,
      icon: widget.isPublishing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.send, size: 18),
      tooltip: 'نشر',
      style: IconButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.primary.withOpacity(0.5),
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(10),
      ),
    );
  }

  /// The attached picture, above the field, with a corner X that undoes it.
  ///
  /// A thumbnail rather than a filename: the question a poster asks before
  /// sending is "is this the picture I meant", and `IMG_4821.jpg` never answers
  /// it. Removing is one tap on the picture itself, because that is where the
  /// eye already is and a bar with no undo has to make the way out obvious.
  Widget _buildImagePreview(ColorScheme scheme) {
    final url = _imageUrl!;
    final busy = _isUploadingImage || widget.isPublishing;

    return Tooltip(
      message: 'إزالة الصورة',
      child: InkWell(
        // Dropping the URL is the whole of "removed": the file is already in
        // the bucket, and sweeping an orphan out of storage is a job for
        // something that runs on a schedule, not for a bar that may still be
        // cancelled.
        onTap: busy ? null : () => setState(() => _imageUrl = null),
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: url,
                // The query string carries a per-request token, so a cache key
                // built from the whole URL would miss the disk cache on every
                // rebuild and re-download the same picture.
                cacheKey: url.contains('?') ? url.split('?').first : url,
                width: 72,
                height: 72,
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
              top: -6,
              right: -6,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surfaceContainerHigh,
                    width: 1.5,
                  ),
                ),
                child: Icon(LucideIcons.x, size: 12, color: scheme.onError),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
