import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../utils/responsive_utils.dart';
import 'viewer_components/college_collection_widget.dart';
import 'university_cloud_library_w.dart';
import 'dashboard/dashboard_palette.dart';

/// Which half of the sidebar explorer is on screen.
///
/// The university library and the local folders used to be two stacked
/// collapsible sections; they are one row of two tabs now, so exactly one of
/// the two lists is visible at a time.
enum _ExplorerTab { university, local }

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  bool _isAdding = false;

  /// Tap behaviour is plain tabs: tapping the selected word does nothing, so
  /// the sidebar always has one list showing.
  _ExplorerTab _tab = _ExplorerTab.university;

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
        bool isCollapseLocked,
      })
    >(
      selector: (_, app) => (
        isDarkMode: app.isDarkMode,
        classes: app.classes,
        activeClassId: app.activeClassId,
        activePdfId: app.activePdfId,
        isCollapsed: app.isSidebarCollapsedEffective,
        isCollapseLocked: app.isSidebarForcedOpen,
      ),
      builder: (context, data, _) {
        final app = context.read<AppProvider>();
        final classes = data.classes;
        final isCollapsed = data.isCollapsed;
        final isCollapseLocked = data.isCollapseLocked;

        final screenWidth = MediaQuery.sizeOf(context).width;
        final isMobile = ResponsiveBreakpoints.isMobile(screenWidth);
        final sidebarWidth = ResponsiveBreakpoints.sidebarWidth(screenWidth);
        // The sidebar carries the app's primary colour, so it is painted from
        // the shared palette instead of from the theme: in light mode the
        // theme's surface is white, and a white sidebar is not this app.
        final sidebarBg = DashboardColors.background;
        final separatorColor = DashboardColors.separator;
        final textPrimary = DashboardColors.title;
        final textMuted = DashboardColors.subtitle;
        final selectedTabColor = DashboardColors.title;

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
                  // Laid out left-to-right on purpose, against the app's RTL
                  // context: the brand leads the row and the collapse/close
                  // control trails it. Inheriting the ambient direction put the
                  // brand on the right of the row instead, which is not the
                  // arrangement this header is drawn for.
                  textDirection: TextDirection.ltr,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        // Same reason as the row above: without this the inner
                        // row takes the ambient RTL and puts the icon after the
                        // title. `Flex.textDirection` is local to the flex, it
                        // does not hand a direction down to its children.
                        textDirection: TextDirection.ltr,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.book,
                            color: DashboardColors.accentSoft,
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
                        // On the home page the explorer is pinned open, so the
                        // collapse control is hidden rather than left there
                        // inviting a click that would be undone immediately.
                        if (!isMobile && !isCollapseLocked)
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
                            tooltip: 'إغلاق',
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
                            DashboardColors.surface,
                            DashboardColors.background,
                          ], // slate-800 to slate-900
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: DashboardColors.border,
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
                              color: DashboardColors.subtitle, // slate-400
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
                                DashboardColors.accentSoft,
                              ),
                              Container(
                                width: 1,
                                height: 30,
                                color: DashboardColors.border,
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
                                color: DashboardColors.border,
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

                    // Explorer tabs — the university library and the local
                    // folders. One row of two words instead of two stacked
                    // sections, so only the selected list is on screen.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _buildExplorerTab(
                              label: 'المكتبة الجامعية',
                              isSelected: _tab == _ExplorerTab.university,
                              selectedColor: selectedTabColor,
                              mutedColor: textMuted,
                              onTap: () => setState(() {
                                // Leaving the local tab hides its input, and a
                                // focused offstage field keeps the mobile
                                // keyboard open over a list that no longer
                                // shows it.
                                FocusManager.instance.primaryFocus?.unfocus();
                                _tab = _ExplorerTab.university;
                              }),
                            ),
                            const SizedBox(width: 18),
                            _buildExplorerTab(
                              label: 'الملفات المحلية',
                              isSelected: _tab == _ExplorerTab.local,
                              selectedColor: selectedTabColor,
                              mutedColor: textMuted,
                              onTap: () =>
                                  setState(() => _tab = _ExplorerTab.local),
                            ),
                          ],
                        ),
                        // Adding a folder is a local-files action, so the
                        // button only appears on the local tab.
                        if (_tab == _ExplorerTab.local)
                          IconButton(
                            onPressed: () => setState(() => _isAdding = true),
                            icon: const Icon(
                              LucideIcons.plus,
                              size: 16,
                              color: DashboardColors.subtitle,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'إضافة ملف محلي',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Visibility(
                      visible: _tab == _ExplorerTab.university,
                      maintainState: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CollegeCollectionWidget(
                            // The collection is a pane of the always-dark
                            // sidebar, so it is dark in both themes too.
                            isDarkMode: true,
                            panelBg: sidebarBg,
                            panelBorder: separatorColor,
                            surfaceAlt: DashboardColors.surface,
                            textPrimary: textPrimary,
                            textMuted: textMuted,
                            folderStyle: true,
                          ),

                          // The collection above is the shortcut list; this is
                          // the same library as its own page. It used to live on
                          // the dashboard as a card, and moved here when the
                          // dashboard was redesigned around the header and the
                          // services row.
                          if (app.currentUser != null) ...[
                            const SizedBox(height: 8),
                            _buildOpenLibraryButton(context, app),
                          ],
                        ],
                      ),
                    ),

                    Visibility(
                      visible: _tab == _ExplorerTab.local,
                      maintainState: true,
                      child: Column(
                        children: [
                          // Add Class Input
                          if (_isAdding)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Builder(
                                      builder: (ctx) {
                                        final inputBg = DashboardColors.surface;
                                        final inputText = DashboardColors.title;
                                        return TextField(
                                          controller: _classController,
                                          autofocus: true,
                                          style: TextStyle(
                                            color: inputText,
                                            fontSize: 14,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'اسم القسم...',
                                            hintStyle: const TextStyle(
                                              color: DashboardColors.subtitle,
                                            ),
                                            filled: true,
                                            fillColor: inputBg,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
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
                                    tooltip: 'حفظ المجلد',
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
                                    tooltip: 'إلغاء',
                                  ),
                                ],
                              ),
                            ),

                          // Local class list (custom drag/drop for folders)
                          for (final entry in classes.asMap().entries)
                            _buildClassItem(
                              context,
                              entry.value,
                              app,
                              entry.key,
                            ),

                          // The local tree had no empty state while it sat under
                          // the library; as a tab it needs one, or an empty list
                          // reads as a broken panel.
                          if (classes.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'لا توجد أقسام بعد',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
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
                            color: DashboardColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: separatorColor),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.info,
                                  size: 16,
                                  color: DashboardColors.accentSoft,
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
                            color: DashboardColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: separatorColor),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.settings,
                                  size: 16,
                                  color: DashboardColors.accentSoft,
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
    final textMuted = DashboardColors.subtitle;
    final textPrimary = DashboardColors.title;
    final hoverBg = DashboardColors.hover;

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
                            ? DashboardColors.surface
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
                              ? DashboardColors.accentSoft
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
                            color: DashboardColors.surface.withOpacity(0.9),
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
                                color: DashboardColors.subtitle,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  cls.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: DashboardColors.title,
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
                  left: BorderSide(color: DashboardColors.divider, width: 2),
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
        // A local file has no announcements page to come back to, so the
        // university folder the main area was showing is released here and the
        // viewer stays exactly what it is today. This is the only place that
        // clears it on the local side: opening a local *folder* deliberately
        // leaves the announcements alone, because the requirement is that the
        // local tree never changes what the main area shows.
        app.closeFolderAnnouncements();
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
              ? DashboardColors.hover.withOpacity(0.3)
              : (isSecondary
                    ? DashboardColors.subtitle.withOpacity(0.15)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
          border: isSecondary
              ? Border.all(
                  color: DashboardColors.subtitle.withOpacity(0.2),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.fileText,
              size: 14,
              color: isActive
                  ? DashboardColors.selectedText
                  : (isSecondary
                        ? DashboardColors.secondaryText
                        : DashboardColors.subtitle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pdf.name,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive
                      ? DashboardColors.selectedText
                      : (isSecondary
                            ? DashboardColors.secondaryText
                            : DashboardColors.subtitle),
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
            color: isHovering ? DashboardColors.hoverWash : Colors.transparent,
            border: isHovering
                ? Border.all(color: DashboardColors.accent, width: 1)
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
                color: DashboardColors.surface.withOpacity(0.9),
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
                    color: DashboardColors.subtitle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pdf.name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: DashboardColors.title,
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
          style: const TextStyle(fontSize: 10, color: DashboardColors.subtitle),
        ),
      ],
    );
  }

  /// One word of the explorer's tab row.
  ///
  /// Both words share font and size, which leaves colour as the only thing
  /// telling the selected tab from the other one, so the caller passes both
  /// colours in (they depend on the theme, which this method has no access to).
  Widget _buildExplorerTab({
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required Color mutedColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? selectedColor : mutedColor,
          ),
        ),
      ),
    );
  }

  /// Opens the full cloud library as its own page, the way the dashboard's
  /// library card used to. Guarded on a signed-in user because the library is
  /// keyed by `user.universityId`.
  Widget _buildOpenLibraryButton(BuildContext context, AppProvider app) {
    final isDarkMode = app.isDarkMode;
    final user = app.currentUser!;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: const Text('المكتبة الجامعية'),
                  backgroundColor: isDarkMode
                      ? DashboardColors.background
                      : Colors.white,
                ),
                body: UniversityCloudLibraryWidget(
                  isDarkMode: isDarkMode,
                  user: user,
                ),
              ),
            ),
          );
        },
        icon: const Icon(LucideIcons.library, size: 16),
        label: const Text('فتح المكتبة', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: DashboardColors.accentSoft,
          side: const BorderSide(color: DashboardColors.border),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
