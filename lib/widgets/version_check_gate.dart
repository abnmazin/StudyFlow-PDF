import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/version_check_service.dart';
import 'developer_modal_w.dart';

const String _kUpdateUrl = ''; // TODO: Replace with your actual Windows installer download URL
const String _kForceUpdateKey = 'force_update_active';
const String _kForceUpdateMinVersionKey = 'force_update_min_version';
const String _kForceUpdateLatestVersionKey = 'force_update_latest_version';

class VersionCheckGate extends StatefulWidget {
  final Widget child;

  const VersionCheckGate({super.key, required this.child});

  @override
  State<VersionCheckGate> createState() => _VersionCheckGateState();
}

class _VersionCheckGateState extends State<VersionCheckGate> {
  late final Future<VersionCheckResult?> _checkFuture;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _checkFuture = _resolveVersionStatus();
  }

  // Returns null if we should not block and can continue startup.
  Future<VersionCheckResult?> _resolveVersionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final wasForceBlocked = prefs.getBool(_kForceUpdateKey) ?? false;

    // Always try a live check first; if backend is fixed, unblock immediately.
    try {
      final result = await VersionCheckService.check();
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

  Future<void> _openUpdateUrl() async {
    if (_kUpdateUrl.isEmpty) return;
    final uri = Uri.parse(_kUpdateUrl);
    await launchUrl(uri);
  }

  Future<void> _showSoftUpdateDialog(VersionCheckResult result) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('تحديث متاح'),
          content: Text(
            'الإصدار ${result.latestVersion} متوفر. إصدارك الحالي ${result.currentVersion}.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('لاحقاً'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _openUpdateUrl();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('تحديث الآن'),
            ),
          ],
        );
      },
    );
  }

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
      builder: (context, snapshot) {
        // If no internet or check failed → don't block, show app normally
        if (snapshot.hasError) return widget.child;

        if (snapshot.connectionState == ConnectionState.done) {
          final result = snapshot.data;
          if (result == null) return widget.child;

          // Force update: completely replace the app UI
          if (result.status == VersionStatus.forceUpdate) {
            return _buildForceUpdateScreen(result);
          }

          // Soft update: show app normally, trigger dialog once
          if (result.status == VersionStatus.softUpdate && !_dialogShown) {
            _dialogShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Guard: only show the dialog if MaterialLocalizations is in the tree.
              // VersionCheckGate sits above MaterialApp, so we need to wait one
              // additional frame for the MaterialApp subtree to be fully mounted.
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;
                // Verify that MaterialLocalizations are accessible via the
                // context before calling showDialog (avoids the crash when this
                // widget lives above MaterialApp in the widget tree).
                final hasLocalization =
                    Localizations.of<MaterialLocalizations>(
                          context,
                          MaterialLocalizations,
                        ) !=
                        null;
                if (!hasLocalization) return;
                await _showSoftUpdateDialog(result);
              });
            });
          }

          return widget.child;
        }

        // Still loading → show app normally, don't block
        return widget.child;
      },
    );
  }
}
