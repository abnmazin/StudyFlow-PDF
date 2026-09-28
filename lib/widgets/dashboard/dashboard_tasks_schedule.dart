import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/isar_models.dart';
import '../../models/lecture_slot.dart';
import '../../providers/app_state.dart';
import 'dashboard_palette.dart';
import 'dashboard_schedule_editor.dart';

/// Section C: today's tasks beside the day's schedule, 1:1 with a 32px gap.
///
/// The tasks column is the user's real `StudyTask` list through
/// `AppProvider.tasks`. The schedule column is [LectureSlot] rows built from the
/// shared Firestore timetable: `AppProvider.lectures` supplies the day's rows, and
/// the admin's way into writing the table is `ScheduleAdminButton`, which hangs off
/// this card's heading.
///
/// The columns are equalised with `IntrinsicHeight` rather than
/// `CrossAxisAlignment.stretch`. Stretch would be cheaper, but it needs a bounded
/// height to hand its children, and this row lives in a sliver, which is
/// unbounded vertically by definition: `stretch` there fails the pump with
/// `BoxConstraints forces an infinite height`. `IntrinsicHeight` measures the
/// children instead of asking the parent for a size, which is the only option
/// that works in a scrollable.
class DashboardTasksAndSchedule extends StatelessWidget {
  const DashboardTasksAndSchedule({super.key, required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (!isWide) {
      // Stacked, the cards size to their own content, so nothing to equalise.
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [TodayTasksCard(), SizedBox(height: 32), ScheduleCard()],
      );
    }

    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: TodayTasksCard()),
          SizedBox(width: 32),
          Expanded(child: ScheduleCard()),
        ],
      ),
    );
  }
}

/// The user's task list, with the add-task dialog.
class TodayTasksCard extends StatelessWidget {
  const TodayTasksCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: DashboardColors.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DashboardSectionTitle(
            'مهام اليوم',
            trailing: IconButton(
              onPressed: () => _showTaskDialog(context),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              color: DashboardColors.accent,
              tooltip: 'إضافة مهمة',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(height: 12),
          const _TaskList(),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final tasks = app.tasks;

        if (tasks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(Icons.checklist, size: 32, color: DashboardColors.border),
                SizedBox(height: 12),
                Text(
                  'لا توجد مهام حالياً',
                  style: TextStyle(
                    fontSize: 13,
                    color: DashboardColors.subtitle,
                  ),
                ),
              ],
            ),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final task in tasks) _TaskRow(task: task)],
          ),
        );
      },
    );
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({required this.task});

  final StudyTask task;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  static const String _tapGroup = 'dashboard-task-menu';

  /// The brief's menu: 128 wide, 8px radius, below the icon it belongs to.
  static const double _menuWidth = 128;

  final GlobalKey _menuButtonKey = GlobalKey();
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  StudyTask get _task => widget.task;

  void _toggleMenu() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isDone = _task.isDone;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // The brief's 20×20 circle. `Checkbox` cannot hold 20px: its own
          // minimum tap target is 48px and it paints its own ink, so shrinking it
          // leaves a shape the design does not describe.
          _TaskCheckbox(
            value: isDone,
            onChanged: () => app.toggleTask(_task.uuid),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _task.title,
              style: TextStyle(
                fontSize: 13,
                color: isDone
                    ? DashboardColors.subtitle
                    : DashboardColors.title,
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          CompositedTransformTarget(
            link: _link,
            child: TapRegion(
              groupId: _tapGroup,
              onTapOutside: (_) => _portal.hide(),
              child: IconButton(
                key: _menuButtonKey,
                icon: const Icon(Icons.more_horiz, size: 18),
                onPressed: _toggleMenu,
                color: DashboardColors.subtitle,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'خيارات المهمة',
              ),
            ),
          ),
          _TaskMenu(
            controller: _portal,
            link: _link,
            anchorKey: _menuButtonKey,
            tapGroup: _tapGroup,
            onEdit: () => _showTaskDialog(context, task: _task),
            onDelete: () => app.deleteTask(_task.uuid),
          ),
        ],
      ),
    );
  }
}

class _TaskCheckbox extends StatelessWidget {
  const _TaskCheckbox({required this.value, required this.onChanged});

  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      label: 'إنجاز المهمة',
      child: InkWell(
        onTap: onChanged,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 20,
          height: 20,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? DashboardColors.accent : Colors.transparent,
              border: Border.all(
                color: value ? DashboardColors.accent : DashboardColors.border,
                width: 1.5,
              ),
            ),
            child: value
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

/// The 3-dots popup, following its button.
class _TaskMenu extends StatelessWidget {
  const _TaskMenu({
    required this.controller,
    required this.link,
    required this.anchorKey,
    required this.tapGroup,
    required this.onEdit,
    required this.onDelete,
  });

  final OverlayPortalController controller;
  final LayerLink link;
  final GlobalKey anchorKey;
  final String tapGroup;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: controller,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        // Physical anchors, because `CompositedTransformFollower` takes
        // physical `Alignment`. Matching the same edge on both sides keeps the
        // menu on the button's own side of the window.
        targetAnchor: Alignment.topRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 4),
        // The Overlay hands every entry tight screen constraints and the follower
        // passes them through, so a `maxWidth` below is inert without this. The
        // `Align`'s empty half is not hit-tested, so a tap outside still reaches
        // the button's `TapRegion`.
        child: Align(
          alignment: Alignment.topRight,
          child: TapRegion(
            groupId: tapGroup,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _TaskRowState._menuWidth),
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: DashboardColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DashboardColors.border),
                    boxShadow: DashboardColors.panelShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MenuItem(
                          icon: Icons.edit_outlined,
                          label: 'تعديل',
                          onTap: onEdit,
                        ),
                        Container(height: 1, color: DashboardColors.divider),
                        _MenuItem(
                          icon: Icons.delete_outline,
                          label: 'حذف',
                          color: const Color(0xFFEF4444),
                          onTap: onDelete,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // Nothing to place: the follower's child carries the size, and the portal
      // only needs a widget in the page tree to own the controller.
      child: const SizedBox.shrink(),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = DashboardColors.title,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: _TaskRowState._menuWidth,
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Tomorrow's lectures.
///
/// One day, and the day itself is picked in `AppProvider.lectures` — the card
/// only draws what it is handed, so it cannot drift from the admin's list about
/// which entries are tomorrow's.
class ScheduleCard extends StatelessWidget {
  const ScheduleCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final lectures = app.lectures;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: DashboardColors.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DashboardSectionTitle(
            'الجدول',
            // The admin's `+`. Renders as nothing at all for a student, so the
            // card reads identically for both roles.
            trailing: ScheduleAdminButton(),
          ),
          const SizedBox(height: 16),
          // A failed read replaces the day rather than sitting beside it: the
          // heading below would be a claim about a table nobody managed to read.
          if (app.isTimetableFailed)
            const _ScheduleUnavailableRow()
          else ...[
            _DayHeading(label: 'غداً', hasLectures: lectures.isNotEmpty),
            const SizedBox(height: 10),
            if (lectures.isEmpty)
              const _EmptyScheduleRow()
            else
              for (final lecture in lectures) LectureRow(lecture: lecture),
          ],
        ],
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.label, required this.hasLectures});

  final String label;
  final bool hasLectures;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The brief's 8px glowing dot, next to a day that has something in it.
        if (hasLectures)
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: DashboardColors.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x662563EB),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          )
        else
          const SizedBox(width: 8),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DashboardColors.title,
          ),
        ),
      ],
    );
  }
}

class _EmptyScheduleRow extends StatelessWidget {
  const _EmptyScheduleRow();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'لا توجد محاضرات',
      style: TextStyle(fontSize: 13, color: DashboardColors.subtitle),
    );
  }
}

/// What the card says when the table could not be read at all.
///
/// Deliberately a different sentence from `_EmptyScheduleRow`. "لا توجد محاضرات"
/// is a claim about the timetable, and this is a confession about the app: draw
/// the first when the second is true and a reader is told their week is free when
/// it may be full. The distinction lives in `AppProvider.isTimetableFailed`.
class _ScheduleUnavailableRow extends StatelessWidget {
  const _ScheduleUnavailableRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.cloud_off, size: 16, color: DashboardColors.subtitle),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'تعذّر تحميل الجدول',
            style: TextStyle(fontSize: 13, color: DashboardColors.subtitle),
          ),
        ),
      ],
    );
  }
}

/// One lecture: the name on the reading edge, the time opposite it on the same
/// baseline.
///
/// `CrossAxisAlignment.baseline` is the brief's hard constraint and it is what
/// makes the pair work for a title of any length: the time is the smaller of the
/// two sizes, so centre alignment would drift as the title wraps, while a
/// baseline pins them to one line of text. A `Row` reports the highest of its
/// children's baselines, which is what keeps the smaller label on the title's
/// line rather than near it.
///
/// The time is bare text. It used to be a bordered chip that carried the room as
/// well; with the room dropped from the row, a box around a single label reads as
/// a button, and the row is not one. `Flexible` and `IntrinsicWidth` went with
/// the chip — both existed only because the chip was unbreakable, and a
/// fixed-width time label has nothing to shrink.
///
/// `Expanded` on the title is the other half of it: without it a long title
/// claims the row's full width and pushes the time off the card.
class LectureRow extends StatelessWidget {
  const LectureRow({super.key, required this.lecture});

  final LectureSlot lecture;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        key: const ValueKey('lecture-row'),
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              lecture.title,
              style: const TextStyle(
                fontSize: 14,
                color: DashboardColors.title,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // Keyed because the tests are about *this* box: the row's rule is that
          // it shares the title's baseline, and finding it by its text would tie
          // those tests to one fixture's clock.
          Text(
            lecture.time,
            key: const ValueKey('lecture-time'),
            style: const TextStyle(
              fontSize: 12,
              color: DashboardColors.subtitle,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// Add a task, or rename an existing one.
///
/// One dialog for both, because they differ by a single field and a pre-filled
/// title: two dialogs would be two copies of the same form.
void _showTaskDialog(BuildContext context, {StudyTask? task}) {
  final controller = TextEditingController(text: task?.title ?? '');
  final isEdit = task != null;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: DashboardColors.surface,
      title: Text(
        isEdit ? 'تعديل المهمة' : 'إضافة مهمة جديدة',
        style: const TextStyle(color: DashboardColors.title, fontSize: 18),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: DashboardColors.title),
        decoration: const InputDecoration(hintText: 'ماذا تريد أن تفعل؟'),
        onSubmitted: (value) {
          if (value.trim().isEmpty) return;
          final app = dialogContext.read<AppProvider>();
          if (isEdit) {
            app.updateTask(task.uuid, value.trim());
          } else {
            app.addTask(value.trim());
          }
          Navigator.pop(dialogContext);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            if (controller.text.trim().isEmpty) return;
            final app = dialogContext.read<AppProvider>();
            if (isEdit) {
              app.updateTask(task.uuid, controller.text.trim());
            } else {
              app.addTask(controller.text.trim());
            }
            Navigator.pop(dialogContext);
          },
          child: Text(isEdit ? 'حفظ' : 'إضافة'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
