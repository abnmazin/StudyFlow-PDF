import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:studyflow_pdf/services/update_service.dart';
import 'package:studyflow_pdf/services/version_check_service.dart';
import 'package:studyflow_pdf/utils/semver.dart';
import 'package:studyflow_pdf/widgets/developer_modal_w.dart';
import 'package:studyflow_pdf/widgets/version_check_gate.dart';

/// Fixtures, so the tests read as behaviour rather than as data.
Map<String, dynamic> releaseJson({
  String tag = 'v1.2.0',
  String htmlUrl = 'https://example.test/releases/tag/v1.2.0',
  String body = 'إصلاح لوحة الإشعارات',
  String? installerName = 'StudyFlowPDF_Setup_1.2.0.exe',
  int? size = 12,
  String? digest = 'sha256:abc',
  String? extraAsset,
}) {
  return {
    'tag_name': tag,
    'html_url': htmlUrl,
    'body': body,
    'assets': [
      // A release may carry a checksum file or a zip beside the installer, and
      // whichever asset is listed first must not be the one downloaded.
      if (extraAsset != null) {'name': extraAsset, 'size': 4},
      if (installerName != null)
        {
          'name': installerName,
          'size': size,
          'digest': digest,
          'browser_download_url': 'https://example.test/dl/$installerName',
        },
    ],
  };
}

/// A release as GitHub reports it, or null when it could not be read.
UpdateRelease? releaseOf(Map<String, dynamic> json) =>
    UpdateRelease.fromJson(json);

/// Locks the two decisions this updater makes that no one can check by eye:
/// which build is newer, and whether the bytes that came down are the ones that
/// were published.
///
/// Both fail silently. A comparison written by eye says `1.9.0` is newer than
/// `1.10.0` and the release is never offered; a verification skipped, or run
/// against the wrong side, installs whatever the network delivered — with the
/// installer's rights. Neither shows a symptom until it shows a support request.
///
/// The release JSON is a fixture rather than a live call because the shape is
/// what these tests are about, and a test that needs github.com reports the state
/// of the network instead of the state of the code.
void main() {
  group('which build is newer', () {
    test('1.10.0 is newer than 1.9.0', () {
      // The pair a comparison done by eye gets wrong, and the pair that decides
      // whether a whole release is ever offered.
      expect(isVersionLessThan('1.9.0', '1.10.0'), isTrue);
      expect(isVersionLessThan('1.10.0', '1.9.0'), isFalse);
    });

    test('a git tag is compared, not its shape', () {
      // The tag carries the `v`; the version the app holds does not.
      expect(isVersionLessThan('v1.1.0', '1.2.0'), isTrue);
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      // A build number is not part of what a reader is offered.
      expect(compareVersions('1.2.0+3', '1.2.0'), 0);
    });

    test('a typo in a tag does not end the launch', () {
      // The tag is typed by hand into a release, so it is the side that can be
      // wrong; reading it as zero makes a bad tag harmless instead of fatal.
      expect(compareVersions('banana', '0.0.0'), 0);
      expect(compareVersions('1.x.0', '1.0.0'), 0);
    });
  });

  group('what a release offers', () {
    test('the version comes from the tag, and the page link stays', () {
      final release = releaseOf(releaseJson())!;
      expect(release.version, '1.2.0');
      // The tag is kept, because the link has to match it exactly.
      expect(release.tagName, 'v1.2.0');
      expect(release.pageUrl, 'https://example.test/releases/tag/v1.2.0');
      expect(release.notes, 'إصلاح لوحة الإشعارات');
    });

    test('the installer is the .exe, not whichever asset came first', () {
      final release = releaseOf(releaseJson(extraAsset: 'SHA256SUMS.txt'))!;
      expect(release.downloadUrl, endsWith('StudyFlowPDF_Setup_1.2.0.exe'));
      expect(release.downloadSize, 12);
      // GitHub reports `sha256:<hex>`; what is compared is the hex alone.
      expect(release.sha256, 'abc');
    });

    test('a release with nothing attached is a state, not an error', () {
      final release = releaseOf(releaseJson(installerName: null))!;
      expect(release.isDownloadable, isFalse);
      // The reader still gets a version and a page to open, so "no installer
      // published yet" reads as that rather than as a failed update.
      expect(release.version, '1.2.0');
      expect(release.pageUrl, isNotEmpty);
    });

    test('an empty page link falls back to the releases page', () {
      final release = releaseOf(releaseJson(htmlUrl: '   '))!;
      expect(release.pageUrl, kUpdateReleasesPage);
    });

    test('no tag at all means there is no version to offer', () {
      expect(releaseOf(releaseJson(tag: '')), isNull);
    });
  });

  group('the bytes that arrive', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('sfp_update_test');
    });

    tearDown(() => temp.delete(recursive: true));

    /// A service whose only network is one canned answer.
    UpdateService answeringWith(List<int> bytes, {int status = 200}) {
      return UpdateService(
        client: MockClient((_) async => http.Response.bytes(bytes, status)),
      );
    }

    Future<File> exeFile(List<int> bytes) async {
      final file = File(p.join(temp.path, 'downloaded.exe'));
      await file.writeAsBytes(bytes);
      return file;
    }

    test('the installer lands under its version, with progress', () async {
      final bytes = List<int>.generate(64, (i) => i);
      final release = releaseOf(releaseJson(size: bytes.length, digest: null))!;
      final progress = <int>[];

      final file = await answeringWith(bytes).downloadInstaller(
        release,
        directory: temp,
        onProgress: (received, total) => progress.add(received),
      );

      // Versioned so two downloads never mix, and so a file half-written by an
      // earlier attempt cannot be picked up and run by a later one.
      expect(file.path, endsWith(UpdateService.installerFileName('1.2.0')));
      expect(await file.readAsBytes(), bytes);
      // The bar is drawn from this, so the last value has to reach the total.
      expect(progress, isNotEmpty);
      expect(progress.last, bytes.length);
    });

    test('a failed download is an error, not a file', () async {
      final release = releaseOf(releaseJson(size: 12))!;

      await expectLater(
        answeringWith(
          const [],
          status: 404,
        ).downloadInstaller(release, directory: temp),
        throwsA(isA<UpdateException>()),
      );

      // A bad URL is answered with an HTML page and a non-200 status; nothing
      // may be left on disk for a later attempt to hand to Setup.
      expect(temp.listSync(), isEmpty);
    });

    test('a release with no installer cannot be downloaded', () async {
      final release = releaseOf(releaseJson(installerName: null))!;

      await expectLater(
        answeringWith(const []).downloadInstaller(release, directory: temp),
        throwsA(isA<UpdateException>()),
      );
    });

    test('a file matching the published digest is accepted', () async {
      final bytes = <int>[1, 2, 3, 4];
      final digest = sha256.convert(bytes).toString();
      final release = releaseOf(
        releaseJson(size: bytes.length, digest: 'sha256:$digest'),
      )!;

      expect(
        await UpdateService().verify(await exeFile(bytes), release),
        isTrue,
      );
    });

    test('a file that is not what was published is refused', () async {
      final release = releaseOf(
        releaseJson(size: 4, digest: 'sha256:${List.filled(64, '0').join()}'),
      )!;

      expect(
        await UpdateService().verify(
          await exeFile(const [1, 2, 3, 4]),
          release,
        ),
        isFalse,
      );
    });

    test('a truncated file is refused on its length alone', () async {
      // A release published before GitHub reported digests has only its size to
      // go on, and a truncated installer fails midway with no way for the reader
      // to know why.
      final short = releaseOf(releaseJson(size: 999, digest: null))!;
      expect(
        await UpdateService().verify(await exeFile(const [1, 2, 3]), short),
        isFalse,
      );

      // And the same check must not reject a file that does match.
      final exact = releaseOf(releaseJson(size: 3, digest: null))!;
      expect(
        await UpdateService().verify(await exeFile(const [1, 2, 3]), exact),
        isTrue,
      );
    });
  });

  group('the forced screen is the only page', () {
    // The failure this group exists to prevent: a forced launch put two pages in
    // front of the reader — the developer modal, and an update panel laid over
    // it — and the panel started downloading on its own. The screen must now be
    // one page, idle until it is pressed, and it must still reach Setup and end
    // the app so Setup can replace it.
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('sfp_forced_update_test');
    });

    tearDown(() async {
      // The screen is disposed explicitly by the test that installs, which
      // closes the file handle it held there. This teardown still has to
      // tolerate a handle the OS has not released yet: a sharing violation must
      // not be reported as a failure of an unrelated assertion.
      try {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows keeps the installer locked for a moment after the writer
        // closes; the temp directory is the OS's to sweep.
      }
    });

    /// The blocking launch screen, exactly as `VersionCheckGate` builds it.
    ///
    /// No `onClose`: a forced screen has no way out, which is what makes this
    /// test read the launch path rather than a dialog.
    Future<void> pumpScreen(
      WidgetTester tester,
      UpdateRelease? release, {
      UpdateService? service,
      required void Function() onQuit,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DeveloperModal(
            isVisible: true,
            isForceUpdate: true,
            currentVersion: '1.1.0',
            requiredVersion: '1.2.0',
            service: service ?? UpdateService(),
            release: release,
            quit: onQuit,
          ),
        ),
      );
    }

    /// Runs [body] with real callbacks, then rebuilds.
    ///
    /// The screen's own path touches the filesystem — it writes the installer,
    /// reads it back to hash it, and it is those FS-backed futures that `pump`
    /// alone never completes, because `pump` advances fake time while the file
    /// I/O completes on the real event loop. `runAsync` is the only way in.
    ///
    /// `pump` always runs after [body], and the caller checks its condition
    /// *after* the call: a task entered by a post-frame callback is not running
    /// yet when a pump-until helper first looks at it, so a helper that checks
    /// first would step over it and hang.
    Future<void> drain(
      WidgetTester tester,
      Future<void> Function() body,
    ) async {
      await tester.runAsync(body);
      await tester.pump();
    }

    testWidgets('it waits on the button, and carries no contact details', (
      tester,
    ) async {
      // The rule, stated as a pause: a launch that cannot use the app must still
      // not install anything behind the reader's back, and the page they are
      // stuck on must be the only one there is.
      final release = releaseOf(releaseJson())!;
      final service = _RecordingService(
        release: release,
        bytes: const [1, 2, 3],
        directory: temp,
        onStart: (_) {},
      );

      await pumpScreen(tester, release, service: service, onQuit: () {});
      // Long enough for anything automatic to have happened several times over.
      await tester.pump(const Duration(seconds: 1));

      expect(service.downloads, 0, reason: 'only the button starts an update');
      expect(find.text('تحديث الآن'), findsOneWidget);
      expect(find.text('جارٍ تنزيل التحديث'), findsNothing);

      // The contact rows are gone from this page, not merely below the fold.
      expect(find.textContaining('@FFFF_6'), findsNothing);
      expect(find.textContaining('07710529693'), findsNothing);
      // And so is every way out: the point of a forced update is that pressing
      // nothing leaves the reader here, with a new version as the only exit.
      expect(find.text('تخطّي الآن'), findsNothing);
      expect(find.text('Close'), findsNothing);
      expect(find.text('إغلاق'), findsNothing);
      // The «مسح البلوك (للمطورين)» button used to sit here. It cleared the
      // cached block, which unblocked the launch only while the network was
      // down, and it shipped to every reader a button labelled "for developers"
      // on the one screen they cannot leave. Removed on 2026-10-02.
      expect(find.text('مسح البلوك (للمطورين)'), findsNothing);
    });

    testWidgets('one press downloads, verifies, and hands over to Setup', (
      tester,
    ) async {
      // The bytes and the file they are checked against, so verification passes
      // for the real reason instead of being stubbed out.
      final bytes = List<int>.generate(32, (i) => i * 3);
      final digest = sha256.convert(bytes).toString();
      final release = releaseOf(
        releaseJson(size: bytes.length, digest: 'sha256:$digest', body: ''),
      )!;

      var quitCalled = false;
      final started = <String>[];
      final service = _RecordingService(
        release: release,
        bytes: bytes,
        directory: temp,
        onStart: started.add,
      );

      await pumpScreen(
        tester,
        release,
        service: service,
        onQuit: () => quitCalled = true,
      );
      await tester.pump();

      // The one deliberate press. Everything below happens because of it, and
      // the press count is the whole point: an update the reader never agreed to
      // is the defect this file was rewritten for.
      await tester.tap(find.text('تحديث الآن'));
      await tester.pump();
      for (var i = 0; i < 20 && !quitCalled; i++) {
        await drain(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }

      expect(quitCalled, isTrue, reason: 'the app must leave for Setup');
      expect(service.downloads, 1, reason: 'one download, not one per frame');
      expect(started, isNotEmpty, reason: 'Setup must be started');
      // The silent switches are what make the install invisible; a missing
      // /CLOSEAPPLICATIONS leaves the running exe locked and Setup waiting.
      expect(started.single, contains('/VERYSILENT'));
      expect(started.single, contains('/CLOSEAPPLICATIONS'));
      // `quit` asks the screen to go, it does not take it away itself, so the
      // widget is disposed here to close the temp file it wrote — the same thing
      // the real `exit(0)` does for the process.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed press says so, and offers the page instead of a way out', (
      tester,
    ) async {
      // A network that is down is not fixed by trying again, and the reader has
      // to be able to read what went wrong — while still being unable to leave a
      // screen they were never allowed to leave in the first place.
      final release = releaseOf(releaseJson(size: 9, digest: null))!;
      var quitCalled = false;
      final service = _RecordingService(
        release: release,
        bytes: const [],
        directory: temp,
        onStart: (_) {},
        downloadStatus: 500,
      );

      await pumpScreen(
        tester,
        release,
        service: service,
        onQuit: () => quitCalled = true,
      );
      await tester.pump();
      await tester.tap(find.text('تحديث الآن'));
      await tester.pump();
      for (var i = 0; i < 20 && service.downloads == 0; i++) {
        await drain(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      // A few more rounds, so a retry loop — the thing this test is about — has
      // every chance to show itself.
      for (var i = 0; i < 4; i++) {
        await drain(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }

      expect(quitCalled, isFalse, reason: 'nothing was installed');
      expect(service.downloads, 1, reason: 'one press, one attempt');
      expect(find.textContaining('تعذّر'), findsWidgets);
      // The way out for a reader who cannot use the app is the release page, not
      // a button that drops them back into the build they just failed to update.
      expect(find.text('صفحة الإصدارات'), findsOneWidget);
      expect(find.text('إغلاق'), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the failure has to fit the screen it is reported on',
      );
    });

    testWidgets('the optional offer is dismissible and installs nothing by itself', (
      tester,
    ) async {
      // The same page, but the case where the reader may walk away from it — and
      // where an update that began on its own would be an install nobody agreed
      // to. It also has to read as an offer, not as a block.
      final release = releaseOf(releaseJson())!;
      var closed = false;
      var quitCalled = false;
      final service = _RecordingService(
        release: release,
        bytes: const [1, 2, 3],
        directory: temp,
        onStart: (_) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DeveloperModal(
            isVisible: true,
            currentVersion: '1.1.0',
            latestVersion: '1.2.0',
            service: service,
            release: release,
            quit: () => quitCalled = true,
            onClose: () => closed = true,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(service.downloads, 0, reason: 'nothing starts without a button');
      expect(quitCalled, isFalse);
      expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
      expect(find.text('يجب تحديث التطبيق للمتابعة'), findsNothing);

      // The notes are on screen *before* anything is pressed — otherwise the
      // reader is asked to install a version whose changes they were never shown.
      expect(find.text('الإصدار الجديد: 1.2.0'), findsOneWidget);
      expect(find.textContaining('إصلاح لوحة الإشعارات'), findsWidgets);

      // One way out, and it is the skip — not a second `Close` beside it.
      expect(find.text('تخطّي الآن'), findsOneWidget);
      expect(find.text('Close'), findsNothing);

      await tester.tap(find.text('تخطّي الآن'));
      // The close is animated, so the callback lands after the reverse finishes.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(closed, isTrue, reason: 'an offer the reader may decline');
    });
  });

  group('the gate that blocks a launch', () {
    // The failure this group exists to prevent: the forced path called `setState`
    // from inside `build`, and the framework threw
    // `setState() or markNeedsBuild() called during build` on the launch frame —
    // every reader whose version was below the minimum saw a broken launch.
    //
    // These build the real `VersionCheckGate`, not the screen on its own,
    // because the defect lived in the gate's own build phase: the screen's tests
    // above passed while this was broken.
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('sfp_gate_test');
    });

    tearDown(() {
      try {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Same Windows sharing delay the other group documents; see there.
      }
    });

    /// The app as `main.dart` assembles it: a `MaterialApp` handed to the gate.
    ///
    /// The gate sits *above* it, which is why the child has to bring its own
    /// `Directionality` — and exactly why the forced screen and the updater wrap
    /// themselves in one by hand. A bare `Text` here fails with
    /// `No Directionality widget found`, which is a defect in the fixture, not in
    /// the gate.
    Widget app() => const MaterialApp(home: Scaffold(body: Text('التطبيق')));

    Widget gate({VersionCheckResult? result}) =>
        VersionCheckGate(debugResultOverride: result, child: app());

    testWidgets('a soft result offers the update without being asked', (
      tester,
    ) async {
      // The check reaches Firebase, so this asserts the part that does not
      // depend on the network: the gate builds to the app, not to the blocking
      // screen, and puts nothing in the reader's way while it waits.
      await tester.pumpWidget(gate());
      expect(find.text('التطبيق'), findsOneWidget);
    });

    testWidgets('the gate never mutates state while building', (tester) async {
      // The guard for the whole class of defect above: any `setState` reached
      // from this widget's build phase is reported by the framework as a test
      // failure, so simply building the gate and letting a frame pass proves the
      // launch path cannot throw that assertion.
      await tester.pumpWidget(gate());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a forced result blocks the app with no way out', (
      tester,
    ) async {
      await tester.pumpWidget(
        gate(
          // A forced result injected, so the framework's assertion is exercised
          // without a Firestore that cannot exist here.
          result: const VersionCheckResult(
            status: VersionStatus.forceUpdate,
            currentVersion: '1.0.0',
            latestVersion: '2.0.0',
            minVersion: '2.0.0',
          ),
        ),
      );
      // The first frame runs the app: the check is a future, so one frame of the
      // app is what every launch has before the answer arrives. Not what this
      // test is about.
      expect(find.text('التطبيق'), findsOneWidget);

      // The frame in which the forced result is built — exactly the build that
      // used to throw `setState() or markNeedsBuild() called during build`.
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The app is replaced, and the blocking screen names what is missing.
      expect(find.text('التطبيق'), findsNothing);
      expect(find.text('يجب تحديث التطبيق للمتابعة'), findsOneWidget);
      expect(find.text('الإصدار المطلوب: 2.0.0'), findsOneWidget);
    });

    testWidgets('a forced launch shows that screen and opens nothing over it', (
      tester,
    ) async {
      await tester.pumpWidget(
        gate(
          result: const VersionCheckResult(
            status: VersionStatus.forceUpdate,
            currentVersion: '1.0.0',
            latestVersion: '2.0.0',
            minVersion: '2.0.0',
          ),
        ),
      );
      // Two frames and then a long one: the first is the app, the second is the
      // frame the answer lands on, and the long pump covers the moment the gate
      // used to open an updater of its own accord.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);

      // `flutter_test` answers every HTTP request with 400, so a screen that had
      // gone looking for a release would be sitting on its failure by now. It has
      // not gone looking: the button is there and nothing has started — which is
      // the whole change, since this launch used to reach that failure without
      // anyone pressing anything.
      expect(find.text('تعذّر إكمال التحديث'), findsNothing);
      expect(find.text('تحديث الآن'), findsOneWidget);
      // Still no way back into the app.
      expect(find.text('التطبيق'), findsNothing);
    });
  });
}

/// A service that downloads from a canned answer, records how many times it was
/// asked, and never runs the real Setup.
///
/// [runInstaller] is the one call that must not reach the world: it would launch
/// an executable on the machine running the tests. What is worth holding in place
/// is that it *is* reached, with the switches that make the install silent.
class _RecordingService extends UpdateService {
  _RecordingService({
    required this.release,
    required this.bytes,
    required this.directory,
    required this.onStart,
    this.downloadStatus = 200,
  }) : super(
         client: MockClient(
           (_) async => http.Response.bytes(bytes, downloadStatus),
         ),
       );

  final UpdateRelease? release;
  final List<int> bytes;
  final Directory directory;
  final void Function(String args) onStart;
  final int downloadStatus;

  int downloads = 0;

  @override
  Future<UpdateRelease?> latestRelease() async => release;

  @override
  Future<File> downloadInstaller(
    UpdateRelease release, {
    void Function(int received, int? total)? onProgress,
    Directory? directory,
  }) {
    downloads++;
    return super.downloadInstaller(
      release,
      onProgress: onProgress,
      directory: this.directory,
    );
  }

  @override
  Future<void> runInstaller(File setup) async {
    onStart(UpdateService.silentInstallArgs.join(' '));
  }
}
