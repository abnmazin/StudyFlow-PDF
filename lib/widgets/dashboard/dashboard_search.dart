import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/structure.dart';
import '../../providers/app_state.dart';
import 'dashboard_palette.dart';

/// Document search over the user's own local files.
///
/// Real, not decorative: the query runs against the in-memory class list the
/// explorer already holds (`AppProvider.classes`, hydrated from Isar at login),
/// so it costs nothing and always sees exactly what the sidebar shows. Tapping
/// a result activates the file through the same two calls the sidebar uses.
///
/// Local files only, on purpose. The university library lives in Firestore, and
/// searching it would mean a network round trip per keystroke on a dashboard
/// that is otherwise offline-first.
///
/// Opened empty-handed the panel is still a list, not an empty box: it offers
/// the files worth resuming (see [buildSearchSuggestions]) plus the size of the
/// library it searches, so the field reads as a search before the first key.
class DashboardSearch extends StatefulWidget {
  const DashboardSearch({
    super.key,
    required this.isWide,
    required this.contentWidth,
    this.libraryOverride,
  });

  final bool isWide;

  /// The dashboard's content width. Kept for the narrow layout, where the field
  /// is the one element allowed to shrink and the panel follows it.
  final double contentWidth;

  /// The local library, injected. Production leaves it null and the panel reads
  /// `AppProvider`; a widget test cannot, because an `AppProvider` opens
  /// `SyncService`, Isar and Firebase in its constructor, and the two things
  /// worth locking here — that the panel hangs off the field's *bottom* edge and
  /// that it shows a list rather than an empty box — are its rendered behaviour.
  final SearchLibrary Function()? libraryOverride;

  @override
  State<DashboardSearch> createState() => _DashboardSearchState();
}

/// The slice of the app state the search reads, in one read rather than four.
typedef SearchLibrary = ({
  List<ClassItem> classes,
  String? activeClassId,
  String? activePdfId,
});

/// Identifies the panel's own box.
///
/// A test measures *this* to know where the panel opens. Measuring the first
/// row of text instead is not the same fact: the panel draws a header above that
/// row, so a panel hung off the field's top edge still pushes its first row below
/// the field's bottom, and the mistake reads as a pass.
const Key searchPanelKey = ValueKey('dashboardSearchPanel');

class _DashboardSearchState extends State<DashboardSearch> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final OverlayPortalController _portal = OverlayPortalController();

  String _query = '';

  /// A dashboard dropdown listing 400 files is a worse answer than one showing
  /// the best handful and inviting a narrower query.
  static const int _maxResults = 8;

  /// Ties the field and its results panel into one tap area.
  static const String _tapGroup = 'dashboard-search';

  /// The brief's field: 384 wide, 44 tall, fully rounded. The results panel
  /// takes the same 384 so the two read as one control.
  static const double fieldWidth = 384;
  static const double fieldHeight = 44;

  /// Tall rather than wide: the field sets the width, the list sets the height.
  static const double _maxPanelHeight = 480;

  /// How the results panel should be placed.
  ///
  /// The width is fixed at the field's own width and only shrinks when the room
  /// beside the field cannot hold it. The height grows downwards, limited by the
  /// space below the field.
  ///
  /// The measurement comes from [OverlayChildLayoutInfo] — the field's box, its
  /// paint transform into the overlay, and the overlay's size — instead of from
  /// a `GlobalKey` + `localToGlobal` + `MediaQuery` trio. Same three facts, one
  /// layer lower, and no `CompositedTransformFollower` in the portal's ancestry:
  /// `overlay.dart` forbids that combination, and `Tooltip` (built on
  /// `OverlayPortal.overlayChildLayoutBuilder` too) is what trips it.
  ///
  /// Deliberately a pure function of the layout that just ran rather than
  /// stored state: it is called from inside layout, where `setState` is an
  /// error.
  ({double top, double? left, double? right, double width, double height})
  _geometry(OverlayChildLayoutInfo info) {
    final screen = info.overlaySize;
    const margin = 12.0;
    const gap = 8.0;

    // Physical, because `Positioned` is: `left`/`right` are window sides, not
    // reading-order sides.
    final origin = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset.zero,
    );
    final rect = origin & info.childSize;

    final roomToRight = screen.width - margin - rect.left;
    final roomToLeft = rect.right - margin;
    final toRight = roomToRight >= roomToLeft;
    final room = toRight ? roomToRight : roomToLeft;
    final below = screen.height - margin - rect.bottom - gap;

    // Hung off the field's *bottom*, not its top, so the panel cannot cover the
    // field or the bar's other controls.
    return (
      top: rect.bottom + gap,
      left: toRight ? rect.left : null,
      right: toRight ? null : screen.width - rect.right,
      width: (fieldWidth < room ? fieldWidth : room).clamp(
        0.0,
        screen.width - 2 * margin,
      ),
      height: below < _maxPanelHeight ? below : _maxPanelHeight,
    );
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    if (_focusNode.hasFocus) {
      _portal.show();
    }
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
    _focusNode.requestFocus();
  }

  /// The app state this panel reads, or the injected stand-in for it.
  ///
  /// Read with `read`, not `watch`, exactly like the rest of the widget: watching
  /// the provider would rebuild the field on every unrelated notify — a page
  /// turn writes reading progress through it — and both lists are a snapshot of
  /// the frame the panel opened on anyway.
  SearchLibrary _library() {
    final override = widget.libraryOverride;
    if (override != null) return override();
    final app = context.read<AppProvider>();
    return (
      classes: app.classes,
      activeClassId: app.activeClassId,
      activePdfId: app.activePdfId,
    );
  }

  static List<SearchSuggestion> _search(String query, List<ClassItem> classes) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final hits = <SearchSuggestion>[];
    for (final cls in classes) {
      for (final pdf in cls.pdfs) {
        if (pdf.name.toLowerCase().contains(needle)) {
          hits.add(
            SearchSuggestion(classId: cls.id, className: cls.name, pdf: pdf),
          );
        }
      }
    }
    return hits;
  }

  /// Every local file. The panel's footer quotes the library's size, which the
  /// capped suggestion list cannot report on its own.
  static int _totalFiles(List<ClassItem> classes) {
    var total = 0;
    for (final cls in classes) {
      total += cls.pdfs.length;
    }
    return total;
  }

  void _openResult(SearchSuggestion hit) {
    final app = context.read<AppProvider>();
    // Unfocusing first: the focus listener hides the panel, so the list is gone
    // before the class and PDF ids move underneath it.
    _focusNode.unfocus();
    _controller.clear();
    setState(() => _query = '');
    app.setActiveClass(hit.classId);
    app.setActivePdf(hit.pdf.id);
  }

  @override
  Widget build(BuildContext context) {
    final library = _library();
    // One list or the other, decided here rather than inside the panel: an
    // empty query means the suggestions, and typing means the matches.
    final hasQuery = _query.trim().isNotEmpty;
    final matches = hasQuery
        ? _search(_query, library.classes)
        : const <SearchSuggestion>[];
    final suggestions = hasQuery
        ? const <SearchSuggestion>[]
        : buildSearchSuggestions(
            library.classes,
            activeClassId: library.activeClassId,
            activePdfId: library.activePdfId,
            max: _maxResults,
          );
    final totalFiles = hasQuery ? 0 : _totalFiles(library.classes);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      // Floats over the page instead of pushing the sections below it down, and
      // is clipped to the window rather than to the dashboard's scroll view.
      //
      // Placed with `Positioned` from `_geometry(info)` rather than with a
      // `CompositedTransformFollower`: `overlay.dart` forbids a follower between
      // an `OverlayPortal` and its `Overlay` (it asserts in debug, "may result in
      // an incorrect child paint transform"). That combination already crashed
      // the notifications panel through a `Tooltip`, and `Tooltip` itself is an
      // `OverlayPortal.overlayChildLayoutBuilder` — the panel's footer and the
      // clear button are exactly the kind of place one gets added next.
      overlayChildBuilder: (context, info) {
        final placement = _geometry(info);
        // Physical edges: `left`/`right` are window sides. The panel's `top` is
        // the field's bottom plus the gap, so it opens under the field instead
        // of over it and the bar's other controls.
        return Positioned(
          top: placement.top,
          left: placement.left,
          right: placement.right,
          child: TapRegion(
            // The results live in the Overlay, so they are not descendants of
            // the field's `TapRegion` below. Without a shared group the tap that
            // dismisses the field fires on pointer-down, before the tapped
            // result's own handler, and picking a file does nothing. It wraps
            // the panel only, not the empty space around it.
            groupId: _tapGroup,
            child: ConstrainedBox(
              key: searchPanelKey,
              // Never wider or taller than the room measured beside the field,
              // so the panel cannot run past the window edge.
              constraints: BoxConstraints(
                maxWidth: placement.width,
                maxHeight: placement.height,
              ),
              child: _SearchResults(
                matches: matches,
                suggestions: suggestions,
                query: _query,
                totalFiles: totalFiles,
                maxResults: _maxResults,
                onPick: _openResult,
              ),
            ),
          ),
        );
      },
      // The field itself: the portal's own `child`, and the box `_geometry`
      // measures off the layout info. No `CompositedTransformTarget` here.
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) {
          _focusNode.unfocus();
          _portal.hide();
        },
        child: SizedBox(
          height: fieldHeight,
          width: widget.isWide ? fieldWidth : 260,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13, color: DashboardColors.title),
            decoration: InputDecoration(
              hintText: 'ابحث في ملفاتك…',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: DashboardColors.subtitle,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: DashboardColors.subtitle,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clear,
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: DashboardColors.subtitle,
                      ),
                      tooltip: 'مسح',
                    ),
              isDense: true,
              filled: true,
              fillColor: DashboardColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                // Pill, per the brief: half the field's height, so the two
                // halves meet and the radius never shows a corner.
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: DashboardColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: DashboardColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(
                  color: DashboardColors.accent,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the panel: a file, the folder it lives in, and — for a row from
/// the pre-typing list — the reading position that earned it its place.
class SearchSuggestion {
  const SearchSuggestion({
    required this.classId,
    required this.className,
    required this.pdf,
    this.note,
  });

  final String classId;
  final String className;
  final PdfItem pdf;

  /// A short status line for the suggestion list ('آخر ملف فتحته', 'صفحة 12'),
  /// printed under the name. Null on a plain query match, which stays one line.
  final String? note;
}

/// The label on the row the reader would resume, and on the ones they never
/// started. Literals because the row prints them and nothing else reads them.
const String _resumeNote = 'آخر ملف فتحته';
const String _noProgressNote = 'لا تقدّم محفوظ';

/// Whether the reader has a place saved in this file.
///
/// `lastPage` counts from 1 and Isar defaults it to 1, so "has a place" means
/// "past the first page": a plain `!= null` would mark every hydrated file as
/// progress and flatten the ranking into the sidebar's own order.
bool _hasPlace(PdfItem pdf) {
  final page = pdf.lastPage;
  return page != null && page > 1;
}

/// The list shown before the user types anything.
///
/// Ranked the way a reader resumes work rather than the way the sidebar is
/// ordered: where they are, then the files with a place saved in them, then the
/// rest of the active folder, then everything else. Top-level and pure on
/// purpose: the widget's own lists come from `context.read<AppProvider>()`,
/// which a widget test cannot seed, so the ranking is kept callable on its own.
List<SearchSuggestion> buildSearchSuggestions(
  List<ClassItem> classes, {
  String? activeClassId,
  String? activePdfId,
  int max = 8,
}) {
  final ranked = <SearchSuggestion>[];
  final taken = <String>{};

  void add(ClassItem cls, PdfItem pdf, String? note) {
    // `taken` as well as the cap: the same file can sit in two folders, and two
    // identical rows a reader cannot tell apart is worse than one.
    if (ranked.length >= max || !taken.add(pdf.id)) return;
    ranked.add(
      SearchSuggestion(
        classId: cls.id,
        className: cls.name,
        pdf: pdf,
        note: note,
      ),
    );
  }

  // 1. Where the reader is: the open file, or the active folder's memory of the
  //    last file opened in it when nothing is open.
  final active = _classById(classes, activeClassId);
  final resumeId = activePdfId ?? active?.lastActivePdfId;
  if (resumeId != null) {
    for (final cls in classes) {
      for (final pdf in cls.pdfs) {
        if (pdf.id == resumeId) add(cls, pdf, _resumeNote);
      }
    }
  }

  // 2. Every file with a place saved in it, in the sidebar's own order.
  for (final cls in classes) {
    for (final pdf in cls.pdfs) {
      if (ranked.length >= max) break;
      if (_hasPlace(pdf)) add(cls, pdf, 'صفحة ${pdf.lastPage}');
    }
  }

  // 3. What is left: the active folder's files first, then the other folders'
  //    — the sidebar's order again, for a reader who has started nothing yet.
  if (active != null) {
    for (final pdf in active.pdfs) {
      if (ranked.length >= max) break;
      add(active, pdf, _noProgressNote);
    }
  }
  for (final cls in classes) {
    for (final pdf in cls.pdfs) {
      if (ranked.length >= max) break;
      add(cls, pdf, _noProgressNote);
    }
  }

  return ranked;
}

ClassItem? _classById(List<ClassItem> classes, String? id) {
  if (id == null) return null;
  for (final cls in classes) {
    if (cls.id == id) return cls;
  }
  return null;
}

/// The word above the pre-typing list: "continue" is only promised when a row
/// can actually keep it.
String _heading(List<SearchSuggestion> rows) =>
    rows.any((row) => _hasPlace(row.pdf)) ? 'تابع من حيث توقفت' : 'ملفاتك';

/// Arabic counts a file total several ways, and "1 ملفات" is the kind of wrong
/// a reader notices. Only the four shapes this footer can produce are handled.
String _filesCount(int count) {
  if (count == 1) return 'ملف واحد';
  if (count == 2) return 'ملفين';
  if (count <= 10) return '$count ملفات';
  return '$count ملفاً';
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.matches,
    required this.suggestions,
    required this.query,
    required this.totalFiles,
    required this.maxResults,
    required this.onPick,
  });

  /// The query's hits — empty when there is no query.
  final List<SearchSuggestion> matches;

  /// The pre-typing list — empty once the user has typed something.
  final List<SearchSuggestion> suggestions;

  final String query;

  /// Every local file, which the footer quotes: the list itself is capped, so
  /// it cannot report the size of the library it is a window onto.
  final int totalFiles;

  final int maxResults;
  final ValueChanged<SearchSuggestion> onPick;

  @override
  Widget build(BuildContext context) {
    final typed = query.trim().isNotEmpty;
    final rows = typed ? matches : suggestions;
    return Material(
      color: Colors.transparent,
      // No width cap of its own: the caller measures the room beside the field
      // and applies it, and a second cap here would only fight with that one.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DashboardColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DashboardColors.border),
          boxShadow: DashboardColors.panelShadow,
        ),
        // Two empty states, and neither is a box with nothing in it: a query
        // that matched nothing, and a user who has no local files yet.
        child: rows.isEmpty
            ? _PanelNote(text: typed ? 'لا نتائج' : 'لا توجد ملفات محلية بعد')
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // The heading only heads a list the user did not ask for: a
                  // query's own results need no word above them.
                  children: [
                    if (!typed) _PanelHeading(text: _heading(rows)),
                    // Scrollable and shrink-wrapped: eight rows must not
                    // overflow a short window, and one row must not leave a
                    // tall empty box behind it. `Flexible` is what bounds the
                    // list to the room the heading and the footer leave.
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: min(rows.length, maxResults),
                        itemBuilder: (context, index) {
                          final hit = rows[index];
                          return _ResultTile(
                            hit: hit,
                            onTap: () => onPick(hit),
                          );
                        },
                      ),
                    ),
                    if (!typed)
                      _PanelFooter(
                        text:
                            'اكتب اسم الملف للبحث في ${_filesCount(totalFiles)}',
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// One empty state, sized to its own words rather than to the panel.
class _PanelNote extends StatelessWidget {
  const _PanelNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: DashboardColors.subtitle),
      ),
    );
  }
}

/// The word above the pre-typing list.
class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DashboardColors.subtitle,
          ),
        ),
      ),
    );
  }
}

/// The hint under the list. Dividers, not padding, because it is a footnote to
/// the list rather than one more row of it.
class _PanelFooter extends StatelessWidget {
  const _PanelFooter({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DashboardColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: DashboardColors.subtitle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.hit, required this.onTap});

  final SearchSuggestion hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final note = hit.note;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.picture_as_pdf,
              size: 16,
              color: DashboardColors.subtitle,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                // Start, not centre: the two lines share an edge, and the
                // second one is shorter than the first on purpose.
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hit.pdf.name,
                    style: const TextStyle(
                      fontSize: 13,
                      color: DashboardColors.title,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // The folder and the reading position, together: the folder
                  // alone was already the least useful part of the row, and a
                  // suggestion is only worth its place because of the page.
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${hit.className} · $note',
                      style: const TextStyle(
                        fontSize: 11,
                        color: DashboardColors.subtitle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // A query match keeps the folder on the same line instead, under
            // the name it belongs to. Flexible, not fixed: an unbounded folder
            // name would otherwise widen the row past the panel's cap and
            // overflow it.
            if (note == null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hit.className,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DashboardColors.subtitle,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
