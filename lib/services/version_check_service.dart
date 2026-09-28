import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  static Future<VersionCheckResult> check() async {
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
    if (_isLessThan(current, min)) return VersionStatus.forceUpdate;
    if (_isLessThan(current, latest)) return VersionStatus.softUpdate;
    return VersionStatus.upToDate;
  }

  // Returns true if versionA < versionB
  static bool _isLessThan(String versionA, String versionB) {
    final a = versionA.split('.').map(int.parse).toList();
    final b = versionB.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai < bi) return true;
      if (ai > bi) return false;
    }
    return false;
  }
}
