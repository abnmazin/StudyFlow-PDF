import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where releases are published.
///
/// The source repository itself, which is public — so `releases/latest` answers a
/// client that carries no token, and a token shipped inside a client is a token
/// given away. Verified against the GitHub API on 2026-10-02: `private: false`.
/// The cost of putting an installer where the source already lives is that the
/// release page shows the repository's own history beside it.
const String kUpdateRepoOwner = 'abnmazin';
const String kUpdateRepoName = 'StudyFlow-PDF';

/// Where a reader is sent when the download cannot happen here: no release
/// published yet, no installer attached to it, or no internet.
const String kUpdateReleasesPage =
    'https://github.com/$kUpdateRepoOwner/$kUpdateRepoName/releases';

/// One published release, as much of it as this app uses.
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.tagName,
    required this.pageUrl,
    this.notes = '',
    this.downloadUrl,
    this.downloadSize,
    this.sha256,
  });

  /// The tag without its `v`: what gets compared, printed and put in a file
  /// name. The tag itself is kept for the link, where it must match exactly.
  final String version;
  final String tagName;

  /// The release's own page, for the reader who would rather see it.
  final String pageUrl;

  /// The release body, shown as "what is new". Empty on a release written
  /// without notes.
  final String notes;

  /// Null when the release carries no `.exe` — a draft, or one published before
  /// the installer was attached.
  final String? downloadUrl;
  final int? downloadSize;

  /// The `sha256:…` GitHub reports for the asset, lowercased, or null when the
  /// publisher attached a file before GitHub started reporting digests.
  final String? sha256;

  bool get isDownloadable => downloadUrl != null;

  /// Reads the release from what `GET /releases/latest` returns.
  ///
  /// A release with no tag, or with nothing to download, is not an error: it is
  /// a state this app has to survive, and the page link is what it falls back
  /// to. Null only when there is no version to speak of at all.
  static UpdateRelease? fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) return null;

    var installer = <String, dynamic>{};
    for (final asset in (json['assets'] as List?) ?? const []) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (!name.endsWith('.exe')) continue;
      installer = Map<String, dynamic>.from(asset);
      break;
    }

    final digest = (installer['digest'] as String? ?? '').toLowerCase();
    final version = tag.startsWith('v') || tag.startsWith('V')
        ? tag.substring(1)
        : tag;

    return UpdateRelease(
      version: version,
      tagName: tag,
      pageUrl: (json['html_url'] as String?)?.trim().isNotEmpty == true
          ? (json['html_url'] as String).trim()
          : kUpdateReleasesPage,
      notes: (json['body'] as String? ?? '').trim(),
      downloadUrl: (installer['browser_download_url'] as String?)?.trim(),
      // The API reports it as an int; a JSON number read as `num` keeps this
      // from throwing on a release big enough to be written as a double.
      downloadSize: (installer['size'] as num?)?.toInt(),
      sha256: digest.startsWith('sha256:')
          ? digest.substring('sha256:'.length)
          : null,
    );
  }
}

/// A failure worth telling the reader about, already in their words.
///
/// It exists so the updater does not have to read a message off a `StateError`
/// and strip the framework's `Bad state: ` prefix — the same trap
/// `AnnouncementComposer._messageOf` documents at the other end of the app.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Finds the newest published release, downloads its installer, checks it and
/// starts it.
///
/// The client is injectable for the same reason `AnnouncementComposer.pickImage`
/// is: the real one talks to github.com, and a widget test can reach nothing.
/// What is worth holding in place is what this does with an answer — which asset
/// it picks, what it does when the digest does not match, and what it does when
/// there is nothing to install.
class UpdateService {
  UpdateService({
    http.Client? client,
    this.owner = kUpdateRepoOwner,
    this.repo = kUpdateRepoName,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String owner;
  final String repo;

  /// The installer's name in the release, and the name it is given on disk.
  ///
  /// Versioned so the temp directory never mixes two downloads, and so a
  /// half-finished file from an earlier attempt cannot be run by mistake.
  static String installerFileName(String version) =>
      'StudyFlowPDF_Setup_$version.exe';

  /// The switches Setup is started with; [runInstaller] explains each one.
  static const List<String> silentInstallArgs = [
    '/VERYSILENT',
    '/CLOSEAPPLICATIONS',
    '/NORESTART',
    '/SUPPRESSMSGBOXES',
    '/LOG',
  ];

  /// The newest published release, or null when there is none or it cannot be
  /// reached.
  ///
  /// Null is the normal answer on a machine with no internet and on a repository
  /// that has published nothing yet — `abnmazin/StudyFlow-PDF` held no release and
  /// no tag at all on 2026-10-02 — so the caller must have something to do with
  /// it. It is deliberately not
  /// an exception: "nothing to offer" and "the download broke" are told to the
  /// reader differently.
  Future<UpdateRelease?> latestRelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );
    try {
      // Bounded, because this runs on the launch path: on a network that
      // black-holes the connection, `package:http` waits forever, and a reader
      // whose launch screen never finishes is a worse outcome than not being told
      // about an update. Ten seconds is longer than GitHub takes from anywhere and
      // shorter than anyone's patience; the timeout lands in the `catch` below,
      // which is the same answer as "no internet".
      final response = await _client
          .get(uri, headers: _apiHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return UpdateRelease.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Downloads the installer to the temp directory and returns the file.
  ///
  /// [onProgress] receives the bytes so far and the total when the server
  /// declares one; a percentage needs that total, so the dialog prints megabytes
  /// when it is missing instead of pretending to know.
  Future<File> downloadInstaller(
    UpdateRelease release, {
    void Function(int received, int? total)? onProgress,
    Directory? directory,
  }) async {
    final url = release.downloadUrl;
    if (url == null) {
      throw const UpdateException('هذا الإصدار لا يحتوي على ملف تنصيب');
    }

    final dir = directory ?? await getTemporaryDirectory();
    final file = File(p.join(dir.path, installerFileName(release.version)));

    try {
      final response = await _client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw UpdateException(
          'تعذّر تنزيل التحديث (رمز ${response.statusCode})',
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      return file;
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException('تعذّر تنزيل التحديث: $error');
    }
  }

  /// Whether [file] is the file the release published.
  ///
  /// These bytes came from a URL that a tag chose, and they are about to be run
  /// with the installer's rights: without this, the only thing between a
  /// truncated download and a silent install is trust in the network.
  ///
  /// A release published without a digest or a size is accepted — GitHub only
  /// started reporting asset digests recently, and refusing such a release would
  /// lock out exactly the readers who most need the update. Attaching both is the
  /// publisher's job, and `tools/publish_release.ps1` does it.
  Future<bool> verify(File file, UpdateRelease release) async {
    final expectedSize = release.downloadSize;
    if (expectedSize != null && await file.length() != expectedSize) {
      return false;
    }

    final expectedHash = release.sha256?.trim().toLowerCase();
    if (expectedHash == null || expectedHash.isEmpty) return true;

    // Streamed rather than `readAsBytes`: an installer is tens of megabytes, and
    // this is the last step before the bytes are handed to Setup, so the whole
    // file does not need to exist in memory at once.
    final actual = await sha256.bind(file.openRead()).first;
    return actual.toString() == expectedHash;
  }

  /// Starts the downloaded installer with no wizard.
  ///
  /// Each switch is load-bearing:
  /// `/VERYSILENT` because this app has already shown the progress and asked;
  /// `/CLOSEAPPLICATIONS` because the install directory holds the running exe,
  /// and Windows will not replace a file that is in use;
  /// `/NORESTART` so a reboot prompt never appears without the reader's consent;
  /// `/SUPPRESSMSGBOXES` so a silent run stays silent;
  /// `/LOG` so a failed silent install leaves a file to read instead of a
  /// mystery.
  ///
  /// Detached on purpose: Setup outlives this process, because the app has to
  /// exit for its own files to be replaceable. Setup starts the new version when
  /// it is finished — the `[Run]` entry in `installer.iss`, which silent mode
  /// still honours.
  ///
  /// An installer built for all users carries a manifest that asks for
  /// administrator rights, and `Process.start` cannot grant them: Windows answers
  /// `ERROR_ELEVATION_REQUIRED`. That is not a dead end — it is the one case
  /// where the shell is asked to start the file instead, which raises the single
  /// UAC question the reader clears with one click.
  Future<void> runInstaller(File setup) async {
    try {
      await Process.start(
        setup.path,
        silentInstallArgs,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      if (error.errorCode != 740) rethrow;
      await _runElevated(setup);
    }
  }

  Future<void> _runElevated(File setup) async {
    // Quoted for PowerShell, not for `cmd`: an apostrophe inside a single-quoted
    // string is doubled, so a folder whose name has one still works.
    final path = "'${setup.path.replaceAll("'", "''")}'";
    final args = silentInstallArgs.map((a) => "'$a'").join(',');
    await Process.start('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Start-Process -FilePath $path -ArgumentList $args -Verb RunAs',
    ], mode: ProcessStartMode.detached);
  }

  static const Map<String, String> _apiHeaders = {
    // GitHub answers 403 to a request with no user agent, and a name for this
    // app is also the honest thing to appear in their logs.
    'User-Agent': 'StudyFlow-PDF-Reader',
    'Accept': 'application/vnd.github+json',
  };
}
