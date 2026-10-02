import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// The in-app update: what the new version is, a download with real progress,
/// and the installer starting itself.
///
/// It exists because the alternative was a dead button. The soft-update dialog
/// offered «تحديث الآن» and did nothing (`_kUpdateUrl` was the empty string),
/// and the forced-update screen sent the reader to a chat app to ask for the
/// file by hand — which is not an update, it is a support ticket.
///
/// A screen rather than a dialog on purpose. `VersionCheckGate` sits *above*
/// `MaterialApp` (`main.dart` wraps the app in it, not the other way round), so a
/// `showDialog` from there finds no `Navigator` above it — and no
/// `MaterialLocalizations` either, which is exactly what the guard in
/// `version_check_gate.dart` checks and returns early on. A dialog offered from
/// that position cannot appear. The gate renders this instead, over the running
/// app, and takes it away again through [onClose].
///
/// [service] is injectable, so a widget test drives every stage without a
/// network — the same treatment `AnnouncementComposer.pickImage` gets.
/// [quit] is called once the installer has started, because the app has to be
/// gone for Setup to replace its own files; it is injectable for the same reason
/// — `exit(0)` in a test takes the test process with it.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({
    super.key,
    required this.service,
    this.release,
    this.onClose,
    this.quit,
    this.autoInstall = false,
  });

  final UpdateService service;

  /// A release already fetched by the caller, so the gate does not ask GitHub
  /// twice for the same answer. Null means "ask now".
  final UpdateRelease? release;

  /// How the reader gets back to the app. Null means the screen stays: the
  /// forced-update case blocks everything until the update happens.
  final VoidCallback? onClose;

  /// How the app leaves the way for the installer. Null means `exit(0)`.
  final void Function()? quit;

  /// Download and install without being asked.
  ///
  /// The forced-update case sets this. A reader who may not use the app until it
  /// is updated should not have to find a button to say yes to the only thing
  /// they can do — and the button being missed is exactly how the old forced
  /// screen left them stuck with a release page they did not understand. A
  /// failure is still shown and still offers the page: this removes the question,
  /// not the way out.
  final bool autoInstall;

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

/// The stages the screen can be in, in the order they happen.
enum _UpdateStage {
  /// Asking GitHub what the newest release is.
  checking,

  /// A release is known: show what is new and offer to install it.
  ready,

  /// The installer is coming down.
  downloading,

  /// The size and the SHA-256 are being checked.
  verifying,

  /// Setup has been started; the app is about to go.
  installing,

  /// Nothing can be done here; the release page is the way out.
  failed,
}

class _UpdateScreenState extends State<UpdateScreen> {
  late _UpdateStage _stage;
  UpdateRelease? _release;
  String? _error;

  /// True once this screen has a release to work from — either the one the gate
  /// already fetched, or one fetched here.
  ///
  /// [widget.release] is the normal answer, and it can still be null while a
  /// release exists: the launch check asks Firestore and GitHub together, and the
  /// database may have been the side that failed. In that case this screen asks
  /// GitHub itself — once, not per rebuild.
  bool _loaded = false;

  /// True once a download has been started, so a rebuild cannot start a second
  /// one on top of the first.
  bool _installStarted = false;

  /// How many install attempts have failed. Not shown to the reader: it is what
  /// decides that the automatic attempt is over and the screen stops driving
  /// itself.
  int _failures = 0;

  /// Set when the screen is taken away while the download is running.
  ///
  /// The transfer cannot be aborted mid-chunk from here — `http` has no handle
  /// for it once the stream is being read — so the bytes keep arriving and are
  /// then left alone: what was cancelled is the *install*, not the wire. The next
  /// attempt overwrites the same versioned file.
  bool _cancelled = false;

  int _received = 0;
  int? _total;

  @override
  void initState() {
    super.initState();
    _release = widget.release;
    _loaded = _release != null;
    _stage = _loaded ? _UpdateStage.ready : _UpdateStage.checking;
    // One frame later: this runs from `initState`, where `setState` is not
    // allowed, and the frame also lets the checking stage be seen before GitHub
    // is asked — which is the honest order, the reader sees what is happening.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  /// Whatever has to happen without a button being pressed.
  ///
  /// Decided here rather than in `build`, where it would run on every rebuild —
  /// the forced update would then start its download again on each frame.
  void _start() {
    if (!_loaded) {
      _load();
      return;
    }
    _maybeAutoInstall();
  }

  /// Downloads and installs on its own, for the forced case, once.
  ///
  /// Deliberately not retried after a failure: a network that is down is not
  /// fixed by trying again in a loop, and the reader has to be able to read what
  /// went wrong. [UpdateScreen.autoInstall] says why this exists at all.
  void _maybeAutoInstall() {
    if (!widget.autoInstall) return;
    if (_installStarted || _failures > 0) return;
    if (_stage != _UpdateStage.ready) return;

    if (!(_release?.isDownloadable ?? false)) {
      // There is nothing to install, so waiting forever is worse than saying so:
      // the page link in the failed stage is the only thing that can help.
      setState(() {
        _stage = _UpdateStage.failed;
        _error =
            'هذا الإصدار لم يُرفق به ملف تنصيب، فالتحديث من صفحة الإصدارات.';
      });
      return;
    }
    _install();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _load() async {
    final release = await widget.service.latestRelease();
    if (!mounted) return;

    if (release == null) {
      // Straight to the failure, with no `setState` in between. Staging through
      // `ready` first — which the automatic path then rejects one call later —
      // set the stage twice in the same event-loop turn, so the reader saw the
      // checking spinner flash after the answer had already arrived.
      setState(() {
        _release = null;
        _loaded = false;
        _stage = _UpdateStage.failed;
        _error = 'لا يوجد تحديث منشور الآن، أو تعذّر الوصول إلى GitHub.';
      });
      return;
    }

    setState(() {
      _release = release;
      _loaded = true;
      _stage = _UpdateStage.ready;
      _error = null;
    });

    // Asked only now that a release is known, and only for the forced case: a
    // release that carries no file has nothing to install, and `_maybeAutoInstall`
    // says so rather than waiting.
    _maybeAutoInstall();
  }

  Future<void> _install() async {
    final release = _release;
    if (release == null) return;

    // The guard against a second download on the same screen. `_install` is
    // reached from a button and from the automatic path, and both can fire on
    // the same rebuild.
    if (_installStarted) return;
    _installStarted = true;

    setState(() {
      _stage = _UpdateStage.downloading;
      _received = 0;
      _total = release.downloadSize;
      _error = null;
    });

    try {
      final file = await widget.service.downloadInstaller(
        release,
        onProgress: (received, total) {
          if (!mounted || _cancelled) return;
          setState(() {
            _received = received;
            _total = total ?? _total;
          });
        },
      );

      if (!mounted || _cancelled) return;
      setState(() => _stage = _UpdateStage.verifying);

      if (!await widget.service.verify(file, release)) {
        if (!mounted) return;
        setState(() {
          _failures++;
          _installStarted = false;
          _stage = _UpdateStage.failed;
          _error =
              'الملف المنزَّل لا يطابق ما نشرَه المطوّر، ولم يُشغَّل. '
              'حاول مرة أخرى، أو نزّله من صفحة الإصدارات.';
        });
        return;
      }

      if (!mounted) return;
      setState(() => _stage = _UpdateStage.installing);
      await widget.service.runInstaller(file);
      if (!mounted) return;
      (widget.quit ?? _defaultQuit)();
    } on UpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _failures++;
        _installStarted = false;
        _stage = _UpdateStage.failed;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failures++;
        _installStarted = false;
        _stage = _UpdateStage.failed;
        _error = 'تعذّر إكمال التحديث: $error';
      });
    }
  }

  static void _defaultQuit() => exit(0);

  @override
  Widget build(BuildContext context) {
    final actions = _actions();

    return Directionality(
      // RTL by hand: this renders above the `MaterialApp` that would otherwise
      // decide the direction, exactly like the forced-update screen beside it.
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: const Color(0xB3000000),
        child: Center(
          child: Container(
            // A fixed panel. The height cap is what lets the body scroll
            // instead of pushing past the window, and the width is the only
            // thing the children may wrap against — see the `SizedBox` around
            // `_step` below for why stating it here is not enough.
            width: 460,
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: MediaQuery.sizeOf(context).height - 80,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              // The same dark blue the forced-update modal uses: this is a
              // launch-time screen, and it must not change with the app theme.
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.system_update_alt_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _title(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // The width has to be forced onto the body, not just offered to
                // the panel. `Center` above gives the panel an unbounded width,
                // and a `Column` with `MainAxisSize.min` then shrink-wraps to its
                // widest child instead of taking the panel's width — so a plain
                // paragraph was laid out unbounded and measured 1232px inside a
                // 418px panel (a `RenderFlex overflowed by 708 pixels`). Every
                // row here is an `Expanded` or controlled, so the widest child
                // reported 418 and hid the fault; the `installing` and `failed`
                // messages are the two that showed it. `width: double.infinity`
                // inside a `Flexible` is what makes the body take the width it
                // was given instead of shrinking to fit.
                Flexible(
                  child: SingleChildScrollView(
                    child: SizedBox(width: double.infinity, child: _step()),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  // `Wrap` and not `Row`: the ready stage has three buttons —
                  // the page link, «لاحقاً» and «تنزيل التحديث وتثبيته» — and
                  // Arabic labels plus two text buttons are wider than the panel.
                  // A `Row` overflowed by 128px and simply hid the download
                  // button off the edge, which is the one button that matters.
                  // Wrapping drops the extra buttons to a second line instead.
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 4,
                      children: actions,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _title() {
    switch (_stage) {
      case _UpdateStage.checking:
        return 'التحقق من التحديثات';
      case _UpdateStage.ready:
        return 'تحديث متاح';
      case _UpdateStage.downloading:
        return 'جارٍ تنزيل التحديث';
      case _UpdateStage.verifying:
        return 'التحقق من الملف';
      case _UpdateStage.installing:
        return 'جارٍ التثبيت';
      case _UpdateStage.failed:
        return 'تعذّر إكمال التحديث';
    }
  }

  /// The body of the panel for the current stage.
  ///
  /// Laid out inside a `Flexible` + `SingleChildScrollView` + forced-width
  /// `SizedBox`, so a long message wraps and scrolls instead of overflowing —
  /// see the comment at that call site in `build`.
  Widget _step() {
    switch (_stage) {
      case _UpdateStage.checking:
        return const _Busy(text: 'جارٍ السؤال عن أحدث إصدار…');

      case _UpdateStage.ready:
        return _readyContent();

      case _UpdateStage.downloading:
        final total = _total;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              // Known total → a real bar; unknown → a moving one. A bar parked at
              // 90% because the server never declared a length is worse than no
              // bar at all.
              value: total != null && total > 0 ? _received / total : null,
            ),
            const SizedBox(height: 12),
            Text(
              total != null && total > 0
                  ? '${((_received / total) * 100).round()}% — '
                        '${_formatBytes(_received)} من ${_formatBytes(total)}'
                  : 'تم تنزيل ${_formatBytes(_received)}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'التنزيل من GitHub Releases مباشرة إلى جهازك.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        );

      case _UpdateStage.verifying:
        return const _Busy(text: 'جارٍ التحقق من حجم الملف وبصمته…');

      case _UpdateStage.installing:
        return const Text(
          'سيتوقف التطبيق الآن، ويُثبَّت التحديث بدون أي نوافذ، ثم يعود من نفسه '
          'بالنسخة الجديدة. لا تغلقه من مدير المهام في هذه اللحظة.',
          style: TextStyle(color: Colors.white, height: 1.6),
        );

      case _UpdateStage.failed:
        return Text(
          _error ?? 'تعذّر التحديث.',
          style: const TextStyle(color: Color(0xFFFCA5A5), height: 1.6),
        );
    }
  }

  Widget _readyContent() {
    final release = _release!;
    final size = release.downloadSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الإصدار الجديد: ${release.version}',
          style: const TextStyle(color: Colors.white),
        ),
        if (size != null) ...[
          const SizedBox(height: 4),
          Text(
            'حجم التنزيل: ${_formatBytes(size)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
        if (release.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: Text(
                release.notes,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
        if (!release.isDownloadable) ...[
          const SizedBox(height: 12),
          const Text(
            'هذا الإصدار لم يُرفق به ملف تنصيب، فالتنزيل من صفحة الإصدارات.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  List<Widget> _actions() {
    switch (_stage) {
      case _UpdateStage.checking:
      case _UpdateStage.downloading:
        return [_cancelButton()];

      case _UpdateStage.ready:
        return [
          _linkButton('صفحة الإصدارات'),
          if (widget.onClose != null) _textButton('لاحقاً', widget.onClose!),
          if (_release!.isDownloadable)
            _primaryButton('تنزيل التحديث وتثبيته', _install),
        ];

      case _UpdateStage.verifying:
      case _UpdateStage.installing:
        // No way out while Setup is taking over: leaving here would leave the
        // reader unsure whether the install happened at all.
        return const [];

      case _UpdateStage.failed:
        return [
          _linkButton('صفحة الإصدارات'),
          if (_release?.isDownloadable ?? false)
            _primaryButton('إعادة المحاولة', _install),
          if (widget.onClose != null) _textButton('إغلاق', widget.onClose!),
        ];
    }
  }

  Widget _cancelButton() => _textButton('إلغاء', _cancel);

  /// Cancelling means putting the screen away, not stopping the wire — see
  /// [_cancelled].
  void _cancel() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      _cancelled = true;
    }
  }

  Widget _primaryButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B82F6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _textButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(color: Colors.white70)),
    );
  }

  /// Always the release page, which exists even when the download does not.
  Widget _linkButton(String label) {
    return TextButton(
      onPressed: _openPage,
      child: Text(label, style: const TextStyle(color: Color(0xFF93C5FD))),
    );
  }

  Future<void> _openPage() async {
    final url = _release?.pageUrl ?? kUpdateReleasesPage;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// `52.4 م.ب` — one decimal, because seeing the number move matters more to the
  /// reader than the difference between 118 and 118.4.
  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
  }
}

/// A spinner and a sentence, for the two stages that are only waiting.
class _Busy extends StatelessWidget {
  const _Busy({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
