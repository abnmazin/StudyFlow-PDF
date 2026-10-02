import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../utils/responsive_utils.dart';

/// The stages an update goes through, all of them after the button.
///
/// There is no `checking` stage before it and nothing starts on its own: the
/// reader presses «تحديث الآن», and this modal becomes the download screen in
/// place. A second page stacked on top of this one is what the forced launch
/// used to show, and the reader was left looking at two screens that both said
/// an update was happening.
enum _UpdateStage {
  /// Nothing started yet; the button is on screen.
  ready,

  /// Asking GitHub which release is newest — only when the launch check did not
  /// already hand one over.
  loading,

  /// The installer is coming down.
  downloading,

  /// The size and the SHA-256 are being checked.
  verifying,

  /// Setup has been started; the app is about to go.
  installing,

  /// Nothing can be done here; the release page is the way out.
  failed,
}

class DeveloperModal extends StatefulWidget {
  final bool isVisible;
  final VoidCallback? onClose;
  final bool isForceUpdate;
  final String currentVersion;
  final String requiredVersion;

  /// The newest build, shown when the update is optional rather than required.
  final String latestVersion;

  /// How the update is carried out, or null when this modal is only information.
  ///
  /// Null is `main.dart`'s developer panel, opened from inside the app; the
  /// forced screen always passes one. It is injectable so a widget test drives
  /// every stage without a network — the same treatment `UpdateScreen.service`
  /// used to get, and the reason that widget could be tested at all.
  final UpdateService? service;

  /// A release the launch check already fetched, so one launch does not ask
  /// GitHub the same question twice. Null means "ask when the button is
  /// pressed".
  final UpdateRelease? release;

  /// How the app leaves the way for the installer. Null means `exit(0)`, and it
  /// is injectable for the same reason: `exit(0)` in a test takes the test
  /// process with it.
  final void Function()? quit;

  const DeveloperModal({
    super.key,
    bool? isVisible,
    bool? isOpen,
    this.onClose,
    this.isForceUpdate = false,
    this.currentVersion = '',
    this.requiredVersion = '',
    this.latestVersion = '',
    this.service,
    this.release,
    this.quit,
  }) : isVisible = isVisible ?? isOpen ?? false;

  @override
  State<DeveloperModal> createState() => _DeveloperModalState();
}

class _DeveloperModalState extends State<DeveloperModal>
    with SingleTickerProviderStateMixin {
  String _appVersion = '';
  late AnimationController _controller;

  /// The updater, which lives here rather than on a second screen: a forced
  /// launch shows this modal alone, and the button turns it into the download
  /// screen in place. See [_startUpdate].
  _UpdateStage _stage = _UpdateStage.ready;
  UpdateRelease? _release;
  String? _error;
  int _received = 0;
  int? _total;

  /// Guards against a second download on the same modal. The button can be
  /// pressed twice before the first one has moved the stage, and a retry after
  /// a failure has to be allowed, so the flag is cleared on failure and not on
  /// success.
  bool _installStarted = false;

  /// True once GitHub has been asked here. Without it a modal built with no
  /// [DeveloperModal.release] would re-ask on every press, and the release API
  /// allows sixty unauthenticated calls an hour.
  bool _releaseAsked = false;

  /// Set on dispose, because the progress callback and the awaited download keep
  /// arriving after the modal is gone.
  bool _cancelled = false;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _blurAnimation;

  @override
  void initState() {
    super.initState();

    // The release the launch check already fetched, taken now rather than asked
    // for later: it is what puts the notes on screen *before* the reader decides,
    // and the release API allows sixty unauthenticated calls an hour.
    _release = widget.release;

    // The version this modal needs in its own words arrives as
    // [DeveloperModal.currentVersion]; this is a second reading for the
    // developer panel below it. So a failure here is not worth crashing a launch
    // over — an unguarded `then` left the rejection unhandled, which is an
    // uncaught async error rather than a shown message. `VersionCheckGate
    // ._getCurrentVersion` wraps the same call for the same reason.
    PackageInfo.fromPlatform()
        .then((info) {
          if (mounted) setState(() => _appVersion = info.version);
        })
        .catchError((_) {
          // No version string; the panel shows nothing rather than guessing.
        });

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.isVisible ? 1.0 : 0.0,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _blurAnimation = Tween<double>(
      begin: 0.0,
      end: 12.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant DeveloperModal oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A newer release arrived while this modal was up. Adopted only before the
    // download starts: once the bytes are moving, the release on record is the
    // one being installed, and swapping it mid-flight would verify a different
    // file than the one it reports.
    if (widget.release != null &&
        widget.release != oldWidget.release &&
        !_installStarted &&
        _stage == _UpdateStage.ready) {
      setState(() => _release = widget.release);
    }

    if (widget.isVisible && !oldWidget.isVisible) {
      _controller.forward();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _controller.dispose();
    super.dispose();
  }

  // Helper to close modal with animation
  void _handleClose() {
    if (widget.isForceUpdate) return;
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onClose?.call();
      }
    });
  }

  /// What «تحديث الآن» does: work out what to install, then install it.
  ///
  /// The only way an update starts in this app. It used to run itself the moment
  /// the forced screen appeared, which meant the reader never chose, and a
  /// launch that lost its network at that moment was left with no button to
  /// press a second time. The stages below are all downstream of this press.
  Future<void> _startUpdate() async {
    final service = widget.service;
    if (service == null || _installStarted) return;

    // The launch check normally hands a release over, so this branch is the
    // offline case: the modal was built from cached preferences with no release,
    // and the reader pressed the button anyway.
    if (_release == null && !_releaseAsked) {
      _releaseAsked = true;
      setState(() => _stage = _UpdateStage.loading);

      final release = await service.latestRelease();
      if (!mounted || _cancelled) return;

      if (release == null) {
        setState(() {
          _stage = _UpdateStage.failed;
          _error = 'لا يوجد تحديث منشور الآن، أو تعذّر الوصول إلى GitHub.';
        });
        return;
      }
      setState(() => _release = release);
    }

    final release = _release;
    if (release == null) return;

    // Waiting for a file that was never attached is worse than saying so: the
    // release page is the only thing that can help.
    if (!release.isDownloadable) {
      setState(() {
        _stage = _UpdateStage.failed;
        _error =
            'هذا الإصدار لم يُرفق به ملف تنصيب، فالتحديث من صفحة الإصدارات.';
      });
      return;
    }

    await _install(release);
  }

  /// Downloads, verifies, then hands over to Setup — in that order, every time.
  ///
  /// Verification sits between the two on purpose. The bytes come off the
  /// network and the file they are written to is then run with the installer's
  /// rights; a digest that is not checked installs whatever arrived. A refusal
  /// here is not a retryable error either: the file was tampered with or
  /// truncated, and trying again does not change that.
  Future<void> _install(UpdateRelease release) async {
    if (_installStarted) return;
    _installStarted = true;

    setState(() {
      _stage = _UpdateStage.downloading;
      _received = 0;
      _total = release.downloadSize;
      _error = null;
    });

    try {
      final file = await widget.service!.downloadInstaller(
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

      if (!await widget.service!.verify(file, release)) {
        if (!mounted) return;
        setState(() {
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
      await widget.service!.runInstaller(file);
      if (!mounted) return;
      (widget.quit ?? _defaultQuit)();
    } on UpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _installStarted = false;
        _stage = _UpdateStage.failed;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installStarted = false;
        _stage = _UpdateStage.failed;
        _error = 'تعذّر إكمال التحديث: $error';
      });
    }
  }

  /// The app has to be gone for Setup to replace its own files.
  static void _defaultQuit() => exit(0);

  /// Always the release page, which exists even when the download does not.
  Future<void> _openReleasePage() async {
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 1. Completely remove from render tree when animation finishes
        if (!widget.isVisible && _controller.isDismissed) {
          return const SizedBox.shrink();
        }

        // 2. Immediately drop all touch events when closing begins
        return IgnorePointer(
          ignoring: !widget.isVisible,
          child: Stack(
            children: [
              // Backdrop with dark blue blur
              GestureDetector(
                onTap: widget.isForceUpdate ? null : _handleClose,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _blurAnimation.value,
                    sigmaY: _blurAnimation.value,
                  ),
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: Container(
                      color: const Color(0xFF0F172A).withOpacity(0.8),
                    ),
                  ),
                ),
              ),

              // Modal Body
              Center(
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: _buildGlassContainer(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlassContainer() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = ResponsiveBreakpoints.dialogWidth(
      screenWidth,
      max: 380,
    );
    final horizontalMargin = screenWidth < 420 ? 16.0 : 24.0;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: dialogWidth),
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.95),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: const Color(0xFF38BDF8).withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withOpacity(0.15),
            blurRadius: 30,
            spreadRadius: -5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // The glass box scrolls instead of overflowing. Three hosts hand it a
      // bounded height — `main.dart`'s `Positioned.fill`, the gate's overlay, and
      // the forced launch — and the forced screen is the one nobody is allowed to
      // leave, so an overflow there shows a blocked reader the middle of an
      // update with neither end of it in reach.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildAestheticHeader(), _buildBody()],
        ),
      ),
    );
  }

  Widget _buildAestheticHeader() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final headerPadding = screenWidth < 420 ? 20.0 : 30.0;

    return Container(
      padding: EdgeInsets.all(headerPadding),
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: Column(
        children: [
          // Profile Picture with glow
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const CircleAvatar(
              radius: 42,
              backgroundColor: Color(0xFF0F172A),
              child: Icon(LucideIcons.user, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Hassan Mazin',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          // "Designed for Al-Bayt" badge - Updated to RTL
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF38BDF8).withOpacity(0.2),
              ),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  // `Flexible`, so the badge's sentence wraps rather than
                  // overflowing the pill. It measured 3px too wide inside the
                  // ~272px the modal leaves at its `dialogWidth` cap.
                  Flexible(
                    child: Text(
                      'تطبيق مصمم خصيصاً للبيت',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE2E8F0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    LucideIcons.heartHandshake,
                    size: 14,
                    color: Color(0xFF38BDF8),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The update section, then what the app is. Renamed when the three contact rows
  /// went: what this built is no longer a social body, and a name that keeps
  /// describing something the file no longer has is how the next reader looks in
  /// the wrong place.
  Widget _buildBody() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 10, 25, 30),
      child: Column(
        children: [
          // The update section — the whole reason a forced launch ever shows
          // this modal. Absent when [DeveloperModal.service] is null, which is
          // `main.dart`'s developer panel: information, and nothing to install.
          if (widget.service != null) ...[
            _buildUpdateBanner(),
            // Only while there is still a decision to make. Once the button has
            // been pressed the reader is past the "what is this" question, and
            // the panel they are watching is the download itself.
            if (_stage == _UpdateStage.ready) ...[
              _buildReleaseDetails(),
              const SizedBox(height: 14),
            ],
            _buildUpdateActions(),
            const SizedBox(height: 20),
          ],
          // App version display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.info,
                  size: 13,
                  color: Colors.white.withOpacity(0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  _appVersion.isEmpty ? 'الإصدار ...' : 'الإصدار $_appVersion',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // `Close` belongs to the developer panel, which is information and
          // nothing else. When this modal is standing in for an update, «تخطّي
          // الآن» above is the way out, and two buttons that both dismiss the
          // same screen is how the reader ends up unsure which one is meant.
          if (!widget.isForceUpdate && widget.service == null)
            _buildActionButtons(),
        ],
      ),
    );
  }

  /// The notice above the button: red when the reader may not use the app,
  /// cyan when the update is only an offer.
  ///
  /// One method for both rather than two banners: they differ in a colour and a
  /// sentence, and a second copy is exactly how one of them drifts out of the
  /// modal's width and starts overflowing on its own.
  Widget _buildUpdateBanner() {
    final accent = widget.isForceUpdate
        ? const Color(0xFFEF4444)
        : const Color(0xFF38BDF8);
    final headline = widget.isForceUpdate
        ? 'يجب تحديث التطبيق للمتابعة'
        : 'يتوفر تحديث جديد';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isForceUpdate
                    ? Icons.warning_rounded
                    : Icons.new_releases_rounded,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              // `Flexible`, so the sentence wraps instead of pushing past the
              // banner. The modal is capped at `dialogWidth` (380) minus the
              // header's own padding, which leaves ~272px — narrower than this
              // line needs, so it overflowed by 93px on the forced-update screen,
              // the one screen nobody is allowed to scroll away from.
              Flexible(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (widget.currentVersion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'إصدارك الحالي: ${widget.currentVersion}',
              style: TextStyle(color: accent.withOpacity(0.7), fontSize: 12),
            ),
          ],
          if (widget.requiredVersion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'الإصدار المطلوب: ${widget.requiredVersion}',
              style: TextStyle(
                color: accent.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (widget.latestVersion.isNotEmpty && !widget.isForceUpdate) ...[
            const SizedBox(height: 4),
            Text(
              'أحدث إصدار: ${widget.latestVersion}',
              style: TextStyle(
                color: accent.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What the new version is, and what changed in it — the question the reader
  /// asked before pressing anything.
  ///
  /// The notes are the release body typed by hand into the GitHub release, and
  /// there is no second copy to fall back on: no release at all means the panel
  /// says nothing rather than inventing a changelog. Height-capped and
  /// scrollable because an unbounded body inside a 380-wide modal is what pushed
  /// this screen past a short window.
  Widget _buildReleaseDetails() {
    final release = _release;
    if (release == null) return const SizedBox.shrink();

    final size = release.downloadSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الإصدار الجديد: ${release.version}',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        if (size != null) ...[
          const SizedBox(height: 4),
          Text(
            'حجم التنزيل: ${_formatBytes(size)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
        if (release.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Scrollbar(
              // Markdown, because the release body is written in it: `##` and
              // `-` are what the publisher typed, and showing them as literal
              // characters is what makes a changelog look like a debug dump.
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: release.notes,
                  selectable: false,
                  styleSheet: MarkdownStyleSheet(
                    // Field by field, not `fromTheme`: that helper asserts on a
                    // theme carrying text styles, and this panel renders above
                    // `MaterialApp` — there is no app theme here to read. The
                    // colours are the panel's own, so the notes match the box
                    // they sit in rather than the app's light/dark setting.
                    p: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                    listBullet: const TextStyle(color: Colors.white70),
                    h1: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    h2: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                    h3: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    // Release notes carry links, and a link the reader cannot
                    // see is one they will not follow.
                    a: const TextStyle(color: Color(0xFF93C5FD)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The button before the press, and the progress panel after it.
  ///
  /// One slot rather than two, and they never appear together: the modal's height
  /// is whatever its column measures, so a progress panel stacked under a
  /// still-visible button is what grew the forced screen past a short window.
  /// The button is gone the moment it is pressed.
  Widget _buildUpdateActions() {
    if (_stage != _UpdateStage.ready) return _buildUpdateProgress();

    final accent = widget.isForceUpdate
        ? const Color(0xFFEF4444)
        : const Color(0xFF38BDF8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _startUpdate,
          icon: const Icon(
            Icons.download_rounded,
            size: 16,
            color: Colors.white,
          ),
          label: const Text(
            'تحديث الآن',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        // The way out of an *optional* update. Present only when there is one to
        // decline — the forced case has no `onClose` at all, which is what stops
        // a reader who cannot use the app from talking their way past it.
        if (!widget.isForceUpdate && widget.onClose != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _handleClose,
            icon: const Icon(
              Icons.schedule_rounded,
              size: 16,
              color: Colors.white70,
            ),
            label: const Text(
              'تخطّي الآن',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
        // Nothing else sits under «تحديث الآن» on the forced screen, and that is
        // the point. It used to carry a «مسح البلوك (للمطورين)» button that wiped
        // the cached block — which unblocked the launch only while the network
        // was down, because the check writes those keys again on the next start,
        // and put a button labelled "for developers" on the one page a shipped
        // reader cannot leave. A blocked reader now has exactly one exit: the
        // new version.
      ],
    );
  }

  /// Where the progress appears, in place of the button it replaced.
  Widget _buildUpdateProgress() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _updateTitle(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          _updateStep(),
          const SizedBox(height: 12),
          _buildFailureActions(),
        ],
      ),
    );
  }

  String _updateTitle() {
    switch (_stage) {
      case _UpdateStage.ready:
        return 'تحديث متاح';
      case _UpdateStage.loading:
        return 'جارٍ التحقق من التحديثات';
      case _UpdateStage.downloading:
        return 'جارٍ تنزيل التحديث';
      case _UpdateStage.verifying:
        return 'جارٍ التحقق من الملف';
      case _UpdateStage.installing:
        return 'جارٍ التثبيت';
      case _UpdateStage.failed:
        return 'تعذّر إكمال التحديث';
    }
  }

  /// The body for the current stage.
  Widget _updateStep() {
    switch (_stage) {
      case _UpdateStage.ready:
      case _UpdateStage.loading:
        return const _Busy(text: 'جارٍ السؤال عن أحدث إصدار…');

      case _UpdateStage.downloading:
        final total = _total;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              // Known total → a real bar; unknown → a moving one. A bar parked
              // at 90% because the server never declared a length is worse than
              // no bar at all.
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

  /// Only a failure offers anything. The release page is always there; «إغلاق»
  /// belongs to the optional update and never to the forced one, because a
  /// blocked launch has nothing to go back to.
  Widget _buildFailureActions() {
    if (_stage != _UpdateStage.failed) return const SizedBox.shrink();

    return Wrap(
      // `Wrap` and not `Row`: three Arabic buttons and a link are wider than the
      // 380 the modal is capped at, and a `Row` pushed the retry off the edge —
      // the one button that matters on a page the reader cannot leave.
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          onPressed: _openReleasePage,
          child: const Text(
            'صفحة الإصدارات',
            style: TextStyle(color: Color(0xFF93C5FD)),
          ),
        ),
        if (_release?.isDownloadable ?? false)
          ElevatedButton(
            onPressed: _startUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'إعادة المحاولة',
              style: TextStyle(color: Colors.white),
            ),
          ),
        if (!widget.isForceUpdate && widget.onClose != null)
          TextButton(
            onPressed: _handleClose,
            child: const Text('إغلاق', style: TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _handleClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A spinner and a sentence, for the stages that are only waiting.
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
        // `Expanded`, so the sentence wraps inside the modal's capped width
        // instead of overflowing it — the stages that use this are the ones where
        // a slow network is the most likely thing to be happening.
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
