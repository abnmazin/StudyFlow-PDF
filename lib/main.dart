import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'services/file_manager_service.dart';
import 'widgets/sidebar_w.dart';
import 'widgets/pdf_viewer_widget_w.dart';
import 'widgets/developer_modal_w.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚀 OPTIMIZATION: منع استهلاك الرام العالي (ت    حديد الذاكرة بـ 50 ميجا)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 10 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 20;

  // Initialize file storage layer before the first frame
  final fileManager = FileManagerService();
  await fileManager.init();

  // WINDOWS FILE ASSOCIATION: Capture PDF file path from command-line
  String? initialFilePath;
  if (args.isNotEmpty && args[0].toLowerCase().endsWith('.pdf')) {
    initialFilePath = args[0];
  }

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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3B82F6),
          ), // blue-500
          useMaterial3: true,
          fontFamily: 'Inter', // Ensure Inter font is available or fallback
          scaffoldBackgroundColor: const Color(0xFFF8FAFC), // slate-50
        ),
        home: MainLayout(initialPdfPath: initialPdfPath),
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
  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              // Sidebar (Desktop)
              if (!isMobile && !app.isSidebarCollapsed) const Sidebar(),

              // Main Content
              Expanded(child:  PDFViewerWidget()),
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

          // Setup Modal
          // We can put modals here if they are global,
          // or just use showDialog in Flutter.
          // The React app had a custom modal component.
          // Let's use the custom DeveloperModal here as an overlay.
          DeveloperModal(
            isOpen: app.showDevInfo,
            onClose: () => app.toggleDevInfo(false),
          ),
        ],
      ),
    );
  }
}
