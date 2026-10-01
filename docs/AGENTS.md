# AGENTS.md — StudyFlow PDF

> The rules live in the repository root `AGENTS.md` and in `.clinerules/` — those
> are the files an agent loads automatically. This document is the deep handbook
> they point to: build, boot, services, schema and gotchas. It is not read for you.

## What This Is

Flutter desktop-first (Windows) PDF study app. Arabic RTL primary locale. PDF viewer with annotation, real-time sync (lecturer→student), university multi-tenant cloud library, and floating mini-app windows.

**Version**: 1.1.0+3 · **SDK**: Dart ^3.10.7 · **Flutter**: 3.41.1 (CI pins 3.10.7)

## Build & Run

```bash
flutter pub get                        # always first
flutter run -d windows                 # primary target
flutter build windows                  # release build
flutter build web --release --base-href "/"  # web deploy
```

## Code Generation (Isar)

After any change to `lib/models/isar_models.dart` or other Isar-annotated files:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Never use `npx` or Node.js for Dart codegen. The generated file is `lib/models/isar_models.g.dart` (excluded from analysis).

## Verify

```bash
flutter analyze --no-pub     # zero errors expected; ~220 info-level lints pre-existing (2026-09-30)
flutter test                 # 6 files, 85 tests, all green (2026-09-30)
flutter test test/<one>_test.dart   # one file is far cheaper while iterating
```

Tests exist and they matter. `.clinerules/testing.md` says what they cover, how
they are written here, and the one case where the answer is the user's eye instead
of a test — a colour, a size or a font is checked by looking, not by asserting, so
that tokens are not spent proving something only the user can judge.

The claim that used to sit in this section — that there are no tests and that
`flutter test` should not be run — was true once and has been false for a while. It
is exactly the kind of stale sentence that costs a project its verification: do not
restore it.

## Architecture (Read Before Coding)

**Mandatory pre-read** before writing code:
- `docs/architecture_map.md` — high-level structure, services, Firestore schema, role system
- `docs/changelog.md` — what changed, what failed, current state
- `.clinerules/*.md` — the working rules (graph, routine, tests, style, memory files).
  These are the files that are actually loaded for an agent; keep rules there, not here.

### Entry Point

`lib/main.dart` — single-instance server (port 45678) → `.env` → Supabase → Firebase → `FileManagerService.init()` → `runApp`. Any boot failure renders `StartupDiagnosticApp` instead of crashing.

### State Management

**Provider only.** `AppProvider` (`lib/providers/app_state.dart`) is the central state hub. Use `context.read()`, `context.watch()`, `context.select()`. Never suggest BLoC, Riverpod, or GetX.

### Key Services (`lib/services/`)

| Service | Role |
|---------|------|
| `auth_service.dart` | `secureLogin()` — device-bound auth, blacklist check |
| `sync_service.dart` | Firestore session code sync, bidirectional annotation reconciliation |
| `file_manager_service.dart` | Isar DB wrapper (folders, PDFs, trash, tasks) — `ChangeNotifier` |
| `university_service.dart` | Multi-tenant university folders/files, Supabase upload/download, reading-progress sync |
| `library_sync_service.dart` | Per-file `syncCode` for library booklets (generate / derive / owner check) |
| `pdf_mutation_service.dart` | Add/delete PDF pages via Syncfusion isolates |
| `math_engine.dart` | Dart-native math evaluation (replaced old Python bridge) |
| `mcp_client_service.dart` | Optional 3rd AI provider — bridges to `gemini-app-mcp` (Node.js) using the user's personal Google account via browser automation, no API key. Fallback ring: `gemini → groq → mcp` |

### File Identity

**SHA-256 file hashes** are the universal cross-device identifier. Never use random local IDs for sync. Reading progress is stored per `(fileHash + userId)`.

### Database Split

- **Isar** (local): ClassFolder, PdfDocument, PdfSnapshot, TrashItem, StudyTask
- **Firestore** (cloud): users, sync_sessions, universities, university_*
- **Supabase Storage**: university-pdfs bucket (private, RLS)

### Part Files

`lib/widgets/pdf_viewer_widget_w.dart` is a part-based file split into 6 parts: `_actions`, `_print`, `_gestures`, `_style`, `_overlay`, `_dashboard`. Edits to the PDF viewer may need to go in the correct part file.

## Knowledge Graph (Graphify)

A local, deterministic code knowledge graph lives at `graphify-out/graph.json` (graphifyy v0.9.69):

```bash
graphify extract . --code-only   # rebuild locally: no API key, no embeddings (13.7s for this repo)
graphify update .                # incremental sync (run after every git pull)
graphify query "who writes reading progress to Firestore"
graphify path "app_state.dart::AppProvider" "file_manager_service.dart::FileManagerService" --undirected
graphify explain "lib/services/university_service.dart::UniversityService"
```

Current snapshot: 2309 nodes · 3021 edges · 86 communities · 100% `EXTRACTED`. Reported under `graphify-out/GRAPH_REPORT.md` (visual: `graph.html`). Cline reaches it through the `graphify` MCP server (`query_graph`, `get_node`, `get_neighbors`, `shortest_path`); agent protocol in `.clinerules/graphify.md`.

Limits (verified): Dart uses a **regex** extractor (not tree-sitter) → `part` files/mixins need manual checks; `pubspec.yaml` is not a package manifest → no Flutter dependency edges; `firestore.rules` is unparsed; generated `lib/models/isar_models.g.dart` and platform folders are excluded by `.graphifyignore`.

## Conventions

- **State management**: Provider only — `ChangeNotifier` + `Selector`/`select` for granular rebuilds
- **Dark mode**: Supported throughout. Light/dark slate palettes via `AppProvider.isDarkMode`
- **Glassmorphism**: Floating windows, overlays, panels use `BackdropFilter` + `ImageFilter.blur`
- **RTL**: Arabic primary. Math/code UI stays LTR via explicit `Directionality` wrapping
- **Desktop robustness**: `_studyflow_` temp PDF copies avoid `errno=32` file locks; single-instance forwarding
- **Comments**: the house style is a comment that explains *why* — which other file
  depends on a value, which failure produced a rule. Match the density of the
  neighbours you are editing. (This file used to say "no comments unless
  explicitly requested"; that was stale and contradicted every file in `lib/`.)
- **LaTeX widgets**: Always constrain with `FittedBox` or `maxHeight` to prevent layout explosions

## Gotchas

- `.env` is listed in `pubspec.yaml` assets for `flutter_dotenv` — removing it breaks runtime key loading
- `analysis_options.yaml` suppresses `deprecated_member_use`, `invalid_use_of_protected_member` globally (needed for part-file setState access)
- `developer_dashboard_v.dart` had a shadowed duplicate `GlobalSettingsModal` — only `DeveloperDashboardView` is live (canonical `GlobalSettingsModal` is in `global_settings_modal.dart`)
- `university_hub.dart` is deprecated — replaced by `university_cloud_library_w.dart` for university users
- Library booklets are NOT a separate sync system: `university_files.syncCode` is the same session id used by `sync_service.dart` (`sync_sessions/{code}/annotations/{fileHash}`), auto-linked in `AppProvider._autoLinkLibrarySession`. There is no download tracking — opening a file never writes a "downloaded" record
- `sync_sessions` documents are created lazily by `ensureLibrarySession` on first open, so an empty collection simply means nothing has been opened yet
- The CI workflow (`.github/workflows/deploy.yml`) deploys to GitHub Pages; Flutter version pinned to `3.10.7` in CI (may drift from local)
- `mcp_client_service.dart` needs Node.js + a Chromium browser; MCP auth expires after ~24h (re-link in Settings). It is unofficial/reverse-engineered — `gemini-app-mcp` may break if Google changes the web UI

## Docs Directory

| File | Purpose |
|------|---------|
| `docs/architecture_map.md` | Structure, services, Firestore schema, roles |
| `docs/changelog.md` | Change log with failure notes |
| `docs/MATH_ENGINE_GUIDE.md` | MathEngine API and migration notes |
| `docs/performance_and_ram.md` | RAM usage research |
| `docs/gesture_conflict.md` | pdfrx vs overlay gesture conflict (known blocker) |
| `docs/deploy_guide.md` | GitHub Pages deployment |
| `docs/PRINT_ISSUE_REPORT.md` | The printing investigation (36 KB — the deep record for its own problem) |
| `docs/TEXT_INPUT_KEYBOARD_CONFLICT_REPORT.md` | Text-input vs keyboard focus investigation |
| `docs/CHAT_SHORTCUT_CONFLICT_REPORT.md` | Chat panel shortcut conflicts |
| `docs/MATH_ENGINE_EXAMPLES.dart` | Runnable MathEngine examples (a Dart sample, not prose) |

Investigation reports are the deep record for the problem they name. Link them from
the architecture map instead of paraphrasing them into it.
