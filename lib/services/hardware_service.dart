import 'dart:io';

class HardwareService {
  Future<String> getDeviceUUID() async {
    final fromWmic = await _fromWmic();
    if (fromWmic != null) return fromWmic;

    final fromCim = await _fromPowerShellCim();
    if (fromCim != null) return fromCim;

    final fromRegistry = await _fromRegistryMachineGuid();
    if (fromRegistry != null) return fromRegistry;

    return 'Unknown-Device-ID';
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
