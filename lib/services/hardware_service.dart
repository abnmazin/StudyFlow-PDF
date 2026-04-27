import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class HardwareService {
  static const String _installIdKey = 'studyflow_device_installation_id_v1';

  /// Generates a strong, multi-layer device fingerprint.
  /// Combines: device name, OS type, OS version, and machine UUID.
  Future<String> getDeviceFingerprint() async {
    try {
      final deviceName = _safeHostName();
      final osType = Platform.operatingSystem;
      final osVersion = Platform.operatingSystemVersion;
      final machineUuid = await getDeviceUUID();

      final rawIdentity = "$deviceName|$osType|$osVersion|$machineUuid";
      final normalized = rawIdentity.toLowerCase().trim();
      
      final bytes = utf8.encode(normalized);
      final digest = sha256.convert(bytes);
      final fingerprint = digest.toString();

      debugPrint('🛡️ [Security] Device Fingerprint Generated Successfully');
      // debugPrint('DEBUG: raw=$normalized');
      // debugPrint('DEBUG: fingerprint=$fingerprint');

      return fingerprint;
    } catch (e) {
      debugPrint('❌ [Security] Failed to generate device fingerprint: $e');
      // Fallback to a less secure but stable ID if possible, 
      // but the strict policy requires this to succeed.
      rethrow;
    }
  }

  Future<String> getDeviceUUID() async {
    if (!Platform.isWindows) {
      return _fromInstallationId();
    }

    final fromWmic = await _fromWmic();
    if (fromWmic != null) return fromWmic;

    final fromCim = await _fromPowerShellCim();
    if (fromCim != null) return fromCim;

    final fromRegistry = await _fromRegistryMachineGuid();
    if (fromRegistry != null) return fromRegistry;

    return _fromInstallationId();
  }

  Future<String> _fromInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final generated = const Uuid().v4();
    await prefs.setString(_installIdKey, generated);
    return generated;
  }

  String _safeHostName() {
    try {
      final hostname = Platform.localHostname.trim();
      if (hostname.isNotEmpty) return hostname;
    } catch (_) {}
    return 'unknown-host';
  }

  Future<String?> _fromWmic() async {
    try {
      final result = await Process.run('wmic', ['csproduct', 'get', 'uuid']);
      if (result.exitCode != 0) return null;

      final output = (result.stdout ?? '').toString();
      final lines = output
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;

      final raw = lines.firstWhere(
        (line) => line.toLowerCase() != 'uuid',
        orElse: () => '',
      );
      return _normalizeId(raw);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fromPowerShellCim() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_ComputerSystemProduct | Select-Object -ExpandProperty UUID',
      ]);
      if (result.exitCode != 0) return null;
      final raw = (result.stdout ?? '').toString().trim();
      return _normalizeId(raw);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fromRegistryMachineGuid() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      if (result.exitCode != 0) return null;

      final output = (result.stdout ?? '').toString();
      final lines = output
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      final line = lines.firstWhere(
        (l) => l.toLowerCase().contains('machineguid'),
        orElse: () => '',
      );
      if (line.isEmpty) return null;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.isEmpty) return null;
      final raw = parts.last;
      return _normalizeId(raw);
    } catch (_) {
      return null;
    }
  }

  String? _normalizeId(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
    if (cleaned.isEmpty) return null;
    final lower = cleaned.toLowerCase();
    if (lower == 'uuid' || lower == 'ffffffff-ffff-ffff-ffff-ffffffffffff') {
      return null;
    }
    return cleaned;
  }
}
