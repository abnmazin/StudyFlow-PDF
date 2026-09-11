# AGENTS.md — StudyFlow PDF

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
flutter analyze        # zero errors expected; ~169 info-level lints are pre-existing
```

There are **no tests** (`test/widget_test.dart` is empty). Do not attempt to run `flutter test` expecting coverage.

## Architecture (Read Before Coding)

**Mandatory pre-read** (per `.cursorrules`):
- `docs/architecture_map.md` — high-level structure, services, Firestore schema, role system
- `docs/changelog.md` — what changed, what failed, current state

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
| `university_service.dart` | Multi-tenant university folders/files, Supabase upload/download |
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

## Conventions

- **State management**: Provider only — `ChangeNotifier` + `Selector`/`select` for granular rebuilds
- **Dark mode**: Supported throughout. Light/dark slate palettes via `AppProvider.isDarkMode`
- **Glassmorphism**: Floating windows, overlays, panels use `BackdropFilter` + `ImageFilter.blur`
- **RTL**: Arabic primary. Math/code UI stays LTR via explicit `Directionality` wrapping
- **Desktop robustness**: `_studyflow_` temp PDF copies avoid `errno=32` file locks; single-instance forwarding
- **No comments in code** unless explicitly requested
- **LaTeX widgets**: Always constrain with `FittedBox` or `maxHeight` to prevent layout explosions

## Gotchas

- `.env` is listed in `pubspec.yaml` assets for `flutter_dotenv` — removing it breaks runtime key loading
- `analysis_options.yaml` suppresses `deprecated_member_use`, `invalid_use_of_protected_member` globally (needed for part-file setState access)
- `developer_dashboard_v.dart` had a shadowed duplicate `GlobalSettingsModal` — only `DeveloperDashboardView` is live (canonical `GlobalSettingsModal` is in `global_settings_modal.dart`)
- `university_hub.dart` is deprecated — replaced by `university_cloud_library_w.dart` for university users
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
