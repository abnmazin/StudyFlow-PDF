import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/dashboard_quote.dart';
import '../../providers/app_state.dart';
import 'dashboard_palette.dart';

/// Opens the quote manager.
///
/// A function rather than a callback baked into the panel, for the reason
/// `showScheduleManager` gives: a second entry point (a menu item, a shortcut)
/// can open the same dialog without the card knowing about it. It also opens
/// nothing at all for a reader who is not an admin — the role check lives at the
/// door, not only in the panel's gesture.
Future<void> showQuoteManager(BuildContext context) {
  final isAdmin = context.read<AppProvider>().currentUser?.isAdmin ?? false;
  if (!isAdmin) return Future<void>.value();

  return showDialog<void>(
    context: context,
    builder: (_) => const QuoteManagerDialog(),
  );
}

/// Every quotation on the shared list, with pin, edit and delete on each.
///
/// Reads `AppProvider.quotes`, the whole list, because the panel reads that and
/// not a slice: an admin editing the list has to be able to fix any row of it,
/// which is the same reason the timetable's manager reads
/// `timetableEntries` rather than today's `lectures`.
class QuoteManagerDialog extends StatelessWidget {
  const QuoteManagerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DashboardColors.surface,
      title: const Text(
        'إدارة الاقتباسات',
        style: TextStyle(color: DashboardColors.title, fontSize: 18),
      ),
      content: SizedBox(
        width: 520,
        // An `AlertDialog` does not scroll its own content, and a long list of
        // quotations runs past the bottom of a laptop screen: without a cap the
        // later rows are simply unreachable.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Consumer<AppProvider>(
            builder: (context, app, _) {
              // The same distinction the panel makes: an empty list and a list
              // nobody has asked about yet are different answers, and drawing
              // the empty state during the first round trip would flash a wrong
              // one.
              if (!app.isQuotesLoaded) {
                if (app.isQuotesFailed) {
                  return const _QuotesUnavailable();
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

              final quotes = app.quotes;
              if (quotes.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.format_quote,
                        size: 32,
                        color: DashboardColors.border,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'لم يضف أي اقتباس بعد',
                        style: TextStyle(
                          fontSize: 13,
                          color: DashboardColors.subtitle,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                children: [
                  for (final quote in quotes)
                    _QuoteRow(quote: quote, quotes: quotes),
                ],
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
          onPressed: () => showQuoteEditorDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('إضافة اقتباس'),
        ),
      ],
    );
  }
}

/// One quotation in the manager: what it says, who said it, and its three
/// controls.
class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote, required this.quotes});

  final DashboardQuote quote;

  /// The whole list, because pinning is a question about the others: the pin
  /// button on an already-pinned row clears it, which is the only way the panel
  /// gets its rotation back.
  final List<DashboardQuote> quotes;

  /// The panel's rule, stated on the control that performs it: pinning a row
  /// releases whichever row was pinned, so there is never a second one.
  void _togglePin(BuildContext context) {
    final app = context.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(context);
    // `null` unpins everything. The provider flips every row in one go, because
    // the write behind it is a batch over all of them.
    final next = quote.pinned ? null : quote.id;
    app.setQuotePinned(next).catchError((Object e) {
      messenger.showSnackBar(
        SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
      );
    });
  }

  /// Deletes after a confirmation, because the write is shared.
  ///
  /// The confirmation is not ceremony: this quotation is on every user's
  /// dashboard at once, and there is no undo. Naming it in the question is what
  /// makes this a check rather than a reflex.
  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: DashboardColors.surface,
        title: const Text(
          'حذف الاقتباس',
          style: TextStyle(color: DashboardColors.title, fontSize: 18),
        ),
        content: Text(
          'سيتم حذف الاقتباس من لوحة جميع المستخدمين. هل أنت متأكد؟',
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
      await context.read<AppProvider>().deleteQuote(quote.id);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ تم حذف الاقتباس'),
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
        // The pinned row is tinted with the dashboard's hover blue, so the one
        // sentence the panel is holding is visible in the list that controls it.
        color: quote.pinned ? DashboardColors.hover : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: quote.pinned ? DashboardColors.accent : DashboardColors.divider,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: DashboardColors.title,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '— ${quote.author}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DashboardColors.subtitle,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            // The tooltip says which of the two actions this button will do,
            // because the icon alone cannot: the same pin means "hold this" on
            // an unpinned row and "let the rotation back in" on a pinned one.
            tooltip: quote.pinned ? 'إلغاء التثبيت' : 'تثبيت على اللوحة',
            onPressed: () => _togglePin(context),
            icon: Icon(
              quote.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 18,
              color: quote.pinned
                  ? DashboardColors.accent
                  : DashboardColors.subtitle,
            ),
          ),
          IconButton(
            tooltip: 'تعديل',
            onPressed: () => showQuoteEditorDialog(context, quote: quote),
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: DashboardColors.subtitle,
            ),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: () => _confirmDelete(context),
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: _danger,
            ),
          ),
        ],
      ),
    );
  }
}

/// The red this file's destructive controls use.
///
/// Named here rather than borrowed from a palette that has no red: this is the
/// only palette that needed one, and adding a destructive colour to
/// `DashboardColors` would put a token in every other file's reach to misuse.
const _danger = Color(0xFFEF4444);

/// The add/edit form.
///
/// Both modes in one dialog, chosen by [quote] being null or not, because they
/// are the same two fields and the same one rule — a form that is "add" until
/// the row is loaded and then turns into "edit" is two code paths for one
/// validation, and one of them drifts.
Future<void> showQuoteEditorDialog(
  BuildContext context, {
  DashboardQuote? quote,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _QuoteEditorDialog(quote: quote),
  );
}

/// A failed read, told apart from a list nobody has asked about yet.
///
/// The schedule card has the same row, and the reason it exists is the same: a
/// rule that is not deployed, a denied read and a dead network all end
/// identically, and an empty list would tell the admin the quotations are gone.
class _QuotesUnavailable extends StatelessWidget {
  const _QuotesUnavailable();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off,
            size: 28,
            color: DashboardColors.subtitle,
          ),
          const SizedBox(height: 12),
          const Text(
            'تعذّر تحميل الاقتباسات',
            style: TextStyle(fontSize: 13, color: DashboardColors.subtitle),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => context.read<AppProvider>().initQuotes(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

/// The form itself: the quotation, the author, and the one rule that decides
/// whether either of them is allowed in.
class _QuoteEditorDialog extends StatefulWidget {
  const _QuoteEditorDialog({this.quote});

  final DashboardQuote? quote;

  @override
  State<_QuoteEditorDialog> createState() => _QuoteEditorDialogState();
}

class _QuoteEditorDialogState extends State<_QuoteEditorDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.quote?.text ?? '',
  );
  late final TextEditingController _author = TextEditingController(
    text: widget.quote?.author ?? '',
  );

  bool _saving = false;

  /// The model's own sentence, shown under the fields.
  ///
  /// Read from [DashboardQuote.validationMessage] rather than written here, for
  /// the reason `TimetableService.saveEntry` states: this check is a
  /// convenience and the service is the rule, so one wording has to answer for
  /// both or the editor and the database will disagree about the same sentence.
  String? _problem() => DashboardQuote.validationMessage(
    text: _text.text,
    author: _author.text,
  );

  bool get _isEdit => widget.quote != null;

  @override
  void dispose() {
    _text.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final invalid = _problem();
    if (invalid != null || _saving) return;

    setState(() => _saving = true);
    final existing = widget.quote;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final quote = DashboardQuote(
      // An edit keeps the id; an add leaves it empty and the service creates
      // the document. Getting this backwards turns an edit into a second
      // quotation nobody can delete.
      id: existing?.id ?? '',
      text: _text.text.trim(),
      author: _author.text.trim(),
      // The pin is the manager's control, not the form's: a new quotation is
      // never born pinned, and an edit leaves the pin exactly where it was.
      pinned: existing?.pinned ?? false,
    );
try {
      await context.read<AppProvider>().saveQuote(quote);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEdit ? '✅ تم حفظ التعديل' : '✅ تمت الإضافة'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // The dialog stays open on a failed write, with the admin's text still in
      // it: closing it would throw away the sentence they just typed because the
      // network blinked.
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _problem();

    return AlertDialog(
      backgroundColor: DashboardColors.surface,
      title: Text(
        _isEdit ? 'تعديل الاقتباس' : 'اقتباس جديد',
        style: const TextStyle(color: DashboardColors.title, fontSize: 18),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              controller: _text,
              label: 'نص الاقتباس',
              hint: 'اكتب الحكمة أو المقولة',
              autofocus: true,
              maxLines: 3,
              // The one listener that redraws the counter and the sentence under
              // the fields. `setState` is called on the form, not on the field —
              // see `_Field.onChanged`.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _author,
              label: 'الكاتب أو المؤلف',
              hint: 'مثال: المتنبي',
            ),
            // The counter and the sentence in one line, because the limit is the
            // same number the Firestore rule enforces and an admin about to be
            // refused by that rule should have been told here.
            if (invalid != null || _text.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  invalid ??
                      '${_text.text.length} / ${DashboardQuote.maxTextLength}',
                  style: TextStyle(
                    fontSize: 12,
                    color: invalid != null ? _danger : DashboardColors.subtitle,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _saving || invalid != null ? null : _save,
          child: _saving
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

/// One labelled input, so the two fields in this form share one decoration
/// instead of two hand-built copies that drift apart.
///
/// Focused and unfocused borders are both stated because the form sits on the
/// dashboard's dark palette, where the theme's default underline is invisible.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.autofocus = false,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool autofocus;
  final int maxLines;

  /// Told about every keystroke so the form can re-read its own validation.
  ///
  /// A callback rather than the field rebuilding itself: the counter and the
  /// sentence that tells the admin their quotation is too long both live in the
  /// form above, and a field that redrew only itself would leave them showing
  /// the answer to the previous keystroke.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: 1,
      // No `setState` here, and that is deliberate: the field reports a keystroke
      // to nobody and rebuilds nothing. The counter and the validation sentence
      // belong to the form above, which listens here and rebuilds itself — a
      // field calling `setState` on its own would rebuild a `TextField` whose
      // text it did not change.
      onChanged: (value) => onChanged?.call(value),
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
