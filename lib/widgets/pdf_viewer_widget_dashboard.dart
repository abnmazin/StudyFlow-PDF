part of 'pdf_viewer_widget_w.dart';

// ─── DASHBOARD ─────────────────────────────────────────────────────────────

Widget _buildDashboard(BuildContext context) {
  final app = context.watch<AppProvider>();
  final isDarkMode = context.select<AppProvider, bool>((app) => app.isDarkMode);
  final dashboardBg = isDarkMode
      ? const Color(0xFF0F172A)
      : const Color(0xFFF8FAFC);

  // Use FutureBuilder for async recent docs
  return ColoredBox(
    color: dashboardBg,
    child: SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width < 700
              ? 12.0
              : (width < 1100 ? 20.0 : 32.0);
          final verticalPadding = width < 700 ? 12.0 : 20.0;

          return FutureBuilder<List<List<PdfDocument>>>(
            future: Future.wait([
              context.read<FileManagerService>().getRecentDocuments(limit: 6),
              context.read<FileManagerService>().getAllDocuments(),
            ]),
            builder: (context, snapshot) {
              final recentDocs = snapshot.data != null
                  ? snapshot.data![0]
                  : <PdfDocument>[];
              final allDocs = snapshot.data != null
                  ? snapshot.data![1]
                  : <PdfDocument>[];
              final readingTimeEstimate = _estimateReadingTime(allDocs);

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (verticalPadding * 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeHeader(app),
                      const SizedBox(height: 24),
                      _buildQuickActionsGrid(context, isDarkMode),
                      const SizedBox(height: 32),
                      _buildRecentDocumentsSection(recentDocs, isDarkMode),
                      const SizedBox(height: 32),
                      _buildStatisticsSection(app, readingTimeEstimate),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

Widget _buildWelcomeHeader(AppProvider app) {
  final panelBg = app.isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  final panelBorder = app.isDarkMode
      ? const Color(0xFF334155)
      : const Color(0xFFE2E8F0);

  final statsBadge = Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(
      color: panelBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: panelBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.bookOpen, size: 20, color: Color(0xFF3B82F6)),
        const SizedBox(width: 8),
        Text(
          '${app.totalPdfs} كتاب • ${app.totalHighlights} هايلايت',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: app.isDarkMode ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ],
    ),
  );

  return LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;

      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مرحبًا بك في ستادي فلو',
            style: TextStyle(
              fontSize: compact ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: app.isDarkMode ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ابدأ رحلة تعلّم ذكية باستخدام أدوات PDF المتقدمة',
            style: TextStyle(
              fontSize: compact ? 14 : 16,
              color: app.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );

      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 16), statsBadge],
        );
      }

      return Row(
        children: [
          Expanded(child: titleBlock),
          const SizedBox(width: 16),
          Flexible(child: statsBadge),
        ],
      );
    },
  );
}

Widget _buildQuickActionsGrid(BuildContext context, bool isDarkMode) {
  final cardBg = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  final cardBorder = isDarkMode
      ? const Color(0xFF334155)
      : const Color(0xFFE2E8F0);

  final actions = [
    {
      'icon': LucideIcons.upload,
      'label': 'رفع PDF',
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
      'label': 'دمج ملفات PDF',
      'color': 0xFF8B5CF6, // Purple
      'action': () => showDialog(
        context: context,
        builder: (context) => const MergePdfDialog(),
      ),
    },
    {
      'icon': LucideIcons.image,
      'label': 'تحويل الصور إلى PDF',
      'color': 0xFF10B981, // Green
      'action': () => showDialog(
        context: context,
        builder: (context) => const ImagesToPdfDialog(),
      ),
    },
    {
      'icon': LucideIcons.folderPlus,
      'label': 'مجلد جديد',
      'color': 0xFFF59E0B, // Amber (shifted color)
      'action': () => _showCreateFolderDialog(context),
    },
  ];

  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final crossAxisCount = width >= 1200
          ? 4
          : (width >= 860 ? 3 : (width >= 520 ? 2 : 1));
      final childAspectRatio = crossAxisCount == 1 ? 2.8 : 1.5;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إجراءات سريعة',
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
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: childAspectRatio,
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
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder),
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
                    mainAxisSize: MainAxisSize.min,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

Widget _buildRecentDocumentsSection(
  List<PdfDocument> recentDocs,
  bool isDarkMode,
) {
  final panelBg = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  final panelBorder = isDarkMode
      ? const Color(0xFF334155)
      : const Color(0xFFE2E8F0);

  if (recentDocs.isEmpty) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: panelBorder),
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
            'لا توجد كتب مفتوحة مؤخرًا',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ابدأ برفع كتاب جديد للدراسة',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final crossAxisCount = width >= 1200 ? 3 : (width >= 760 ? 2 : 1);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الكتب الأخيرة',
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
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2.5,
            ),
            itemCount: recentDocs.length,
            itemBuilder: (context, index) {
              final doc = recentDocs[index];
              return _buildDocumentCard(context, doc, isDarkMode);
            },
          ),
        ],
      );
    },
  );
}

Widget _buildDocumentCard(
  BuildContext context,
  PdfDocument doc,
  bool isDarkMode,
) {
  final cardBg = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  final cardBorder = isDarkMode
      ? const Color(0xFF334155)
      : const Color(0xFFE2E8F0);

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
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
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
                    color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
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
                      'الصفحة ${doc.lastPage}',
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

Widget _buildStatisticsSection(AppProvider app, String readingTimeEstimate) {
  final gradient = app.isDarkMode
      ? const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)])
      : const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)]);
  final borderColor = app.isDarkMode
      ? const Color(0xFF334155)
      : const Color(0xFFE2E8F0);

  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final itemWidth = compact
            ? (constraints.maxWidth - 24) / 2
            : (constraints.maxWidth - 36) / 4;

        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 16,
          spacing: 12,
          children: [
            SizedBox(
              width: itemWidth,
              child: _buildStatItem(
                LucideIcons.bookOpen,
                app.totalPdfs.toString(),
                'إجمالي الكتب',
                app.isDarkMode,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildStatItem(
                LucideIcons.highlighter,
                app.totalHighlights.toString(),
                'هايلايت',
                app.isDarkMode,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildStatItem(
                LucideIcons.messageSquare,
                app.totalComments.toString(),
                'تعليقات',
                app.isDarkMode,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildStatItem(
                LucideIcons.clock,
                readingTimeEstimate,
                'وقت القراءة',
                app.isDarkMode,
              ),
            ),
          ],
        );
      },
    ),
  );
}

String _estimateReadingTime(List<PdfDocument> docs) {
  // Fallback estimate: 2 minutes per reached page.
  final totalPagesReached = docs.fold<int>(
    0,
    (sum, d) => sum + (d.lastPage > 0 ? d.lastPage : 0),
  );
  final totalMinutes = totalPagesReached * 2;
  if (totalMinutes <= 0) return '0m';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

Widget _buildStatItem(
  IconData icon,
  String value,
  String label,
  bool isDarkMode,
) {
  final iconColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.8)
      : const Color(0xFF334155);
  final valueColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
  final labelColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.6)
      : const Color(0xFF64748B);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: iconColor, size: 24),
      const SizedBox(height: 8),
      Text(
        value,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: valueColor,
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
    ],
  );
}

Widget _buildTipsSection(bool isDarkMode) {
  final tips = [
    'استخدم Ctrl+F للبحث',
    'جرّب وضع LaTeX للمعادلات',
    'انقر مرتين على النص لعمل هايلايت',
    'انقر بالزر الأيمن لإضافة تعليق',
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
              color: isDarkMode ? Colors.yellow[700] : const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            Text(
              'نصائح سريعة',
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      title: const Text('مجلد جديد'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'اسم المجلد'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('إلغاء'),
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
          child: const Text('إنشاء'),
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
