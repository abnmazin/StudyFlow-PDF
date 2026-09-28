import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../dialogs/images_to_pdf_dialog.dart';
import '../dialogs/merge_pdf_dialog.dart';
import 'dashboard_palette.dart';

/// "الخدمات" — the five one-tap actions, in the order the dashboard header
/// presents them: the filled first card is the action the app exists for.
///
/// The handlers are the dashboard's existing ones, unchanged: upload targets the
/// active folder (falling back to the first one), and it refuses with a message
/// when there is no folder to upload into yet.
class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({super.key});

  static const List<_Service> _services = [
    _Service('رفع PDF', LucideIcons.upload, _ServiceKind.upload),
    _Service('دمج ملفات', LucideIcons.combine, _ServiceKind.merge),
    _Service('صور إلى PDF', LucideIcons.image, _ServiceKind.imagesToPdf),
    _Service('مجلد جديد', LucideIcons.folderPlus, _ServiceKind.newFolder),
    _Service('ترجمة الملفات', LucideIcons.languages, _ServiceKind.disabled),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 1180 => 5,
          >= 820 => 3,
          _ => 2,
        };
        const gap = 12.0;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        // Rows are built by hand rather than with `Wrap`, for two reasons. The
        // design wants the five cards on one line sharing one height, and `Wrap`
        // gives each run its own height with no way to equalise it. And a
        // two-line label must not make one card taller than its neighbours —
        // `IntrinsicHeight` is what reads the row's tallest card and hands the
        // same number to all of them.
        final rows = <List<_Service>>[];
        for (var i = 0; i < _services.length; i += columns) {
          rows.add(
            _services.sublist(i, (i + columns).clamp(0, _services.length)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The other two sections carry an 18px bold heading and this one did
            // not, which read as the tiles being a header rather than a section.
            const DashboardSectionTitle('الخدمات'),
            const SizedBox(height: 20),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Fixed widths, not `Expanded`: a short final row must keep
                    // its tiles the same size as a full one rather than
                    // stretching three tiles across five slots of space. The
                    // trailing `Expanded` takes the leftover, and being last it
                    // never affects the tiles.
                    for (var j = 0; j < rows[i].length; j++) ...[
                      if (j > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: tileWidth,
                        child: _ServiceTile(service: rows[i][j]),
                      ),
                    ],
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

enum _ServiceKind { upload, merge, imagesToPdf, newFolder, disabled }

class _Service {
  const _Service(this.label, this.icon, this.kind);

  final String label;
  final IconData icon;
  final _ServiceKind kind;
}

class _ServiceTile extends StatefulWidget {
  const _ServiceTile({required this.service});

  final _Service service;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  // Hover is tracked here rather than left to `InkWell`, because the tile's
  // border and fill live in a `Container` and `InkWell` only paints its own
  // splash. The state is the only thing that can change them.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final isPrimary = service.kind == _ServiceKind.upload;
    final isDisabled = service.kind == _ServiceKind.disabled;

    return MouseRegion(
      // Keyed by label so the tiles are addressable in a test: `MouseRegion` is
      // what a pointer target looks like from the outside, and there are eleven
      // of them in this subtree once `Scaffold` and `InkWell` have added theirs.
      key: ValueKey('service-tile-${service.label}'),
      // A disabled action still gets the pointer, so it can explain itself by
      // looking inert rather than by doing nothing at all.
      cursor: isDisabled
          ? SystemMouseCursors.basic
          : _hovered
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: isDisabled ? null : () => _run(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          // The brief's minimum, not a fixed height: a 14px label and a 24px icon
          // are 72px of content, so a fixed 100 would only add dead space. The
          // floor is what keeps the five cards equal.
          constraints: const BoxConstraints(minHeight: 100),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _fillFor(isPrimary: isPrimary, disabled: isDisabled),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _borderFor(
                isPrimary: isPrimary,
                disabled: isDisabled,
                hovered: _hovered,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                service.icon,
                size: 24,
                color: isPrimary
                    ? Colors.white
                    : isDisabled
                    ? DashboardColors.subtitle.withValues(alpha: 0.45)
                    : DashboardColors.title,
              ),
              const SizedBox(height: 12),
              Text(
                // "قريباً" is part of the label rather than a second line, so the
                // five cards stay one row tall and the reason is not missed.
                isDisabled ? '${service.label} (قريباً)' : service.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isPrimary
                      ? Colors.white
                      : isDisabled
                      ? DashboardColors.subtitle.withValues(alpha: 0.45)
                      : DashboardColors.title,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The fill for the current state. The primary tile is blue by definition and
  /// never changes; a disabled tile must not react to the pointer, or hovering
  /// something unavailable would look like it is available.
  Color _fillFor({required bool isPrimary, required bool disabled}) {
    if (isPrimary) return DashboardColors.accent;
    if (disabled) return DashboardColors.surface;
    return _hovered ? DashboardColors.hover : DashboardColors.surface;
  }

  Color _borderFor({
    required bool isPrimary,
    required bool disabled,
    required bool hovered,
  }) {
    if (isPrimary) return DashboardColors.accent;
    if (disabled) return DashboardColors.border;
    return hovered ? DashboardColors.accent : DashboardColors.border;
  }

  void _run(BuildContext context) {
    final app = context.read<AppProvider>();
    switch (widget.service.kind) {
      case _ServiceKind.upload:
        final classId =
            app.activeClassId ??
            (app.classes.isNotEmpty ? app.classes.first.id : null);
        if (classId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى إنشاء مجلد أولاً لرفع الملف إليه.'),
            ),
          );
          return;
        }
        app.uploadPdf(classId);
      case _ServiceKind.merge:
        showDialog(context: context, builder: (_) => const MergePdfDialog());
      case _ServiceKind.imagesToPdf:
        showDialog(context: context, builder: (_) => const ImagesToPdfDialog());
      case _ServiceKind.newFolder:
        _showCreateFolderDialog(context);
      case _ServiceKind.disabled:
        break;
    }
  }
}

void _showCreateFolderDialog(BuildContext context) {
  final controller = TextEditingController();
  final app = context.read<AppProvider>();

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DashboardColors.surface,
      title: const Text(
        'إنشاء مجلد جديد',
        style: TextStyle(color: DashboardColors.title, fontSize: 18),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: DashboardColors.title),
        decoration: const InputDecoration(hintText: 'اسم المجلد...'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              await app.addClass(name);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('إنشاء'),
        ),
      ],
    ),
  );
}
