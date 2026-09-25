import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../utils/responsive_utils.dart';
import '../services/library_sync_service.dart';
import '../services/university_service.dart';
import 'viewer_components/college_collection_widget.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  bool _isAdding = false;
  bool _showUniversityFolders = true;
  final TextEditingController _classController = TextEditingController();

  void _handleAddClass(BuildContext context) {
    final name = _classController.text.trim();
    if (name.isNotEmpty) {
      context.read<AppProvider>().addClass(name);
      _classController.clear();
      setState(() => _isAdding = false);
    }
  }

  // دوال الحذف والتأكيد التي حذفها الذكاء الاصطناعي بالخطأ
  void _confirmDeleteClass(
    BuildContext context,
    String classId,
    AppProvider app,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القسم؟'),
        content: const Text(
          'هل أنت متأكد من حذف هذا القسم وكل ملفات PDF بداخله؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              app.deleteClass(classId);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePdf(
    BuildContext context,
    PdfItem pdf,
    AppProvider app,
    String classId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف ملف PDF؟'),
        content: Text('هل أنت متأكد من حذف "${pdf.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              app.deletePdf(classId, pdf.id);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
      AppProvider,
      ({
        bool isDarkMode,
        List<ClassItem> classes,
        String? activeClassId,
        String? activePdfId,
        bool isCollapsed,
      })
    >(
      selector: (_, app) => (
        isDarkMode: app.isDarkMode,
        classes: app.classes,
        activeClassId: app.activeClassId,
        activePdfId: app.activePdfId,
        isCollapsed: app.isSidebarCollapsed,
      ),
      builder: (context, data, _) {
        final app = context.read<AppProvider>();
        final isDarkMode = data.isDarkMode;
        final classes = data.classes;
        final isCollapsed = data.isCollapsed;

        final screenWidth = MediaQuery.sizeOf(context).width;
        final isMobile = ResponsiveBreakpoints.isMobile(screenWidth);
        final sidebarWidth = ResponsiveBreakpoints.sidebarWidth(screenWidth);
        final scheme = Theme.of(context).colorScheme;
        final sidebarBg = isDarkMode ? const Color(0xFF0F172A) : scheme.surface;
        final separatorColor = isDarkMode
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.05);
        final textPrimary = isDarkMode
            ? const Color(0xFFF1F5F9)
            : scheme.onSurface;
        final textMuted = isDarkMode
            ? const Color(0xFF94A3B8)
            : scheme.onSurfaceVariant;

        return Container(
          width: sidebarWidth,
          decoration: BoxDecoration(
            color: sidebarBg,
            border: Border(right: BorderSide(color: separatorColor, width: 1)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: separatorColor, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.book,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'StudyFlow PDF',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isMobile ? 17 : 20,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (!isMobile)
                          IconButton(
                            onPressed: () => app.toggleSidebar(),
                            icon: Icon(
                              isCollapsed
                                  ? LucideIcons.chevronRight
                                  : LucideIcons.chevronLeft,
                              color: textMuted,
                            ),
                            tooltip: isCollapsed ? 'فتح القائمة' : 'طي القائمة',
                          ),
                        if (isMobile)
                          IconButton(
                            onPressed: () => app.toggleMobile(),
                            icon: Icon(LucideIcons.x, color: textMuted),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // --- Study Overview Dashboard ---
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1E293B),
                            Color(0xFF0F172A),
                          ], // slate-800 to slate-900
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF334155),
                        ), // slate-700
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'نظرة عامة',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF94A3B8), // slate-400
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildStatItem(
                                LucideIcons.fileText,
                                app.totalPdfs.toString(),
                                'ملفات',
                                const Color(0xFF60A5FA),
                              ),
                              Container(
                                width: 1,
                                height: 30,
                                color: const Color(0xFF334155),
                              ),
                              _buildStatItem(
                                LucideIcons.highlighter,
                                app.totalHighlights.toString(),
                                'هايلايت',
                                const Color(0xFFFBBF24),
                              ),
                              Container(
                                width: 1,
                                height: 30,
                                color: const Color(0xFF334155),
                              ),
                              _buildStatItem(
                                LucideIcons.messageSquare,
                                app.totalComments.toString(),
                                'ملاحظات',
                                const Color(0xFFA78BFA),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // "University Library" Header — click to hide/show the folders
                    InkWell(
                      onTap: () => setState(
                        () => _showUniversityFolders = !_showUniversityFolders,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'المكتبة الجامعية',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8), // slate-400
                                letterSpacing: 1.0,
                              ),
                            ),
                            Icon(
                              _showUniversityFolders
                                  ? LucideIcons.chevronUp
                                  : LucideIcons.chevronDown,
                              size: 14,
                              color: const Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Visibility(
                      visible: _showUniversityFolders,
                      maintainState: true,
                      child: CollegeCollectionWidget(
                        isDarkMode: isDarkMode,
                        panelBg: sidebarBg,
                        panelBorder: separatorColor,
                        surfaceAlt: isDarkMode
                            ? const Color(0xFF1E293B)
                            : scheme.surfaceContainerHighest,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        folderStyle: true,
                      ),
                    ),

                    // Library owner feed (sync code + member downloads) — the
                    // owner account only. Management controls come later.
                    if (_showUniversityFolders &&
                        LibrarySyncService.isOwner(app.currentUser))
                      _LibraryOwnerFeed(
                        app: app,
                        isDarkMode: isDarkMode,
                        panelBorder: separatorColor,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                      ),

                    // "Local Files" Header
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الملفات المحلية',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8), // slate-400
                            letterSpacing: 1.0,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _isAdding = true),
                          icon: const Icon(
                            LucideIcons.plus,
                            size: 16,
                            color: Color(0xFF94A3B8),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Add Class Input
                    if (_isAdding)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Builder(
                                builder: (ctx) {
                                  final scheme = Theme.of(ctx).colorScheme;
                                  final inputBg = isDarkMode
                                      ? const Color(0xFF1E293B)
                                      : scheme.surfaceContainerHigh;
                                  final inputText = isDarkMode
                                      ? Colors.white
                                      : scheme.onSurface;
                                  return TextField(
                                    controller: _classController,
                                    autofocus: true,
                                    style: TextStyle(
                                      color: inputText,
                                      fontSize: 14,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'اسم القسم...',
                                      hintStyle: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white.withOpacity(0.5)
                                            : scheme.onSurfaceVariant
                                                  .withOpacity(0.6),
                                      ),
                                      filled: true,
                                      fillColor: inputBg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                      isDense: true,
                                    ),
                                    onSubmitted: (_) =>
                                        _handleAddClass(context),
                                  );
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                LucideIcons.check,
                                color: Color(0xFF4ADE80),
                                size: 18,
                              ), // green-400
                              onPressed: () => _handleAddClass(context),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                            IconButton(
                              icon: const Icon(
                                LucideIcons.x,
                                color: Color(0xFFF87171),
                                size: 18,
                              ), // red-400
                              onPressed: () =>
                                  setState(() => _isAdding = false),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                          ],
                        ),
                      ),

                    // Local class list (custom drag/drop for folders)
                    Column(
                      children: [
                        for (final entry in classes.asMap().entries)
                          _buildClassItem(context, entry.value, app, entry.key),
                      ],
                    ),
                  ],
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: separatorColor, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => app.toggleDevInfo(!app.showDevInfo),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF1E293B)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: separatorColor),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.info,
                                  size: 16,
                                  color: isDarkMode
                                      ? const Color(0xFF60A5FA)
                                      : scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'الحقوق',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => app.toggleSettings(true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF1E293B)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: separatorColor),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.settings,
                                  size: 16,
                                  color: isDarkMode
                                      ? const Color(0xFF60A5FA)
                                      : scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'الإعدادات',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClassItem(
    BuildContext context,
    ClassItem cls,
    AppProvider app,
    int classIndex,
  ) {
    final isActive = app.activeClassId == cls.id;
    final scheme = Theme.of(context).colorScheme;
    final textMuted = app.isDarkMode
        ? const Color(0xFF94A3B8)
        : scheme.onSurfaceVariant;
    final textPrimary = app.isDarkMode
        ? const Color(0xFFF1F5F9)
        : scheme.onSurface;
    final hoverBg = app.isDarkMode
        ? const Color(0xFF1E3A8A)
        : scheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Class Header + DragTarget
        DragTarget<Map<String, String>>(
          onWillAccept: (data) {
            if (data == null) return false;
            final dragType = data['dragType'];

            if (dragType == 'pdf') {
              return data['sourceClassId'] != cls.id;
            }

            if (dragType == 'class') {
              return data['classId'] != cls.id;
            }

            return false;
          },
          onAccept: (data) async {
            final dragType = data['dragType'];

            if (dragType == 'pdf' &&
                data['pdfId'] != null &&
                data['sourceClassId'] != null) {
              await app.movePdf(data['pdfId']!, data['sourceClassId']!, cls.id);
              return;
            }

            if (dragType == 'class' && data['classId'] != null) {
              final sourceClassId = data['classId']!;
              final oldIndex = app.classes.indexWhere(
                (c) => c.id == sourceClassId,
              );
              if (oldIndex == -1 || oldIndex == classIndex) return;
              app.reorderClasses(oldIndex, classIndex);
            }
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return InkWell(
              onTap: () => app.setActiveClass(cls.id),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: isHovering
                      ? hoverBg
                      : (isActive
                            ? (app.isDarkMode
                                  ? const Color(0xFF1E293B)
                                  : scheme.surfaceContainerHigh)
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        cls.name,
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF60A5FA)
                              : textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: IconButton(
                                                padding: EdgeInsets.zero,

                        icon: Icon(
                          LucideIcons.upload,
                          size: 14,
                          color: textMuted,
                        ),
                        tooltip: 'رفع PDF',
                        onPressed: () => app.uploadPdf(cls.id),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Draggable<Map<String, String>>(
                      data: {'dragType': 'class', 'classId': cls.id},
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: 220,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.folder,
                                size: 14,
                                color: Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  cls.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFFF1F5F9),
                                    decoration: TextDecoration.none,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      childWhenDragging: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          LucideIcons.gripVertical,
                          size: 16,
                          color: textMuted.withOpacity(0.35),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          LucideIcons.gripVertical,
                          size: 16,
                          color: textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          LucideIcons.trash2,
                          size: 16,
                          color: Color(0xFFF87171),
                        ),
                        tooltip: 'حذف القسم',
                        onPressed: () =>
                            _confirmDeleteClass(context, cls.id, app),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // PDF List
        if (isActive)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: app.isDarkMode
                        ? const Color(0xFF1E293B)
                        : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                children: cls.pdfs
                    .map((pdf) => _buildPdfItem(context, pdf, app, cls.id))
                    .toList(),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPdfItem(
    BuildContext context,
    PdfItem pdf,
    AppProvider app,
    String classId,
  ) {
    final isActive = app.activePdfId == pdf.id;
    final isSecondary = app.isSplitMode && app.secondaryPdfId == pdf.id;


    final child = InkWell(
      onTap: () {
        if (app.isSplitMode && !isActive) {
          app.setSecondaryPdf(pdf.id);
        } else {
          app.setActivePdf(pdf.id);
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0x4D1E3A8A)
              : (isSecondary ? const Color(0x2694A3B8) : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
          border: isSecondary
              ? Border.all(color: const Color(0x3394A3B8), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.fileText,
              size: 14,
              color: isActive
                  ? const Color(0xFFBFDBFE)
                  : (isSecondary ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pdf.name,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive
                      ? const Color(0xFFBFDBFE)
                      : (isSecondary ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8)),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              height: 24,
              width: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 14,
                  color: Color(0xFFF87171),
                ),
                tooltip: 'حذف PDF',
                onPressed: () => _confirmDeletePdf(context, pdf, app, classId),
              ),
            ),
          ],
        ),
      ),
    );

    return DragTarget<Map<String, String>>(
      onWillAccept: (data) =>
          data != null &&
          data['dragType'] == 'pdf' &&
          data['pdfId'] != null &&
          data['pdfId'] != pdf.id,
      onAccept: (data) async {
        final draggedPdfId = data['pdfId'];
        final sourceClassId = data['sourceClassId'];
        if (draggedPdfId == null || sourceClassId == null) return;

        if (sourceClassId == classId) {
          app.reorderPdfWithinClass(classId, draggedPdfId, pdf.id);
          return;
        }

        await app.movePdf(draggedPdfId, sourceClassId, classId);
        await app.reorderPdfWithinClass(classId, draggedPdfId, pdf.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final targetChild = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isHovering ? const Color(0x223B82F6) : Colors.transparent,
            border: isHovering
                ? Border.all(color: const Color(0xFF3B82F6), width: 1)
                : null,
          ),
          child: child,
        );

        return Draggable<Map<String, String>>(
          data: {'dragType': 'pdf', 'pdfId': pdf.id, 'sourceClassId': classId},
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.fileText,
                    size: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pdf.name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFF1F5F9),
                        decoration: TextDecoration.none,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: targetChild),
          child: targetChild,
        );
      },
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library owner feed — shown to the owner account (username "abnmazin") under
// "المكتبة الجامعية". Shows the live downloads by members (auto-connected to
// each file's own sync code). No sync code is displayed anywhere.
// Management controls (kick/delete) are intentionally left for later work.
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryOwnerFeed extends StatefulWidget {
  final AppProvider app;
  final bool isDarkMode;
  final Color panelBorder;
  final Color textPrimary;
  final Color textMuted;

  const _LibraryOwnerFeed({
    required this.app,
    required this.isDarkMode,
    required this.panelBorder,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  State<_LibraryOwnerFeed> createState() => _LibraryOwnerFeedState();
}

class _LibraryOwnerFeedState extends State<_LibraryOwnerFeed> {
  final LibrarySyncService _sync = LibrarySyncService();

  @override
  void initState() {
    super.initState();
    _initOwner();
  }

  /// Owner-only setup: backfill sync codes onto existing uploaded files so
  /// every library booklet already has its own code linked.
  Future<void> _initOwner() async {
    final user = widget.app.currentUser;
    if (user == null) return;
    try {
      final service = UniversityService();
      if (!service.isReady) await service.init(user);
      await service.backfillSyncCodes();
    } catch (e) {
      debugPrint('📡 [LibrarySync] Owner backfill failed: $e');
    }
  }

  String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.app.currentUser;
    final universityId = user?.universityId ?? '';
    if (universityId.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _sync.watchLibraryDownloads(universityId),
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? [];
          if (snapshot.hasError || !snapshot.hasData) {
            return const SizedBox.shrink();
          }

          // Flatten every file-session's downloads into feed rows.
          final rows = <({String username, String fileName, int atMillis})>[];
          for (final session in sessions) {
            final fileName = (session['fileName'] ?? '').toString();
            final raw = session['downloads'];
            if (raw is! List) continue;
            for (final item in raw.whereType<Map>()) {
              rows.add((
                username: (item['username'] ?? 'member').toString(),
                fileName: fileName,
                atMillis: (item['downloadedAt'] as num?)?.toInt() ?? 0,
              ));
            }
          }
          rows.sort((a, b) => b.atMillis.compareTo(a.atMillis));

          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'لا توجد تحميلات بعد',
                style: TextStyle(fontSize: 11.5, color: widget.textMuted),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الأعضاء الذين حمّلوا (${rows.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              ...rows.take(30).map((row) {
                final time = row.atMillis > 0
                    ? _relative(DateTime.fromMillisecondsSinceEpoch(
                        row.atMillis,
                      ))
                    : '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.download,
                        size: 13,
                        color: Color(0xFF22C55E),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.username,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              row.fileName,
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.textMuted,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
