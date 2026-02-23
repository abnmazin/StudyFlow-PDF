import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/app_state.dart';
import '../models/models.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  bool _isAdding = false;
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
        title: const Text('Delete Class?'),
        content: const Text(
          'Are you sure you want to delete this class and all its PDFs?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              app.deleteClass(classId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
        title: const Text('Delete PDF?'),
        content: Text('Are you sure you want to delete "${pdf.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              app.deletePdf(classId, pdf.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isMobile = MediaQuery.of(context).size.width < 768;
    final scheme = Theme.of(context).colorScheme;
    final sidebarBg = app.isDarkMode ? const Color(0xFF0F172A) : scheme.surface;
    final sidebarBorder =
        app.isDarkMode ? const Color(0xFF1E293B) : scheme.outlineVariant;
    final textPrimary = app.isDarkMode ? const Color(0xFFF1F5F9) : scheme.onSurface;
    final textMuted =
        app.isDarkMode ? const Color(0xFF94A3B8) : scheme.onSurfaceVariant;

    return Container(
      width: 288, // w-72
      color: sidebarBg,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: sidebarBorder),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.book,
                      color: Color(0xFF60A5FA),
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'StudyFlow',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (!isMobile)
                      IconButton(
                        onPressed: () => app.toggleSidebar(),
                        icon: Icon(
                          LucideIcons.chevronLeft,
                          color: textMuted,
                        ),
                        tooltip: 'Collapse',
                      ),
                    if (isMobile)
                      IconButton(
                        onPressed: () => app.toggleMobile(),
                        icon: Icon(
                          LucideIcons.x,
                          color: textMuted,
                        ),
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
                        'STUDY OVERVIEW',
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
                            'Files',
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
                            'Highlights',
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
                            'Notes',
                            const Color(0xFFA78BFA),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // "Your Classes" Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'YOUR CLASSES',
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
                              final isDark = context.watch<AppProvider>().isDarkMode;
                              final inputBg = isDark
                                  ? const Color(0xFF1E293B)
                                  : scheme.surfaceContainerHigh;
                              final inputText =
                                  isDark ? Colors.white : scheme.onSurface;
                              return TextField(
                                controller: _classController,
                                autofocus: true,
                                style: TextStyle(
                                  color: inputText,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Name...',
                                  hintStyle: TextStyle(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.5)
                                        : scheme.onSurfaceVariant.withOpacity(0.6),
                                  ),
                                  filled: true,
                                  fillColor: inputBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _handleAddClass(context),
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
                          onPressed: () => setState(() => _isAdding = false),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                      ],
                    ),
                  ),

                // Class List
                ...app.classes.map((cls) => _buildClassItem(context, cls, app)),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: InkWell(
              onTap: () => app.toggleDevInfo(true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(LucideIcons.info, size: 16, color: Color(0xFF60A5FA)),
                    SizedBox(width: 8),
                    Text(
                      'حقوق المطور',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1), // slate-300
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassItem(BuildContext context, ClassItem cls, AppProvider app) {
    final isActive = app.activeClassId == cls.id;
    final scheme = Theme.of(context).colorScheme;
    final textMuted =
        app.isDarkMode ? const Color(0xFF94A3B8) : scheme.onSurfaceVariant;
    final textPrimary = app.isDarkMode ? const Color(0xFFF1F5F9) : scheme.onSurface;
    final hoverBg = app.isDarkMode ? const Color(0xFF1E3A8A) : scheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Class Header + DragTarget
        DragTarget<Map<String, String>>(
          onWillAccept: (data) =>
              data != null && data['sourceClassId'] != cls.id,
          onAccept: (data) {
            if (data['pdfId'] != null && data['sourceClassId'] != null) {
              app.movePdf(data['pdfId']!, data['sourceClassId']!, cls.id);
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
                            ? (app.isDarkMode ? const Color(0xFF1E293B) : scheme.surfaceContainerHigh)
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
                        tooltip: 'Upload PDF',
                        onPressed: () => app.uploadPdf(cls.id),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          LucideIcons.trash2,
                          size: 16,
                          color: Color(0xFFF87171),
                        ),
                        tooltip: 'Delete Class',
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

    final child = InkWell(
      onTap: () => app.setActivePdf(pdf.id),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0x4D1E3A8A) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.fileText,
              size: 14,
              color: isActive
                  ? const Color(0xFFBFDBFE)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pdf.name,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive
                      ? const Color(0xFFBFDBFE)
                      : const Color(0xFF94A3B8),
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
                tooltip: 'Delete PDF',
                onPressed: () => _confirmDeletePdf(context, pdf, app, classId),
              ),
            ),
          ],
        ),
      ),
    );

    return Draggable<Map<String, String>>(
      data: {'pdfId': pdf.id, 'sourceClassId': classId},
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
      childWhenDragging: Opacity(opacity: 0.3, child: child),
      child: child,
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
