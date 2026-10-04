import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/dashboard_quote.dart';
import '../../providers/app_state.dart';
import 'dashboard_palette.dart';
import 'quote_manager_dialog.dart';

/// The dashboard's quote panel: the quotations an admin writes, one at a time.
///
/// It took the row the streak card used to hold, and sits at the left of that
/// row with the three figure cards beside it: a quotation is prose and prose is
/// the one thing on this dashboard that cannot be read at a glance from 30
/// pixels away, so it needs the row's width more than a figure does.
///
/// The rotation is local and it is not a shared clock: every reader turns the
/// page on their own [kQuoteHold], so two people looking at two dashboards read
/// two different sentences. That is deliberate — a quotation everybody saw at
/// the same moment would be an announcement, and the admin has an announcement
/// surface already. What is shared is the *list*, which is why it comes from
/// Firestore rather than from the device.
///
/// A pinned quote ends the rotation rather than joining it: that is the admin's
/// one override, the sentence that stays on every student's dashboard until it
/// is taken down. See `QuoteService.setPinned` for why only one can be pinned.
///
/// Right-click opens the manager, for an admin only. Everyone else gets a card
/// with no gesture on it at all, for the reason `ScheduleAdminButton` gives: a
/// right-click that opens nothing is a control the dashboard advertises and does
/// not have.
class DashboardQuotesCard extends StatefulWidget {
  const DashboardQuotesCard({super.key, this.quotes});

  /// Replaces the provider's list. Present for the same reason
  /// `DashboardReadingStats.days` is: the panel's own behaviour — a long
  /// quotation wrapping inside a fixed height, a pinned one refusing to rotate —
  /// can then be pumped with no Firebase behind it. Production leaves this null
  /// and reads `AppProvider.quotes`.
  final List<DashboardQuote>? quotes;

  @override
  State<DashboardQuotesCard> createState() => _DashboardQuotesCardState();
}

class _DashboardQuotesCardState extends State<DashboardQuotesCard> {
  /// Which quote of the rotating set is on screen. Not persisted anywhere: it is
  /// a position, and restoring it across launches would mean re-showing the
  /// sentence the reader already read yesterday.
  int _index = 0;

Timer? _timer;

  /// How many quotes the last armed rotation was sized for.
  ///
  /// Held so `build` can ask "does the timer still match this list?" without
  /// arming a new one every frame. See [_syncRotation].
  int _armedFor = -1;

  @override
  void dispose() {
    // The one thing this widget must not leak. A periodic timer outlives its
    // `State`, and the next `setState` after disposal is the exception this
    // `dispose` exists to prevent.
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  /// The quote on screen right now, or null while the list is empty.
  ///
  /// The pinned one wins outright: if an admin pinned a sentence, the rotation
  /// is off and there is nothing to choose.
  DashboardQuote? get _current {
    final quotes = _quotes;
    if (quotes.isEmpty) return null;
    final pinned = quotes.where((q) => q.pinned).firstOrNull;
    if (pinned != null) return pinned;
    return quotes[_index % quotes.length];
  }

  /// The list the panel draws from, preferring the injected one.
  ///
  /// Checked first and read without touching a provider, because
  /// `widget.quotes ?? context.watch<AppProvider>().quotes` evaluates the
  /// provider read whenever the prop is null — and this card is pumped on its own
  /// with no provider above it precisely in the tests that hold the layout and the
  /// rotation honest. The two paths stay separate here rather than being folded
  /// into one expression.
  ///
  /// Only ever called from `build`, never from `initState`: `context.watch`
  /// registers a dependency, and registering one before `initState` has finished
  /// throws — `dependOnInheritedWidgetOfExactType was called before
  /// initState() completed`, which is the failure this comment was written after.
  List<DashboardQuote> get _quotes {
    final injected = widget.quotes;
    if (injected != null) return injected;
    return context.watch<AppProvider>().quotes;
  }

  /// How many quotes the rotation is choosing between — the whole list when none
  /// is pinned, none when one is.
  int get _rotatingCount {
    final quotes = _quotes;
    if (quotes.any((q) => q.pinned)) return 0;
    return quotes.length;
  }

  /// Arms the rotation when the list changed underneath it, and only then.
  ///
  /// Called from `build` and deliberately not from `initState`: the list is only
  /// knowable during `build` (it comes from the provider), and asking for it in
  /// `initState` is what threw the assertion named in [_quotes]. Arming here also
  /// covers the case `initState` could never have seen anyway — an admin adding
  /// or pinning a quotation while the panel is open.
  ///
  /// The arming itself is deferred to a post-frame callback, for the reason
  /// `DashboardStatCard._Sync` gives: this is a side effect inside `build`, and
  /// the framework is one refactor away from throwing on that.
  void _syncRotation(int count) {
    if (count == _armedFor) return;
    _armedFor = count;
    // One quote, or none, has nothing to rotate between. Leaving a timer armed
    // would wake the widget every 12 seconds to setState to the same state.
    if (count < 2) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer?.cancel();
      _timer = Timer(kQuoteHold, () {
        if (!mounted) return;
        setState(() => _index++);
        _syncRotation(_rotatingCount);
      });
    });
}

  /// Opens the manager for an admin, and does nothing at all for anyone else.
  ///
  /// The role is read at the moment of the click rather than watched into a
  /// field, so a student is stopped here rather than by a rebuild that a future
  /// refactor might forget to keep.
  void _openManager() {
    final isAdmin = context.read<AppProvider>().currentUser?.isAdmin ?? false;
    if (!isAdmin) return;
    // The same call `showScheduleManager` makes, for the same reason: opening the
    // dialog is the moment its spinner starts counting, so this is the cheapest
    // place to notice a subscription nobody opened.
    context.read<AppProvider>().ensureQuotesWatched();
    showQuoteManager(context);
  }

  @override
  Widget build(BuildContext context) {
    final quotes = _quotes;
    final current = _current;
    // Armed from here rather than from `initState`, because the list is only
    // knowable now — see `_syncRotation`.
    _syncRotation(_rotatingCount);

    return GestureDetector(
      // `onSecondaryTapUp` rather than a `Listener` on a raw pointer: this is the
      // gesture the platform already owns, so the panel needs nothing invented to
      // be right-clickable.
      onSecondaryTapUp: (_) => _openManager(),
      child: Container(
        height: kQuotesPanelHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: kQuotesPanelPadding,
        ),
        decoration: DashboardColors.card(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: current == null
                    ? const _QuotesEmpty()
                    : _QuoteBody(key: ValueKey(current.id), quote: current),
              ),
            ),
            // The admin's override, visible to everyone: a sentence that never
            // changes is a statement, and a reader who did not know it was pinned
            // would sit waiting for the panel to move on. No gap above it — at 80px
            // every pixel is accounted for, and this label is the first thing to
            // go if the sentence grows.
            if (quotes.any((q) => q.pinned))
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'مثبّتة من الإدارة',
                  style: TextStyle(
                    fontSize: 10,
                    color: DashboardColors.subtitle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The empty state: an honest line, not a sample quotation.
///
/// A quotation invented here would be attributed to nobody and readable as the
/// app's own opinion, which is worse than an empty card — the same rule
/// `DashboardReadingStats` states for its zeroes.
class _QuotesEmpty extends StatelessWidget {
  const _QuotesEmpty();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'لا توجد اقتباسات بعد',
      style: TextStyle(fontSize: 14, color: DashboardColors.subtitle),
    );
  }
}

/// One quotation, with its author, and the fade between it and the next.
///
/// The fade is what makes the swap a page turn rather than a flicker, and it is
/// keyed on the document id so the transition is what moves: two different
/// sentences are two different widgets, and the same sentence arriving twice (an
/// admin re-saving it) does not fade at all.
class _QuoteBody extends StatelessWidget {
  const _QuoteBody({super.key, required this.quote});

  final DashboardQuote quote;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: kQuoteFadeDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // `FadeTransition` on its own rather than the default scale: a quotation
      // growing and shrinking as it changes reads as an animation on a card that
      // is meant to be quiet.
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(child: _QuoteText(quote.text)),
          // 6 rather than the 12 this card started with: the panel came down to
          // 80, and the sentence plus the author already fill it. The gap is the
          // slack, so it is where the height reduction was taken from — not from
          // the type, which is what the reader came for.
          const SizedBox(height: 6),
          Text(
            '— ${quote.author}',
            key: const ValueKey('quote-author'),
            style: const TextStyle(
              fontSize: kQuoteAuthorFontSize,
              color: DashboardColors.subtitle,
              // 1.2, not the 1.35 the quotation uses: at 12px the Arabic face's
              // own metric is ~1.7×, so anything higher would push the author
              // line past the bottom of an 80px card on its own.
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sentence, at [kQuoteFontSize] and never below [kQuoteMinFontSize].
///
/// Measured rather than left to a `FittedBox`, for the reason
/// `DashboardSectionTitle._shrinkingTitle` gives: a `FittedBox` scales by
/// whatever factor it needs and would carry a long quotation past the floor,
/// where it stops reading as prose. The card is a fixed height, so the text
/// shrinks into it rather than pushing the author line off the bottom.
class _QuoteText extends StatelessWidget {
  const _QuoteText(this.text);

  final String text;

  /// The style at any size in the shrink, written once because the painter and
  /// the rendered `Text` below have to agree on the measurement — a `Text` set
  /// at a different size than the one that was measured is how a card overflows
  /// the height nothing said it would.
  static TextStyle _styleFor(double fontSize) => TextStyle(
    fontSize: fontSize,
    color: DashboardColors.title,
    // 1.35 rather than the 1.6 this card started at: the panel is 80px now, and
    // the Noto Naskh face reports a line height near 1.7× its size on its own —
    // at 1.6 a 14px line took 22px and a second one pushed the author off the
    // bottom. 1.35 lets two lines and an attribution share 56px of a 56px box.
    // Stated rather than left to the theme's 1.4, which is tuned for body copy.
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: _styleFor(kQuoteFontSize)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 3,
        )..layout(maxWidth: constraints.maxWidth);

        // Measured against the room this row actually has. An unbounded
        // constraint is the answer to "this row is not in a bounded box", not a
        // failure, so it shrinks nothing rather than dividing by infinity.
        final over = constraints.maxHeight.isFinite
            ? painter.height - constraints.maxHeight
            : 0.0;
        final scale = over > 0
            ? (1 - over / painter.height).clamp(
                kQuoteMinFontSize / kQuoteFontSize,
                1.0,
              )
            : 1.0;
        painter.dispose();

        return Text(
          text,
          key: const ValueKey('quote-text'),
          maxLines: 3,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: _styleFor(kQuoteFontSize * scale),
        );
      },
    );
  }
}
