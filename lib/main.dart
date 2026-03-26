import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

import 'providers/app_state.dart';
import 'services/file_manager_service.dart';
import 'widgets/sidebar_w.dart';
import 'widgets/pdf_viewer_widget_w.dart';
import 'widgets/developer_modal_w.dart';
import 'widgets/global_settings_modal.dart'; // NEW
import 'screens/auth/login_screen.dart';
import 'firebase_options.dart';

const int _kSingleInstancePort = 45678;
final StreamController<String> _incomingPdfPaths =
    StreamController<String>.broadcast();
ServerSocket? _singleInstanceServer;

String? _extractPdfPathFromArgs(List<String> args) {
  for (final raw in args) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    var candidate = trimmed;
    if (candidate.startsWith('"') && candidate.endsWith('"')) {
      candidate = candidate.substring(1, candidate.length - 1);
    }

    if (candidate.startsWith('file:///')) {
      try {
        candidate = Uri.parse(candidate).toFilePath(windows: true);
      } catch (_) {}
    }

    if (!candidate.toLowerCase().endsWith('.pdf')) continue;

    // Prefer existing file paths when available.
    if (File(candidate).existsSync()) {
      return candidate;
    }

    // Fallback for paths that may be temporarily inaccessible.
    return candidate;
  }
  return null;
}

Future<bool> _sendPdfToRunningInstance(String filePath) async {
  Future<bool> tryAddress(InternetAddress address) async {
    try {
      final socket = await Socket.connect(
        address,
        _kSingleInstancePort,
        timeout: const Duration(milliseconds: 1200),
      );
      socket.write('$filePath\n');
      await socket.flush();

      final completer = Completer<bool>();
      final buffer = StringBuffer();

      socket.listen(
        (chunk) {
          buffer.write(utf8.decode(chunk));
        },
        onDone: () async {
          final response = buffer.toString().trim();
          await socket.close();
          completer.complete(response == 'OK');
        },
        onError: (_) async {
          await socket.close();
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
        cancelOnError: true,
      );

      return await completer.future.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () async {
          await socket.close();
          return false;
        },
      );
    } catch (_) {
      return false;
    }
  }

  if (await tryAddress(InternetAddress.loopbackIPv4)) return true;
  if (await tryAddress(InternetAddress.loopbackIPv6)) return true;
  return false;
}

Future<void> _startSingleInstanceServer() async {
  if (_singleInstanceServer != null) return;

  try {
    _singleInstanceServer = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      _kSingleInstancePort,
      shared: false,
    );

    _singleInstanceServer!.listen((client) {
      final buffer = StringBuffer();
      client.listen(
        (chunk) {
          buffer.write(utf8.decode(chunk));
        },
        onDone: () async {
          final message = buffer.toString().trim();
          if (message.toLowerCase().endsWith('.pdf')) {
            _incomingPdfPaths.add(message);
            client.write('OK\n');
            await client.flush();
          } else {
            client.write('ERR\n');
            await client.flush();
          }
          await client.close();
        },
      );
    });
  } catch (_) {
    // Another instance may already own the port. That's acceptable for normal launches.
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load .env file if it exists (graceful error handling)
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    print('Warning: .env file not found. Using defaults or environment variables.');
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );



  // 🚀 OPTIMIZATION: منع استهلاك الرام العالي (ت    حديد الذاكرة بـ 50 ميجا)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 10 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 20;

  // Initialize file storage layer before the first frame
  final fileManager = FileManagerService();
  await fileManager.init();

  // WINDOWS FILE ASSOCIATION: Capture PDF file path from command-line
  String? initialFilePath = _extractPdfPathFromArgs(args);

  if (initialFilePath != null) {
    final forwarded = await _sendPdfToRunningInstance(initialFilePath);
    if (forwarded) {
      return;
    }
  }

  await _startSingleInstanceServer();

  runApp(MyApp(initialPdfPath: initialFilePath, fileManager: fileManager));
}

class MyApp extends StatelessWidget {
  final String? initialPdfPath;
  final FileManagerService fileManager;

  const MyApp({super.key, this.initialPdfPath, required this.fileManager});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => fileManager),
        ChangeNotifierProvider(create: (_) => AppProvider()),
      ],
      child: MaterialApp(
        title: 'StudyFlow',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData.dark().copyWith(
          colorScheme: ThemeData.dark().colorScheme.copyWith(
            primary: Colors.blueAccent,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  final String? initialPdfPath;

  const MainLayout({super.key, this.initialPdfPath});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isDragOver = false;
  StreamSubscription<String>? _incomingPdfSubscription;

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    final app = context.read<AppProvider>();
    await app.initialized;

    for (final file in files) {
      final path = file.path;
      if (path.toLowerCase().endsWith('.pdf')) {
        await app.loadPdfFromPath(path);
        if (!mounted) return;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _incomingPdfSubscription = _incomingPdfPaths.stream.listen((path) async {
      if (!mounted) return;
      final app = context.read<AppProvider>();
      await app.initialized;
      await app.loadPdfFromPath(path);
    });

    // Load initial PDF file if provided via command-line
    if (widget.initialPdfPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final app = context.read<AppProvider>();
        await app.initialized; // Wait for state to load
        app.loadPdfFromPath(widget.initialPdfPath!);
      });
    }
  }

  @override
  void dispose() {
    _incomingPdfSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      body: DropTarget(
        onDragEntered: (_) {
          if (mounted) {
            setState(() => _isDragOver = true);
          }
        },
        onDragExited: (_) {
          if (mounted) {
            setState(() => _isDragOver = false);
          }
        },
        onDragDone: (details) async {
          if (mounted) {
            setState(() => _isDragOver = false);
          }
          await _handleDroppedFiles(details.files);
        },
        child: Stack(
          children: [
            Row(
              children: [
                // Sidebar (Desktop)
                if (!isMobile && !app.isSidebarCollapsed) const Sidebar(),

                // Main Content
                Expanded(child: PDFViewerWidget()),
              ],
            ),

            // Mobile Drawer Overlay
            if (isMobile && app.isMobileOpen)
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => app.toggleMobile(),
                    child: Container(color: Colors.black.withOpacity(0.5)),
                  ),
                  const Sidebar(),
                ],
              ),

            if (_isDragOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xFF2563EB).withOpacity(0.12),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF2563EB),
                          width: 1.5,
                        ),
                      ),
                      child: const Text(
                        'Drop PDF to open',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Setup Modal
            DeveloperModal(
              isOpen: app.showDevInfo,
              onClose: () => app.toggleDevInfo(false),
            ),

            // Global Settings Modal (Drawer style from right)
            if (app.isSettingsOpen)
              Positioned.fill(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () => app.toggleSettings(false),
                      child: Container(color: Colors.black.withOpacity(0.4)),
                    ),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: GlobalSettingsModal(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
