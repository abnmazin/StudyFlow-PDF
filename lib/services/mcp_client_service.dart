import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Bridges the Flutter app to the `gemini-app-mcp` Node.js server.
///
/// The server is a JSON-RPC 2.0 MCP endpoint over stdio (newline-delimited
/// JSON). It uses browser automation (Patchright/Playwright) to drive
/// gemini.google.com with the user's personal Google account, so **no API key
/// is required**.
///
/// Protocol summary:
///   stdin:  {"jsonrpc":"2.0","id":0,"method":"initialize",...}
///   stdout: {"jsonrpc":"2.0","id":0,"result":{...}}
///   stdin:  {"jsonrpc":"2.0","method":"notifications/initialized"}
///   stdin:  {"jsonrpc":"2.0","id":1,"method":"tools/call",
///            "params":{"name":"ask_question","arguments":{"question":"..."}}}
class McpClientService {
  McpClientService._();

  static final McpClientService instance = McpClientService._();

  static const String _packageName = 'gemini-app-mcp';
  static const Duration _requestTimeout = Duration(seconds: 60);
  static const Duration _processSpawnTimeout = Duration(seconds: 20);

  Process? _process;
  bool _handshakeComplete = false;
  int _requestId = 0;
  String? _sessionId;
  bool _nodeAvailableChecked = false;
  bool _nodeAvailable = false;
  final Map<int, Completer<Map<String, dynamic>>> _pendingResponses = {};
  final StreamController<String> _stderrLog =
      StreamController<String>.broadcast();
  bool _spawning = false;

  String? get sessionId => _sessionId;
  Stream<String> get stderrLog => _stderrLog.stream;

  /// Whether a server process is currently alive and initialized.
  bool get isRunning => _process != null && _handshakeComplete;

  /// True if the OS has a usable Node.js / npx runtime.
  Future<bool> get isNodeAvailable async {
    if (_nodeAvailableChecked) return _nodeAvailable;
    _nodeAvailableChecked = true;
    _nodeAvailable = await _resolveRunner() != null;
    return _nodeAvailable;
  }

  /// Resolves the command used to launch the server.
  ///
  /// On Windows `npx` is `npx.cmd`, which `Process.start` cannot resolve on
  /// its own, so we resolve the full path first.
  Future<String?> _resolveRunner() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'where.exe',
          ['npx'],
          runInShell: true,
        );
        if (result.exitCode != 0) return null;
        final line = result.stdout
            .toString()
            .trim()
            .split(RegExp(r'\r?\n'))
            .firstWhere(
              (l) => l.trim().isNotEmpty,
              orElse: () => '',
            );
        return line.isEmpty ? null : line.trim();
      } catch (_) {
        return null;
      }
    }
    try {
      final result = await Process.run('which', ['npx']);
      if (result.exitCode != 0) return null;
      final path = result.stdout.toString().trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  /// Spawns the server process (if not already running) and completes the MCP
  /// handshake. Safe to call repeatedly; does nothing if already initialized.
  Future<void> start() async {
    if (isRunning) return;
    if (_spawning) {
      await _waitForRun();
      return;
    }
    _spawning = true;
    try {
      await _killLingeringChrome();
      final runner = await _resolveRunner();
      if (runner == null) {
        throw const McpException(
          'MCP_UNAVAILABLE',
          'Node.js is not installed. Install Node.js to use MCP.',
        );
      }

      final process = await Process.start(
        runner,
        ['-y', '$_packageName@latest'],
        runInShell: Platform.isWindows,
        environment: {
          ...Platform.environment,
          'HEADLESS': 'true',
        },
      ).timeout(_processSpawnTimeout);

      _process = process;
      _wirePipes(process);
      await _performHandshake(process);
      _handshakeComplete = true;
      debugPrint('[Mcp] server started & handshake complete');
    } finally {
      _spawning = false;
    }
  }

  Future<void> _waitForRun() async {
    final deadline = DateTime.now().add(_processSpawnTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isRunning) return;
      if (!_spawning && _process == null) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw const McpException(
      'MCP_TIMEOUT',
      'Timed out waiting for the MCP server to start.',
    );
  }

  /// Kills any leftover Chrome processes still holding gemini-app-mcp's
  /// shared profile directory.
  ///
  /// `gemini-app-mcp` runs Chrome with a fixed `--user-data-dir` that has no
  /// environment override. If a previous instance (or an app crash) left that
  /// Chrome running, the next launch aborts with exit code 21 ("profile in
  /// use") and every request hangs. We therefore terminate any process whose
  /// command line references that profile before (re)spawning the server.
  Future<void> _killLingeringChrome() async {
    if (!Platform.isWindows) return;
    try {
      final script = r'''
$procs = Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction SilentlyContinue
foreach ($p in $procs) {
  if ($p.CommandLine -and $p.CommandLine -like '*gemini-mcp*chrome_profile*') {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }
}
''';
      await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: false,
      ).timeout(_requestTimeout);
    } catch (e) {
      debugPrint('[Mcp] failed to kill lingering Chrome: $e');
    }
  }

  void _wirePipes(Process process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleIncomingLine);

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isNotEmpty && !_stderrLog.isClosed) {
        _stderrLog.add(line);
      }
    });

    process.exitCode.then((code) {
      debugPrint('[Mcp] server exited with code $code');
      final dead = _process;
      if (identical(dead, process)) {
        _process = null;
        _handshakeComplete = false;
      }
      for (final completer in _pendingResponses.values) {
        if (!completer.isCompleted) {
          completer.completeError(const McpException(
            'MCP_DIED',
            'The MCP server process exited unexpectedly.',
          ));
        }
      }
      _pendingResponses.clear();
    });
  }

  void _handleIncomingLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final message = jsonDecode(line) as Map<String, dynamic>;
      final id = message['id'];
      if (id is num && _pendingResponses.containsKey(id)) {
        final completer = _pendingResponses.remove(id);
        if (completer == null || completer.isCompleted) return;
        if (message.containsKey('result')) {
          completer.complete(
            (message['result'] as Map<String, dynamic>?) ?? const {},
          );
        } else if (message.containsKey('error')) {
          final error = message['error'] as Map<String, dynamic>?;
          completer.completeError(McpException(
            'MCP_ERROR_${error?['code'] ?? 'UNKNOWN'}',
            (error?['message'] ?? 'Unknown MCP error').toString(),
          ));
        }
      }
    } catch (e) {
      debugPrint('[Mcp] failed to parse stdout line: $e');
    }
  }

  Future<void> _performHandshake(Process process) async {
    final response = await _sendRequest(
      process,
      'initialize',
      0,
      {
        'protocolVersion': '2025-11-25',
        'capabilities': const {},
        'clientInfo': const {
          'name': 'studyflow',
          'version': '1.1.0',
        },
      },
    );
    if (!response.containsKey('serverInfo')) {
      throw const McpException(
        'MCP_HANDSHAKE',
        'Invalid initialize response from MCP server.',
      );
    }
    _sendNotification(process, 'notifications/initialized', const {});
  }

  int _nextId() => ++_requestId;

  Future<Map<String, dynamic>> _sendRequest(
    Process process,
    String method,
    int id,
    Map<String, dynamic> params, {
    Duration? timeout,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    _pendingResponses[id] = completer;
    final line = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    process.stdin.writeln(line);
    await process.stdin.flush();
    return completer.future.timeout(
      timeout ?? _requestTimeout,
      onTimeout: () {
        _pendingResponses.remove(id);
        throw McpException('MCP_TIMEOUT', 'Request "$method" timed out.');
      },
    );
  }

  void _sendNotification(
    Process process,
    String method,
    Map<String, dynamic> params,
  ) {
    process.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      if (params.isNotEmpty) 'params': params,
    }));
  }

  Future<Map<String, dynamic>> _callTool(
    String name,
    Map<String, dynamic> arguments, {
    Duration timeout = _requestTimeout,
  }) async {
    await start();
    final process = _process;
    if (process == null) {
      throw const McpException(
        'MCP_UNAVAILABLE',
        'MCP server could not be started.',
      );
    }
    final result = await _sendRequest(
      process,
      'tools/call',
      _nextId(),
      {'name': name, 'arguments': arguments},
      timeout: timeout,
    );
    return _extractInnerText(result);
  }

  Map<String, dynamic> _extractInnerText(Map<String, dynamic> result) {
    final content = result['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map<String, dynamic>) {
        final text = first['text'];
        if (text is String && text.isNotEmpty) {
          try {
            final decoded = jsonDecode(text) as Map<String, dynamic>;
            return decoded;
          } catch (_) {
            return {'success': false, 'error': text};
          }
        }
      }
    }
    return {'success': false, 'error': 'Unexpected MCP result shape'};
  }

  /// Asks the personal Gemini app a question and returns the answer text.
  ///
  /// Conversation continuity is kept by internally reusing the session id
  /// returned by the server. Call [resetConversation] to start fresh.
  Future<String> askQuestion(String question) async {
    try {
      return await _askQuestionInner(question);
    } catch (e) {
      final isBrowserCrash = e.toString().contains(RegExp(
        r'browser (has been )?closed|launchPersistentContext|exitCode=21|gracefully close',
        caseSensitive: false,
      ));
      if (isBrowserCrash) {
        // The backing Chrome died or its profile dir is still locked by a
        // previous instance. Kill the server and any lingering Chrome, then
        // retry once with a fresh instance.
        debugPrint('[Mcp] browser crashed, restarting server for retry...');
        await stop();
        resetConversation();
        try {
          return await _askQuestionInner(question);
        } catch (retryError) {
          debugPrint('[Mcp] retry also failed: $retryError');
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<String> _askQuestionInner(String question) async {
    final result = await _callTool('ask_question', {
      'question': question,
      'browser_options': const {'headless': true},
      if (_sessionId != null && _sessionId!.isNotEmpty)
        'session_id': _sessionId,
    });

    final data = result['data'];
    if (data is Map<String, dynamic>) {
      final status = data['status'];
      if (status == 'success') {
        final newSession = data['session_id'];
        if (newSession is String && newSession.isNotEmpty) {
          _sessionId = newSession;
        }
        final answer = data['answer'];
        if (answer is String && answer.trim().isNotEmpty) {
          return answer.trim();
        }
      }
      final answer = data['answer'];
      if (answer is String && answer.trim().isNotEmpty) {
        return answer.trim();
      }
    }

    final error = result['error'] ?? 'Unknown MCP ask_question failure';
    if (error.toString().contains(RegExp(r'authenticat|login|sign in', caseSensitive: false))) {
      throw const McpException(
        'MCP_NOT_AUTHENTICATED',
        'gemini-app-mcp is not authenticated. Open Settings > AI and press '
        '"Connect Google Account".',
      );
    }
    throw McpException('MCP_QUESTION_FAILED', error.toString());
  }

  /// Clears the in-memory conversation session id.
  void resetConversation() {
    _sessionId = null;
  }

  /// Calls the MCP `get_health` tool.
  Future<Map<String, dynamic>> getHealth() async {
    return _callTool('get_health', const {});
  }

  /// Triggers the MCP `setup_auth` tool, which opens a visible browser window
  /// for the user to log into their Google account. Long timeout because the
  /// user has up to 10 minutes to complete login.
  Future<Map<String, dynamic>> setupAuth() async {
    await start();
    final result = await _callTool(
      'setup_auth',
      const {
        'show_browser': true,
        'browser_options': {
          'show': true,
          'headless': false,
          'timeout_ms': 600000,
        },
      },
      timeout: const Duration(minutes: 11),
    );
    return result;
  }

  /// Stops the server process (idempotent).
  Future<void> stop() async {
    final process = _process;
    _process = null;
    _handshakeComplete = false;
    if (process == null) return;
    try {
      process.stdin.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'shutdown',
        'id': _nextId(),
      }));
      await process.stdin.flush();
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      process.kill();
    }
    if (await _isProcessAlive(process)) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  Future<bool> _isProcessAlive(Process process) async {
    final exitCode = process.exitCode;
    try {
      await exitCode.timeout(const Duration(milliseconds: 200));
      return false;
    } catch (_) {
      return true;
    }
  }
}

class McpException implements Exception {
  const McpException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'McpException($code): $message';
}