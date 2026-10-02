# Style — StudyFlow PDF

## Comments are the house style

This codebase documents *why*, everywhere, and that is expected — not tolerated.
A comment that says why a constant exists, which failures led to a rule, or which
other file depends on the same number is what keeps the project navigable; a
comment that repeats the code is noise. Match the density of the neighbours you
are editing, and cite `file:line` when the reason lives somewhere else.

`docs/AGENTS.md` used to say "no comments in code unless explicitly requested".
That line was stale and has been corrected: obeying it would delete the style that
makes this repository readable.

## Colour and size come from one place

- Colour: `DashboardColors` in `lib/widgets/dashboard/dashboard_palette.dart`. The
  sidebar imports it, the dashboard is built from it, and a private copy of
  `0xFF0F172A` anywhere is a defect waiting to happen.
- Anything two places must agree on gets a named constant in that same file —
  `kDashboardNavBarHeight`, `kStatCardHeight`, `kDashboardPagePadding`. Two bare
  `64`s in two files is exactly how the sidebar header and the dashboard navbar
  ended up 16px apart. That pair is fixed now: `kDashboardNavBarHeight` is read by
  all three bands that share the shell's top line — the dashboard navbar
  (`dashboard_top_bar.dart`), the sidebar header (`sidebar_w.dart`) and the viewer
  toolbar (`viewer_components/viewer_toolbar.dart`) — so none of them carries a
  private `64` any more.
- The sidebar and the dashboard stay dark in both themes, on purpose; the light
  theme belongs to the rest of the app.
- A visual choice is the user's to make: propose the value, do not invent it, and
  when the wording allows two readings, ask which one.

## RTL, which surprises people here

- The widget tree runs right-to-left (Arabic is the app locale), so a `Row` starts
  at the **right**: the first child is the rightmost, and `MainAxisAlignment.start`
  means right.
- `Flex.textDirection` decides that flex's own axis only. It does **not** hand a
  direction down to its children — a row that must read left-to-right needs the
  direction set on the row itself and on any nested row whose order matters.
- `Alignment.*` and `EdgeInsets.only` are physical. `AlignmentDirectional` and
  `EdgeInsetsDirectional` follow the reading order. Pick deliberately and say which
  one is meant.
- Do not assume which side the sidebar is on. Under RTL the first child of the
  shell's row is the right side, which is the opposite of what a "left sidebar"
  comment suggests; check before reasoning about a border or a chevron.

## Fixed-height bars holding Arabic text

A line's height is the font's metric, not the font size. The bundled Noto Naskh
Arabic reports roughly 1.71× the size while Segoe UI reports about 1.33×, so the
same 20px + 14px greeting is 62px in one face and 50px in the other. A 64px bar
leaves 2px of slack in the first case and generous room in the second. Before
shrinking a bar that holds text, or adding a line to one, measure — or say that it
was not measured.
