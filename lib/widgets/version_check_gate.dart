import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/update_service.dart';
import '../services/version_check_service.dart';
import 'developer_modal_w.dart';

const String _kForceUpdateKey = 'force_update_active';
const String _kForceUpdateMinVersionKey = 'force_update_min_version';
const String _kForceUpdateLatestVersionKey = 'force_update_latest_version';

class VersionCheckGate extends StatefulWidget {
  final Widget child;

  /// A check result to use instead of asking anything.
  ///
  /// Only a test passes this. The real check reaches Firestore, Remote Config and
  /// `PackageInfo`, none of which exist in a widget test — and the forced path is
  /// the one worth testing, because it is the one that once threw on the launch
  /// frame. A field rather than a mock of three services: the gate's decision is
  /// what is under test, not the fetching.
  final VersionCheckResult? debugResultOverride;

  const VersionCheckGate({
    super.key,
    required this.child,
    this.debugResultOverride,
  });

  @override
  State<VersionCheckGate> createState() => _VersionCheckGateState();
}

class _VersionCheckGateState extends State<VersionCheckGate> {
  late final Future<VersionCheckResult?> _checkFuture;

  /// True once the updater has offered itself on this launch.
  ///
  /// It is what keeps a soft update an *offer*: a reader who closes it has
  /// answered, and the same panel coming back on every rebuild is not an offer,
  /// it is a fight with the window. The forced case does not use it — there is
  /// nothing to offer and nothing to close.
  bool _autoOpened = false;

  /// The release repository is asked alongside the database: the database names
  /// what it wants, and this names what can actually be downloaded.
  final UpdateService _updates = UpdateService();

  /// The release the launch check already fetched, handed to the updater so one
  /// launch does not ask GitHub the same question twice — the unauthenticated API
  /// allows sixty requests an hour per address, and the second answer would be the
  /// first one again.
  UpdateRelease? _release;

  /// The result of this launch's check, once it has arrived.
  ///
  /// A field and not only the `FutureBuilder`'s snapshot, because the optional
  /// update is opened by `_requestUpdater` — which runs after a frame, not during
  /// a build — and the modal it hands the result to is built later than the
  /// snapshot that scheduled it.
  VersionCheckResult? _result;

  /// True while the *optional* update is offered over the app.
  ///
  /// The forced case never sets it: that launch has no app to run behind an
  /// offer, so the blocking screen is the modal itself and there is nothing to
  /// close — the only way out of it is a new version.
  bool _updaterOpen = false;

  @override
  void initState() {
    super.initState();
    _checkFuture = _resolveVersionStatus();
  }

  // Returns null if we should not block and can continue startup.
  Future<VersionCheckResult?> _resolveVersionStatus() async {
    // A test's answer, short-circuiting everything: no `SharedPreferences`, no
    // Firestore, no `PackageInfo`. See [VersionCheckGate.debugResultOverride].
    final injected = widget.debugResultOverride;
    if (injected != null) return injected;

    final prefs = await SharedPreferences.getInstance();
    final wasForceBlocked = prefs.getBool(_kForceUpdateKey) ?? false;

    // Always try a live check first; if backend is fixed, unblock immediately.
    try {
      // The release repository decides *what* is newest, because only it knows
      // whether there is a file to download; the database keeps `min_version`,
      // which is the policy nobody else can express. Both are asked here so the
      // status the app shows and the file the updater fetches agree.
      final release = await _updates.latestRelease();
      // Kept, not only read: the updater is handed this rather than asking again.
      _release = release;
      final result = await VersionCheckService.check(
        latestVersionOverride: release?.version,
      );
      if (result.status == VersionStatus.forceUpdate) {
        await prefs.setBool(_kForceUpdateKey, true);
        await prefs.setString(_kForceUpdateMinVersionKey, result.minVersion);
        await prefs.setString(
          _kForceUpdateLatestVersionKey,
          result.latestVersion,
        );
      } else if (wasForceBlocked) {
        await prefs.remove(_kForceUpdateKey);
        await prefs.remove(_kForceUpdateMinVersionKey);
        await prefs.remove(_kForceUpdateLatestVersionKey);
      }
      return result;
    } catch (_) {
      // Offline: only block if device was force-blocked previously.
      if (wasForceBlocked) {
        return VersionCheckResult(
          status: VersionStatus.forceUpdate,
          currentVersion: await _getCurrentVersion(),
          latestVersion: prefs.getString(_kForceUpdateLatestVersionKey) ?? '',
          minVersion: prefs.getString(_kForceUpdateMinVersionKey) ?? '',
        );
      }
      return null;
    }
  }

  Future<String> _getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '';
    }
  }

  /// Puts [result] away and decides what has to happen with no button pressed.
  ///
  /// Called from the `FutureBuilder`'s builder — during a build — so it may not
  /// put anything on screen. The field assignment is safe; the `setState` is not,
  /// and is why the optional update's opening goes through a post-frame
  /// callback. Writing it here rather than only in that callback keeps the
  /// shipping app idempotent and testable: a test that builds the widget drives
  /// the real path instead of only the path the app itself would have reached.
  void _remember(VersionCheckResult result) {
    final isForced = result.status == VersionStatus.forceUpdate;
    final isSoft = result.status == VersionStatus.softUpdate;
    _result = result;

    // The forced case opens nothing here. `_buildLaunch` returns the blocking
    // screen, and that screen *is* the developer modal with the update in it —
    // laying an updater over it as well is what put two pages in front of a
    // reader who could do nothing about either one, and started the download
    // before they had agreed to anything.
    if (isForced) return;

    // Soft update: the app runs, and the offer is laid over it once per launch.
    // Once, because the reader who closes it has answered — the same offer coming
    // back on every rebuild is not an offer.
    if (isSoft && !_autoOpened) {
      _autoOpened = true;
      _requestUpdater();
    }
  }

  /// The actual open. Safe to call inside a build, because the state change is
  /// deferred to after the frame: `setState` during a build is what threw
  /// `setState() or markNeedsBuild() called during build`.
  void _requestUpdater() {
    if (_updaterOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _updaterOpen) return;
      setState(() => _updaterOpen = true);
    });
  }

  void _closeUpdater() => setState(() => _updaterOpen = false);

  // Force update: show frozen screen with developer modal open
  Widget _buildForceUpdateScreen(VersionCheckResult result) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: const Color(0xFF0F172A),
        child: Center(
          child: SingleChildScrollView(
            child: DeveloperModal(
              isVisible: true,
              isForceUpdate: true,
              currentVersion: result.currentVersion,
              requiredVersion: result.minVersion,
              // The updater travels inside the screen: the button downloads,
              // verifies and installs in place. There is no second page, and
              // nothing starts downloading until the reader presses it.
              service: _updates,
              release: _release,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VersionCheckResult?>(
      future: _checkFuture,
      builder: (context, snapshot) => _withUpdater(_buildLaunch(snapshot)),
    );
  }

  /// What the app is allowed to show, before the updater is laid over it.
  Widget _buildLaunch(AsyncSnapshot<VersionCheckResult?> snapshot) {
    // No internet, or a check that failed → the app runs. An update offer is not
    // worth a blocked reader.
    if (snapshot.hasError) return widget.child;
    if (snapshot.connectionState != ConnectionState.done) return widget.child;

    final result = snapshot.data;
    if (result == null) return widget.child;

    // Puts the result away and arranges the updater; see `_remember` for why the
    // state change itself has to wait for the end of the frame.
    _remember(result);

    if (result.status == VersionStatus.forceUpdate) {
      // The only thing this launch may show. No updater is laid over it
      // and nothing opens behind it: the screen *is* the update, and its button
      // is the only thing that starts one.
      return _buildForceUpdateScreen(result);
    }

    return widget.child;
  }

  /// The *optional* update, laid over whatever the app is showing.
  ///
  /// A `Stack` and not a replacement, because a reader with a PDF open must not
  /// lose it to an update offer. The forced case never reaches here: it has no
  /// app left to keep, and its screen is the modal on its own.
  ///
  /// The same modal the forced launch shows, so this app has one update page and
  /// not two — and it waits for its button just as the forced one does. An offer
  /// that installs itself is not an offer.
  Widget _withUpdater(Widget app) {
    if (!_updaterOpen) return app;

    final result = _result;

    // `Stack` needs a `Directionality` to resolve its own default
    // `AlignmentDirectional.topStart`, and this gate sits above the `MaterialApp`
    // that would otherwise supply one — so without this the soft update threw
    // `No Directionality widget found` on the frame the offer appeared.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        fit: StackFit.expand,
        children: [
          app,
          DeveloperModal(
            isVisible: true,
            currentVersion: result?.currentVersion ?? '',
            latestVersion: result?.latestVersion ?? '',
            service: _updates,
            release: _release,
            onClose: _closeUpdater,
          ),
        ],
      ),
    );
  }
}
