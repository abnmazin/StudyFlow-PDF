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
class DashboardSearch extends StatefulWidget {
  const DashboardSearch({
    super.key,
    required this.isWide,
    required this.contentWidth,
  });

  final bool isWide;

  /// The dashboard's content width. Kept for the narrow layout, where the field
  /// is the one element allowed to shrink and the panel follows it.
  final double contentWidth;

  @override
  State<DashboardSearch> createState() => _DashboardSearchState();
}

class _DashboardSearchState extends State<DashboardSearch> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// Used to find where the field sits on screen, which decides which way the
  /// results panel opens.
  final GlobalKey _fieldKey = GlobalKey();

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
  /// Deliberately a pure function of the current frame rather than stored state:
  /// it is read from `build`, and a `setState` from inside a build is an error.
  /// The overlay child closes over the result of the last build, which is the
  /// frame the panel was opened on.
  ({bool toRight, double width, double height}) _geometry() {
    final screen = MediaQuery.sizeOf(context);
    const margin = 12.0;
    const gap = 8.0;

    final box = _fieldKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return (
        toRight: true,
        width: fieldWidth.clamp(0.0, screen.width - 2 * margin),
        height: (screen.height - 2 * margin).clamp(0.0, _maxPanelHeight),
      );
    }

    final rect = box.localToGlobal(Offset.zero) & box.size;
    final roomToRight = screen.width - margin - rect.left;
    final roomToLeft = rect.right - margin;
    final toRight = roomToRight >= roomToLeft;
    final room = toRight ? roomToRight : roomToLeft;
    final below = screen.height - margin - rect.bottom - gap;

    return (
      toRight: toRight,
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

  List<_SearchHit> _search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final classes = context.read<AppProvider>().classes;
    final hits = <_SearchHit>[];
    for (final cls in classes) {
      for (final pdf in cls.pdfs) {
        if (pdf.name.toLowerCase().contains(needle)) {
          hits.add(_SearchHit(classId: cls.id, className: cls.name, pdf: pdf));
        }
      }
    }
    return hits;
  }

  void _openResult(_SearchHit hit) {
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
    final geometry = _geometry();
    final matches = _search(_query);
    final hasQuery = _query.trim().isNotEmpty;
    return OverlayPortal(
      controller: _portal,
      // Floats over the page instead of pushing the sections below it down, and
      // is clipped to the window rather than to the dashboard's scroll view.
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        // The follower takes physical `Alignment`, and matching the same edge
        // on both sides is what keeps the panel inside the window: it grows
        // towards whichever side the field has room on, sized to that room.
        targetAnchor: geometry.toRight ? Alignment.topLeft : Alignment.topRight,
        followerAnchor: geometry.toRight
            ? Alignment.topLeft
            : Alignment.topRight,
        offset: const Offset(0, 8),
        // The Overlay lays every entry out tight to the whole window
        // (`BoxConstraints.tight(size)`), and a follower hands those tight
        // constraints straight to its child, so a `maxWidth` below could never
        // shrink anything — the panel came out full-screen. `Align` is what
        // loosens them: it fills the window itself, so the anchors above still
        // land the panel on the field, and its empty half is not hit-tested, so
        // a tap outside the panel still reaches the field's `TapRegion`.
        child: Align(
          alignment: geometry.toRight ? Alignment.topLeft : Alignment.topRight,
          child: TapRegion(
            // The results live in the Overlay, so they are not descendants of
            // the field's `TapRegion` below. Without a shared group the tap that
            // dismisses the field fires on pointer-down, before the tapped
            // result's own handler, and picking a file does nothing. It wraps
            // the panel only, not the full-window `Align` around it.
            groupId: _tapGroup,
            child: ConstrainedBox(
              // Never wider or taller than the room measured beside the field,
              // so the panel cannot run past the window edge.
              constraints: BoxConstraints(
                maxWidth: geometry.width,
                maxHeight: geometry.height,
              ),
              child: _SearchResults(
                matches: matches,
                maxResults: _maxResults,
                showEmpty: hasQuery,
                onPick: _openResult,
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) {
            _focusNode.unfocus();
            _portal.hide();
          },
          child: SizedBox(
            key: _fieldKey,
            height: fieldHeight,
            width: widget.isWide ? fieldWidth : 260,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                fontSize: 13,
                color: DashboardColors.title,
              ),
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
      ),
    );
  }
}

class _SearchHit {
  const _SearchHit({
    required this.classId,
    required this.className,
    required this.pdf,
  });

  final String classId;
  final String className;
  final PdfItem pdf;
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.matches,
    required this.maxResults,
    required this.showEmpty,
    required this.onPick,
  });

  final List<_SearchHit> matches;
  final int maxResults;
  final bool showEmpty;
  final ValueChanged<_SearchHit> onPick;

  @override
  Widget build(BuildContext context) {
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
        child: showEmpty && matches.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Text(
                  'لا نتائج',
                  style: TextStyle(
                    fontSize: 13,
                    color: DashboardColors.subtitle,
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // Scrollable and shrink-wrapped: eight results must not
                // overflow a short window, and one result must not leave a
                // tall empty box behind it.
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: min(matches.length, maxResults),
                  itemBuilder: (context, index) {
                    final hit = matches[index];
                    return _ResultTile(hit: hit, onTap: () => onPick(hit));
                  },
                ),
              ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.hit, required this.onTap});

  final _SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              child: Text(
                hit.pdf.name,
                style: const TextStyle(
                  fontSize: 13,
                  color: DashboardColors.title,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Flexible, not fixed: an unbounded folder name would otherwise
            // widen the row past the panel's cap and overflow it.
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
        ),
      ),
    );
  }
}
