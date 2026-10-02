import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/semver.dart';

enum VersionStatus { upToDate, softUpdate, forceUpdate }

class VersionCheckResult {
  final VersionStatus status;
  final String currentVersion;
  final String latestVersion;
  final String minVersion;

  const VersionCheckResult({
    required this.status,
    required this.currentVersion,
    required this.latestVersion,
    required this.minVersion,
  });
}

class VersionCheckService {
  /// Resolves the launch state from the two places that know something about it.
  ///
  /// The Firestore document `app_config/version` (with Remote Config as its
  /// fallback) owns `min_version` — the policy: which builds are no longer
  /// allowed to run. [latestVersionOverride] is what the release repository says
  /// the newest build is, and it wins when it is higher, because only it knows
  /// whether there is something to download: a `latest_version` typed into a
  /// database offers an update nobody can install.
  ///
  /// The comparison itself is `isVersionLessThan` in `utils/semver.dart` — the
  /// updater asks the same question, and two copies of "which is newer" is how
  /// the two ends up disagreeing.
  static Future<VersionCheckResult> check({
    String? latestVersionOverride,
  }) async {
    String minVersion = '';
    String latestVersion = '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get();

      if (doc.exists && doc.data() != null) {
        minVersion = doc.data()!['min_version'] as String? ?? '';
        latestVersion = doc.data()!['latest_version'] as String? ?? '';
      }
    } catch (_) {}

    if (minVersion.isEmpty || latestVersion.isEmpty) {
      try {
        final remoteConfig = FirebaseRemoteConfig.instance;
        await remoteConfig.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: const Duration(seconds: 10),
            minimumFetchInterval: const Duration(hours: 1),
          ),
        );
        await remoteConfig.fetchAndActivate();
        if (minVersion.isEmpty) {
          minVersion = remoteConfig.getString('min_version');
        }
        if (latestVersion.isEmpty) {
          latestVersion = remoteConfig.getString('latest_version');
        }
      } catch (_) {}
    }

    if (minVersion.isEmpty) minVersion = '0.0.0';
    if (latestVersion.isEmpty) latestVersion = '0.0.0';

    // The release repository outranks the database here, and only here: it is
    // the side that can serve a file.
    if (latestVersionOverride != null &&
        latestVersionOverride.trim().isNotEmpty &&
        isVersionLessThan(latestVersion, latestVersionOverride)) {
      latestVersion = latestVersionOverride.trim();
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final status = _compare(currentVersion, minVersion, latestVersion);

    return VersionCheckResult(
      status: status,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      minVersion: minVersion,
    );
  }

  static VersionStatus _compare(String current, String min, String latest) {
    if (isVersionLessThan(current, min)) return VersionStatus.forceUpdate;
    if (isVersionLessThan(current, latest)) return VersionStatus.softUpdate;
    return VersionStatus.upToDate;
  }
}
