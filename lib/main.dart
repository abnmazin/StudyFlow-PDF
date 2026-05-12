import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'providers/app_state.dart';
import 'services/file_manager_service.dart';
import 'services/sync_service.dart';
import 'widgets/floating_window_manager.dart';
import 'widgets/sidebar_w.dart';
import 'widgets/pdf_viewer_widget_w.dart';
import 'widgets/developer_modal_w.dart';
import 'widgets/global_settings_modal.dart'; // NEW
import 'widgets/version_check_gate.dart';
import 'screens/auth/login_screen.dart';
import 'models/app_user.dart';
import 'firebase_options.dart';
import 'utils/responsive_utils.dart';

const int _kSingleInstancePort = 45678;
final StreamController<String> _incomingPdfPaths =
    StreamController<String>.broadcast();
ServerSocket? _singleInstanceServer;
String? _pendingColdStartPath;
const String _kDefaultSupabaseUrl = 'https://kyuvnoprpeiokkeovmxe.supabase.co';
const String _kDefaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt5dXZub3BycGVpb2trZW92bXhlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgwMDE0MzgsImV4cCI6MjA5MzU3NzQzOH0.ydL-XfR6Xd-1iGk0nBUDhp-DEC8GEX7HsLEgDLsWSys';

String _readSupabaseValue(String key, String fallback) {
  final value = dotenv.maybeGet(key)?.trim() ?? '';
  return value.isEmpty ? fallback : value;
}

Future<void> _initializeSupabase() async {
  await Supabase.initialize(
    url: _readSupabaseValue('SUPABASE_URL', _kDefaultSupabaseUrl),
    anonKey: _readSupabaseValue('SUPABASE_ANON_KEY', _kDefaultSupabaseAnonKey),
  );
}

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

Future<void> _bootstrapApp(List<String> args) async {
  String? startupError;
  StackTrace? startupStack;

  try {
    String? initialFilePath = _extractPdfPathFromArgs(args);
    if (initialFilePath != null) {
      final forwarded = await _sendPdfToRunningInstance(initialFilePath);
      if (forwarded) {
        exit(0);
      }
    }

    // Load .env file if it exists (graceful error handling)
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('⚠️ [Boot] .env load skipped: $e');
    }

    await _initializeSupabase();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );

    // 🚀 OPTIMIZATION: Ultra-lean startup RAM (Set to 2MB for Dashboard)
    // This will be expanded to 50MB in AppProvider when a PDF is opened.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 2 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 10;

    // Initialize file storage layer before the first frame
    final fileManager = FileManagerService();
    await fileManager.init();

    await _startSingleInstanceServer();

    _pendingColdStartPath = initialFilePath;
    runApp(MyApp(fileManager: fileManager));
  } catch (error, stackTrace) {
    startupError = error.toString();
    startupStack = stackTrace;
    debugPrint('❌ [Boot] Startup failed: $startupError');
    runApp(
      StartupDiagnosticApp(
        errorMessage: startupError,
        stackTrace: startupStack,
      ),
    );
  }
}
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _bootstrapApp(args);
}

class MyApp extends StatelessWidget {
  final FileManagerService fileManager;

  const MyApp({super.key, required this.fileManager});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => SyncService()),
        ChangeNotifierProvider(create: (_) => fileManager),
        ChangeNotifierProvider(
          create: (context) =>
              AppProvider(syncService: context.read<SyncService>()),
        ),
        ChangeNotifierProvider(create: (_) => WindowManagerProvider()),
      ],
      child: Builder(
        builder: (context) {
          final themeMode = context.select<AppProvider, ThemeMode>(
            (app) => app.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          );
          return VersionCheckGate(
            child: MaterialApp(
              title: 'StudyFlow PDF',
              debugShowCheckedModeBanner: false,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              themeMode: themeMode,
              theme: ThemeData.light().copyWith(
                colorScheme: ThemeData.light().colorScheme.copyWith(
                  primary: Colors.blueAccent,
                  surface: Colors.white,
                  onSurface: const Color(0xFF0F172A), // Dark slate wording
                  surfaceContainerHighest: const Color(
                    0xFFF1F5F9,
                  ), // Subtle slate backgrounds
                  outlineVariant: const Color(0xFFE2E8F0),
                ),
                scaffoldBackgroundColor: const Color(
                  0xFFF8FAFC,
                ), // Off-white clean background
                cardColor: Colors.white,
              ),
              darkTheme: ThemeData.dark().copyWith(
                colorScheme: ThemeData.dark().colorScheme.copyWith(
                  primary: Colors.blueAccent,
                ),
                scaffoldBackgroundColor: const Color(0xFF121212),
              ),
              home: const RootWrapper(),
            ),
          );
        },
      ),
    );
  }
}

class StartupDiagnosticApp extends StatelessWidget {
  final String? errorMessage;
  final StackTrace? stackTrace;

  const StartupDiagnosticApp({super.key, this.errorMessage, this.stackTrace});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Startup configuration error',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Firebase or app bootstrap failed before the main UI could load.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    errorMessage ?? 'Unknown startup error',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  if (stackTrace != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Stack trace',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          stackTrace.toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RootWrapper extends StatelessWidget {
  const RootWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Phase 2 Optimization: Use granular selection to prevent global rebuilds
    final initialized = context.select<AppProvider, Future<void>?>(
      (p) => p.initialized,
    );
    final currentUser = context.select<AppProvider, AppUser?>(
      (p) => p.currentUser,
    );

    return FutureBuilder(
      future: initialized,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          // Initialization complete, check if we have a user
          if (currentUser != null) {
            return const MainLayout();
          } else {
            return const LoginScreen();
          }
        }

        // Splash / Loading state
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blueAccent,
                    ),
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'StudyFlow PDF',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isDragOver = false;
  StreamSubscription<String>? _incomingPdfSubscription;
  late AppProvider _appProvider;

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    final app = _appProvider;
    await app.initialized;

    for (final file in files) {
      var path = file.path;
      if (path.startsWith('file://')) {
        try {
          path = Uri.parse(path).toFilePath();
        } catch (_) {
          // Keep original path if URI parsing fails.
        }
      }

      if (path.toLowerCase().endsWith('.pdf')) {
        await app.loadPdfFromPath(path);
        if (!mounted) return;
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // Phase 11: Real-time Security Listener
    _appProvider = context.read<AppProvider>();
    _appProvider.addListener(_securityListener);

    // Silent Account Verification (Optimistic UI) — delayed to avoid startup CPU spike
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _appProvider.verifyAccountStatusSilently(context);
      });
    });

    _incomingPdfSubscription = _incomingPdfPaths.stream.listen((path) async {
      if (!mounted) return;
      final app = _appProvider;
      await app.initialized;
      await app.loadPdfFromPath(path);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final coldPath = _pendingColdStartPath;
      if (coldPath != null) {
        _pendingColdStartPath = null;
        final app = _appProvider;
        await app.initialized;
        await app.loadPdfFromPath(coldPath);
      }
    });
  }

  @override
  void dispose() {
    _appProvider.removeListener(_securityListener);
    _incomingPdfSubscription?.cancel();
    super.dispose();
  }

  void _securityListener() {
    if (!mounted) return;
    final app = _appProvider;
    final reason = app.forcedLogoutReason;
    final isGlobal = app.isGlobalLogout;
    final isKicked = app.isKicked;

    if (reason != null || isKicked) {
      // Clear immediately to prevent UI loop
      app.clearForcedLogoutReason();

      // Notify user via Toast/Snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason ?? 'لقد تم إنهاء وصولك لهذه الجلسة',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: const Color(0xFFEF4444), // Intense Red
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      // Force Redirect to Login ONLY if account is deleted from system (Global)
      if (isGlobal) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
      // Note: If session-only kick, we stay on the current screen (Viewer)
      // but it will automatically show the "Join" UI because currentSessionCode is cleared.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSidebarCollapsed = context.select<AppProvider, bool>(
      (p) => p.isSidebarCollapsed,
    );
    final isMobileOpen = context.select<AppProvider, bool>(
      (p) => p.isMobileOpen,
    );
    final showDevInfo = context.select<AppProvider, bool>((p) => p.showDevInfo);
    final isSettingsOpen = context.select<AppProvider, bool>(
      (p) => p.isSettingsOpen,
    );

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = ResponsiveBreakpoints.isMobile(screenWidth);

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
                if (!isMobile && !isSidebarCollapsed) const Sidebar(),

                // Main Content
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      RepaintBoundary(child: PDFViewerWidget()),
                      const Positioned.fill(child: FloatingWindowLayer()),
                    ],
                  ),
                ),
              ],
            ),

            // Mobile Drawer Overlay
            if (isMobile && isMobileOpen)
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => context.read<AppProvider>().toggleMobile(),
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
                        'قم بسحب ملف PDF لفتحه',
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
            Positioned.fill(
              child: DeveloperModal(
                isOpen: showDevInfo,
                onClose: () => context.read<AppProvider>().toggleDevInfo(false),
              ),
            ),

            // Global Settings Modal (Drawer style from right)
            if (isSettingsOpen)
              Positioned.fill(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () =>
                          context.read<AppProvider>().toggleSettings(false),
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
