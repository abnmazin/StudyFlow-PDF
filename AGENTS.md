# AGENTS.md — StudyFlow PDF

Flutter desktop-first (Windows) PDF study app for one technical college: a reader
with annotation and sync, a university cloud library, and floating mini-apps.
Arabic is the primary locale, so the widget tree runs right-to-left.

This file is the law, and it is kept short on purpose. The detail lives in
`.clinerules/` (one topic per file, loaded automatically) and in `docs/AGENTS.md`
— the deep handbook for build, boot, services and gotchas, which is **not**
loaded automatically, so read it when a task touches those.

## The four rules that matter most

1. **Ask when the intent is not certain.** A wrong guess costs the user a review
   cycle and costs more tokens than the question. In this app "the header", "the
   bar" and "the main colour" each mean several things; ask once, with concrete
   options, before editing. Example — for "match the main colour": *"Do you mean
   the sidebar's own dark background (the panel that holds the files and
   folders), the blue on the first quick-action tile, or the blue used for icons
   and active labels?"*
2. **Evidence, never assertion.** Every number reported comes from a command's
   real output. Nothing counts as verified unless it was run, and "I did not
   verify this" is a correct answer, not a failure.
3. **Spend tokens like they are scarce.** No test run, no rebuild and no scratch
   file unless it can catch a real defect. For a purely visual change — colour,
   size, spacing, font, shape — write no test and do not launch the app: ask the
   user to look at it, because their eye is the only instrument that can judge it.
4. **Report short, in Arabic, in human words.** A few plain sentences: what
   changed, why it was wrong, what proves it, what is left. No code, no diffs, no
   identifiers the user does not need in order to find something.

## Never

- Never touch uncommitted work. Run `git status` first and leave the user's
  in-flight edits exactly as they are.
- Never `npx` or Node for Dart code generation. Only
  `dart run build_runner build --delete-conflicting-outputs`.
- Never introduce BLoC, Riverpod or GetX. Provider only (`ChangeNotifier`,
  `context.select`, `Selector` for granular rebuilds).
- Never invent a colour, a height or a width: the shared palette and the layout
  constants already exist. See `.clinerules/style.md`.
- Never claim a check you did not run, and never "simulate" the analyzer.

## Commands (PowerShell 5.1 — `;` separates, `&&` is a syntax error)

```powershell
git status                                     # before everything
flutter analyze --no-pub                       # 0 errors expected; ~220 known infos
flutter test test/tool_width_limits_test.dart  # one file while working
flutter test                                   # full suite; 85 tests, green 2026-09-30
flutter run -d windows                         # only when the user asks for it
```

A command here is killed at 30 seconds, so `analyze` and `test` are started as
background processes with their output redirected to a file, then polled — never
re-run after a kill. Details and the reporting shape: `.clinerules/workflow.md`.

## Where the rest lives

| Topic | File | Loaded automatically |
|---|---|---|
| Graph-first retrieval, coverage limits | `.clinerules/graphify.md` | yes |
| Routine, when to ask, token rules, reporting shape | `.clinerules/workflow.md` | yes |
| How tests are written here, when not to write one | `.clinerules/testing.md` | yes |
| Comments, palette, shared constants, RTL | `.clinerules/style.md` | yes |
| When the memory files get updated | `.clinerules/docs.md` | yes |
| Build, boot, services, Firestore, gotchas | `docs/AGENTS.md` | no — read it |
| Architecture and phase history | `docs/architecture_map.md` | no |
| What changed, what failed | `docs/changelog.md` | no |

## Orientation, so the architecture is not re-derived every task

- Boot: `lib/main.dart` → single instance on port 45678 → `.env` → Supabase →
  Firebase → `FileManagerService.init()` → `runApp`. A boot failure renders a
  diagnostic screen instead of crashing.
- State: one hub, `AppProvider` in `lib/providers/app_state.dart`.
- Storage: Isar locally (folders, PDFs, snapshots, trash, tasks), Firestore in
  the cloud (users, sessions, universities), Supabase for library files.
- Identity: a file's SHA-256 hash is the cross-device id — never a local random
  one. Reading progress is stored per (file hash + user).
- Colours and layout constants: `lib/widgets/dashboard/dashboard_palette.dart`.
- `lib/widgets/pdf_viewer_widget_w.dart` is a part file with six parts; a viewer
  edit often belongs in the right part, not the owner.

## The graph

A local, deterministic code graph lives at `graphify-out/graph.json`
(`graphify extract . --code-only`: no API key, no embeddings, every edge
`EXTRACTED`). Query it before reading more than two files for an architecture or
dependency question; confirm the finding in the file before acting on it.

Commands, the absolute path to the CLI, and the coverage limits that were earned
by testing on this repo: `.clinerules/graphify.md`. Keep it fresh with
`update .` after a pull. Never quote a node or community count as current — read
the JSON if a number is actually needed.

