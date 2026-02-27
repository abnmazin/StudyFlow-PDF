part of 'pdf_viewer_widget_w.dart';

// ─── DASHBOARD ─────────────────────────────────────────────────────────────

Widget _buildDashboard(BuildContext context) {
  final app = context.watch<AppProvider>();
  final isDarkMode = context.select<AppProvider, bool>(
    (app) => app.isDarkMode,
  );

  // Use FutureBuilder for async recent docs
  return Container(
    color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    child: FutureBuilder<List<PdfDocument>>(
      future: context.read<FileManagerService>().getRecentDocuments(limit: 6),
      builder: (context, snapshot) {
        final recentDocs = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeHeader(app),
              const SizedBox(height: 32),
              _buildQuickActionsGrid(context, isDarkMode),
              const SizedBox(height: 48),
              _buildRecentDocumentsSection(recentDocs, isDarkMode),
              const SizedBox(height: 48),
              _buildStatisticsSection(app),
              const SizedBox(height: 48),
              _buildTipsSection(isDarkMode),
            ],
          ),
        );
      },
    ),
  );
}

Widget _buildWelcomeHeader(AppProvider app) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome to StudyFlow',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: app.isDarkMode ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start your smart learning journey with advanced PDF tools',
            style: TextStyle(
              fontSize: 16,
              color: app.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: app.isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.bookOpen,
              size: 20,
              color: Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            Text(
              '${app.totalPdfs} Books • ${app.totalHighlights} Highlights',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: app.isDarkMode
                    ? Colors.white
                    : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildQuickActionsGrid(BuildContext context, bool isDarkMode) {
  final actions = [
    {
      'icon': LucideIcons.upload,
      'label': 'Upload PDF',
      'color': 0xFF3B82F6,
      'action': () {
        // Upload to current active class or default
        final app = context.read<AppProvider>();
        final targetClassId =
            app.activeClassId ??
            (app.classes.isNotEmpty ? app.classes.first.id : '');
        if (targetClassId.isNotEmpty) {
          app.uploadPdf(targetClassId);
        }
      },
    },
    {
      'icon': LucideIcons.combine,
      'label': 'Merge PDFs',
      'color': 0xFF8B5CF6, // Purple
      'action': () => showDialog(
        context: context,
        builder: (context) => const MergePdfDialog(),
      ),
    },
    {
      'icon': LucideIcons.image,
      'label': 'Images to PDF',
      'color': 0xFF10B981, // Green
      'action': () => showDialog(
        context: context,
        builder: (context) => const ImagesToPdfDialog(),
      ),
    },
    {
      'icon': LucideIcons.folderPlus,
      'label': 'New Folder',
      'color': 0xFFF59E0B, // Amber (shifted color)
      'action': () => _showCreateFolderDialog(context),
    },
    {
      'icon': LucideIcons.scanLine,
      'label': 'Scan',
      'color': 0xFFEC4899, // Pink
      'action': () => _showTopSnack(context, 'Scanning coming soon!'),
    },
  ];

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Quick Actions',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
        ),
      ),
      const SizedBox(height: 16),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
        ),
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          final colorVal = action['color'] as int;
          final icon = action['icon'] as IconData;
          final label = action['label'] as String;
          final cb = action['action'] as VoidCallback;

          return InkWell(
            onTap: cb,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(colorVal).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Color(colorVal), size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode
                          ? Colors.grey[300]
                          : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
}

Widget _buildRecentDocumentsSection(
  List<PdfDocument> recentDocs,
  bool isDarkMode,
) {
  if (recentDocs.isEmpty) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode
              ? const Color(0xFF334155)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Icon(
            LucideIcons.fileText,
            size: 48,
            color: isDarkMode ? Colors.grey[600] : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No recently opened books',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start by uploading a new book to study',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Recent Books',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
        ),
      ),
      const SizedBox(height: 16),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.5, // Wider cards
        ),
        itemCount: recentDocs.length,
        itemBuilder: (context, index) {
          final doc = recentDocs[index];
          return _buildDocumentCard(context, doc, isDarkMode);
        },
      ),
    ],
  );
}

Widget _buildDocumentCard(BuildContext context, PdfDocument doc, bool isDarkMode) {
  return InkWell(
    onTap: () {
      // Open PDF via AppProvider
      context.read<AppProvider>().setActivePdf(doc.uuid);
      // Also set active class if tracked
      if (doc.classId != null) {
        context.read<AppProvider>().setActiveClass(doc.classId!);
      }
    },
    borderRadius: BorderRadius.circular(12),
    child: Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode
              ? const Color(0xFF334155)
              : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF334155)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: doc.thumbnailPath != null
                  ? Image.file(File(doc.thumbnailPath!), fit: BoxFit.cover)
                  : Icon(
                      LucideIcons.fileText,
                      size: 24,
                      color: Colors.grey[400],
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  doc.originalPath
                      .split(Platform.pathSeparator)
                      .last, // Name fallback
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? Colors.white
                        : const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      LucideIcons.bookmark,
                      size: 12,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Page ${doc.lastPage}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      LucideIcons.highlighter,
                      size: 12,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${doc.annotationCount}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildStatisticsSection(AppProvider app) {
  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          LucideIcons.bookOpen,
          app.totalPdfs.toString(),
          'Total Books',
        ),
        _buildStatItem(
          LucideIcons.highlighter,
          app.totalHighlights.toString(),
          'Highlights',
        ),
        _buildStatItem(
          LucideIcons.messageSquare,
          app.totalComments.toString(),
          'Comments',
        ),
        _buildStatItem(
          LucideIcons.clock,
          'N/A',
          'Reading Time',
        ), // Placeholder
      ],
    ),
  );
}

Widget _buildStatItem(IconData icon, String value, String label) {
  return Column(
    children: [
      Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 24),
      const SizedBox(height: 8),
      Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withValues(alpha: 0.6),
        ),
      ),
    ],
  );
}

Widget _buildTipsSection(bool isDarkMode) {
  final tips = [
    'Use Ctrl+F for Search',
    'Try LaTeX mode for Math',
    'Double tap text to highlight',
    'Right click to annotate',
  ];

  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFBFDBFE),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.lightbulb,
              color: isDarkMode
                  ? Colors.yellow[700]
                  : const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            Text(
              'Quick Tips',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : const Color(0xFF1E4ED8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: tips.map((tip) {
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tip,
                style: TextStyle(
                  color: isDarkMode
                      ? Colors.grey[300]
                      : const Color(0xFF1E293B),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );
}

void _showCreateFolderDialog(BuildContext context) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New Folder'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'Folder Name'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              context.read<FileManagerService>().createFolder(
                name: controller.text,
              );
              Navigator.pop(ctx);
            }
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

void _showTopSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height - 100,
        left: 20,
        right: 20,
      ),
    ),
  );
}
