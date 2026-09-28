import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/timetable_entry.dart';
import '../../providers/app_state.dart';
import 'dashboard_palette.dart';

/// The admin's way into the timetable: a `+` in the schedule card's heading.
///
/// Built only for an admin, and built as *nothing* for everyone else rather than
/// as a disabled button. The schedule is shown to every student, and a greyed-out
/// `+` on each of their cards would advertise a control they cannot have and
/// cannot ask about. `SizedBox.shrink()` is what `DashboardSectionTitle` already
/// expects of an absent `trailing`.
///
/// Watches rather than reads the provider: the role arrives with the profile,
/// which is loaded after the first frame, so a `read` here would decide once —
/// while the user is still unknown — and never reconsider.
class ScheduleAdminButton extends StatelessWidget {
  const ScheduleAdminButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AppProvider>().currentUser?.isAdmin ?? false;
    if (!isAdmin) return const SizedBox.shrink();

    return IconButton(
      onPressed: () => showScheduleManager(context),
      icon: const Icon(Icons.add_circle_outline, size: 18),
      color: DashboardColors.accent,
      tooltip: 'إدارة الجدول',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}

/// Opens the timetable manager.
///
/// A function rather than a callback baked into the button, so a second entry
/// point (a menu item, a shortcut) can open the same dialog without the button.
Future<void> showScheduleManager(BuildContext context) {
  // Opening the dialog is the moment its spinner starts counting, so this is the
  // cheapest place to notice a subscription nobody opened. After the fix that
  // shares the session handover between the two auth paths this is normally
  // already live and the call does nothing — which is the point of checking
  // rather than starting a second stream on top of a working one.
  context.read<AppProvider>().ensureTimetableWatched();
  return showDialog<void>(
    context: context,
    builder: (_) => const ScheduleManagerDialog(),
  );
}

/// Every lecture in the shared table, grouped by weekday, with edit and delete.
///
/// Reads `AppProvider.timetableEntries`, which is the *whole* week, and not
/// `AppProvider.lectures`, which is today and tomorrow only because that is all
/// the schedule card draws. An admin who could see nothing but today could not
/// fix Wednesday, which is the entire reason this dialog exists.
class ScheduleManagerDialog extends StatelessWidget {
  const ScheduleManagerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DashboardColors.surface,
      title: const Text(
        'إدارة الجدول',
        style: TextStyle(color: DashboardColors.title, fontSize: 18),
      ),
      content: SizedBox(
        width: 520,
        // An `AlertDialog` does not scroll its own content, and a full week runs
        // past the bottom of a laptop screen: without a cap here the later days
        // are simply unreachable.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Consumer<AppProvider>(
            builder: (context, app, _) {
              // The same distinction the card makes: an empty table and a table
              // nobody has asked about yet are different answers, and drawing the
              // empty state during the first round trip would flash a wrong one.
              if (!app.isTimetableLoaded) {
                // A read that fails never reaches `isTimetableLoaded`, so without
                // the branch below the spinner is what the admin sees for ever:
                // rules not yet deployed, a dead network, and a stream nobody
                // opened all end identically — silently, and wearing the same
                // face as a first snapshot that is simply still in flight.
                if (app.isTimetableFailed) {
                  return const _TimetableUnavailableRow();
                }
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final entries = app.timetableEntries;
              if (entries.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_note,
                        size: 32,
                        color: DashboardColors.border,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'لا توجد محاضرات بعد',
                        style: TextStyle(
                          fontSize: 13,
                          color: DashboardColors.subtitle,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final weekday in _daysWithEntries(entries))
                      _WeekdayGroup(
                        weekday: weekday,
                        entries: entries
                            .where((entry) => entry.weekday == weekday)
                            .toList(),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
        ElevatedButton.icon(
          onPressed: () => showScheduleEntryDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('إضافة محاضرة'),
        ),
      ],
    );
  }

  /// The days that carry something, in `DateTime` order.
  ///
  /// Only those, because this list is a report of what exists: seven headings,
  /// six of them empty, is noise around one real day. All seven days are offered
  /// in the *form* instead, which is the place a day is arrived at rather than
  /// looked up.
  static List<int> _daysWithEntries(List<TimetableEntry> entries) {
    return entries.map((entry) => entry.weekday).toSet().toList()..sort();
  }
}

/// Why the manager has nothing to list, and the one action that can change that.
///
/// The card draws the same sentence (`_ScheduleUnavailableRow`) with no button,
/// because a student cannot fix a denied read and a control they cannot use is
/// an advertisement for one they cannot have. Here the reader is the admin, the
/// failure is usually the rules not being deployed yet, and re-subscribing is
/// the entire fix — so the retry belongs to this dialog and not to the card.
class _TimetableUnavailableRow extends StatelessWidget {
  const _TimetableUnavailableRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 32, color: DashboardColors.border),
          const SizedBox(height: 12),
          const Text(
            'تعذّر تحميل الجدول',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: DashboardColors.subtitle),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            // Resubscribes rather than re-reading: the failure lives in the
            // subscription, which `initTimetable` also clears, so the next frame
            // honestly says "asking again" instead of showing this row forever.
            onPressed: () => context.read<AppProvider>().initTimetable(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

/// One day's heading, its lecture count, and its lectures.
class _WeekdayGroup extends StatelessWidget {
  const _WeekdayGroup({required this.weekday, required this.entries});

  final int weekday;
  final List<TimetableEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                TimetableEntry.weekdayLabel(weekday),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DashboardColors.title,
                ),
              ),
              const SizedBox(width: 8),
              // The count, because "is my week full" is the first thing an admin
              // checks, and counting rows by eye is the part a dialog should do.
              Text(
                '${entries.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: DashboardColors.subtitle,
                ),
              ),
            ],
          ),
        ),
        for (final entry in entries) _EntryRow(entry: entry),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// One lecture in the manager: what it is, and the two controls on it.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final TimetableEntry entry;

  /// Deletes after a confirmation, because the write is shared.
  ///
  /// The confirmation is not ceremony: this row belongs to every user's
  /// dashboard at once, and there is no undo. Naming the lecture in the question
  /// is what makes it a check rather than a reflex — the reader has to recognise
  /// what they are about to remove.
  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: DashboardColors.surface,
        title: const Text(
          'حذف المحاضرة',
          style: TextStyle(color: DashboardColors.title, fontSize: 18),
        ),
        content: Text(
          'سيتم حذف «${entry.title}» من الجدول لكل المستخدمين. هل أنت متأكد؟',
          style: const TextStyle(color: DashboardColors.subtitle, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف', style: TextStyle(color: _danger)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    // Captured before the await: the messenger outlives this row's context, and
    // reading it afterwards is the case `use_build_context_synchronously` warns
    // about — the row can be gone by the time the stream reports the delete back.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppProvider>().deleteTimetableEntry(entry.id);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ تم حذف المحاضرة'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DashboardColors.hover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DashboardColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: DashboardColors.title,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Time and room on one line, the way the card reads them, and the
                // time always shown: a roomless lecture still has a time, while a
                // timeless one is not a lecture.
                Text(
                  entry.room.isEmpty
                      ? entry.timeLabel
                      : '${entry.timeLabel} · ${entry.room}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DashboardColors.subtitle,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => showScheduleEntryDialog(context, entry: entry),
            icon: const Icon(Icons.edit_outlined, size: 17),
            color: DashboardColors.subtitle,
            tooltip: 'تعديل',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline, size: 17),
            color: _danger,
            tooltip: 'حذف',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Destructive red, the same value the task menu uses for its delete item.
const Color _danger = Color(0xFFEF4444);

/// Adds a lecture, or edits an existing one.
///
/// One dialog for both, following the task dialog's reasoning: they differ by
/// pre-filled fields and a heading, and two dialogs would be two copies of one
/// form to keep in step.
Future<void> showScheduleEntryDialog(
  BuildContext context, {
  TimetableEntry? entry,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ScheduleEntryDialog(entry: entry),
  );
}

class _ScheduleEntryDialog extends StatefulWidget {
  const _ScheduleEntryDialog({this.entry});

  /// Null when adding. Non-null when editing, which is also what carries the id
  /// `saveEntry` uses to decide between `add` and `set`.
  final TimetableEntry? entry;

  @override
  State<_ScheduleEntryDialog> createState() => _ScheduleEntryDialogState();
}

class _ScheduleEntryDialogState extends State<_ScheduleEntryDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _roomCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  late int _weekday;
  String? _error;
  bool _isSaving = false;

  TimetableEntry? get _entry => widget.entry;
  bool get _isEdit => _entry != null;

  @override
  void initState() {
    super.initState();
    final entry = _entry;
    _titleCtrl = TextEditingController(text: entry?.title ?? '');
    _roomCtrl = TextEditingController(text: entry?.room ?? '');
    // The stored ints are rendered through the model's own formatter, so what the
    // admin edits is exactly the time the card shows — there is no second spelling
    // of `08:30` that could disagree with the first.
    _startCtrl = TextEditingController(
      text: entry == null
          ? ''
          : TimetableEntry.formatMinutes(entry.startMinutes),
    );
    _endCtrl = TextEditingController(
      text: entry == null ? '' : TimetableEntry.formatMinutes(entry.endMinutes),
    );
    // Monday when adding: it is the first day of the `DateTime` week, and leaving
    // the day unset would block the save on a field the admin never saw.
    _weekday = entry?.weekday ?? DateTime.monday;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _roomCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Checked on its own before the model's rule, because a field that does not
    // parse is not a null the rule can describe: `validationMessage` speaks about
    // an end being before a start, and it has no sentence for "that is not a time".
    // Returning here is also what promotes both locals to `int` for the rest of the
    // method — a conditional expression would only do that inside its own branch.
    final start = TimetableEntry.parseTime(_startCtrl.text);
    final end = TimetableEntry.parseTime(_endCtrl.text);
    if (start == null || end == null) {
      setState(() => _error = 'أدخل الوقت بصيغة مثل 08:30');
      return;
    }

    // Everything the two parsed times *can* be checked against goes through the
    // model's rule, so the admin reads the sentence the service would have thrown
    // rather than a second wording invented in this form.
    final invalid = TimetableEntry.validationMessage(
      title: _titleCtrl.text,
      startMinutes: start,
      endMinutes: end,
    );
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    final entry = TimetableEntry(
      id: _entry?.id ?? '',
      title: _titleCtrl.text.trim(),
      room: _roomCtrl.text.trim(),
      weekday: _weekday,
      startMinutes: start,
      endMinutes: end,
      updatedBy: _entry?.updatedBy ?? '',
    );

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await context.read<AppProvider>().saveTimetableEntry(entry);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      // Reported inside the dialog rather than as a snackbar behind it: a rejected
      // write is the moment the admin needs the reason, with the fields still in
      // front of them to correct.
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = '❌ $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DashboardColors.surface,
      title: Text(
        _isEdit ? 'تعديل المحاضرة' : 'إضافة محاضرة',
        style: const TextStyle(color: DashboardColors.title, fontSize: 18),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                controller: _titleCtrl,
                label: 'اسم المحاضرة',
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _Field(controller: _roomCtrl, label: 'القاعة (اختياري)'),
              const SizedBox(height: 12),
              _WeekdayPicker(
                value: _weekday,
                onChanged: (value) => setState(() => _weekday = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Field(
                      controller: _startCtrl,
                      label: 'البداية',
                      hint: '08:30',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Field(
                      controller: _endCtrl,
                      label: 'النهاية',
                      hint: '10:00',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Stated in the form, not only in a doc comment: the parser is
              // deliberately lenient about the separator, and an admin who does not
              // know that will keep retyping a colon on a keyboard that will not
              // produce one.
              const Text(
                'يقبل 08:30 أو 08.30 أو 0830',
                style: TextStyle(fontSize: 12, color: DashboardColors.subtitle),
              ),
              if (_isEdit && _entry!.updatedBy.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Who last touched this row, so a shared table has an obvious
                // person to ask before overwriting their edit.
                Text(
                  'آخر تعديل: ${_entry!.updatedBy}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DashboardColors.subtitle,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: _danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'حفظ' : 'إضافة'),
        ),
      ],
    );
  }
}

/// One labelled input, so the four fields in this form share one decoration
/// instead of four hand-built copies that drift apart.
///
/// Focused and unfocused borders are both stated because the form sits on the
/// dashboard's dark palette, where the theme's default underline is invisible.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: const TextStyle(color: DashboardColors.title, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: DashboardColors.subtitle),
        hintStyle: const TextStyle(color: DashboardColors.subtitle),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: DashboardColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: DashboardColors.accent),
        ),
      ),
    );
  }
}

/// The day picker, built from the model's own numbering.
///
/// The seven items are generated from `TimetableEntry.weekdayNames` rather than
/// typed here in a second order, because the number this form saves is the index
/// into that list (`weekday - 1`): a list written out of order in the widget would
/// file Sunday's lecture under Monday without anything looking wrong.
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      // `initialValue`, not `value`: the latter is deprecated on this Flutter and
      // means the same thing.
      initialValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      dropdownColor: DashboardColors.surface,
      style: const TextStyle(color: DashboardColors.title, fontSize: 14),
      decoration: const InputDecoration(
        labelText: 'اليوم',
        labelStyle: TextStyle(color: DashboardColors.subtitle),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: DashboardColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: DashboardColors.accent),
        ),
      ),
      items: [
        for (var day = DateTime.monday; day <= DateTime.sunday; day++)
          DropdownMenuItem<int>(
            value: day,
            child: Text(TimetableEntry.weekdayLabel(day)),
          ),
      ],
    );
  }
}
