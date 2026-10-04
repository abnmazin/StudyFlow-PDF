# Architecture Map

## Standalone Downloader (2026-10-03)
- **A separate application, not a page of this one.** `E:\Programing\flutter\downloader`
  is a standalone C# WinForms project, 104 KB as a single portable `.exe`, with no
  installer and no runtime to fetch. It signs in, reads one Firestore document,
  downloads, verifies and starts Setup. Its own repository — this one keeps a
  single Dart package, and a nested `pubspec.yaml` confuses the tooling.
- **It does not read GitHub.** `app_config/installer` is the only place the
  installer link exists, and the downloader takes it from there. That indirection is
  the whole point: moving the file behind a private bucket later is a Firestore
  edit, not a rebuild — nobody who already has the `.exe` needs a new one.
- **The link is public today, and the map says so.** `url` currently holds the
  `browser_download_url` of a release in the public `abnmazin/StudyFlow-PDF`, so
  anyone can fetch the installer without an account. The `path` field is the
  switch: filled in, it makes `InstallerLink.FetchAsync` mint a 10-minute signed URL
  from a private bucket and ignore `url`. That branch ships unverified, because the
  bucket does not exist yet.
- **Identity is Firebase, and the derivation is copied, not re-invented.**
  `Account.EmailForUsername` is a verbatim port of `AuthService.emailForUsername`
  (`lib/services/auth_service.dart:41`). It now has three copies — that Dart
  function, `emailLocalPart` in `tools/provision_auth.mjs`, and the C# one — and
  they must stay identical or login looks for an address nobody created.
- **The publisher is one command.** `tools/publish_release.ps1` now ends by calling
  `tools/publish_installer_doc.mjs`, which finds the service account key itself and
  raises `app_config/version.latest_version` only when the version is genuinely
  higher. `-SkipDoc` exists and is documented; without the document, a release is
  invisible rather than broken.
- **Built with `csc.exe`, deliberately.** No `dotnet`, no `MSBuild.exe`, no .NET
  Framework 4.8 reference assemblies on this machine (checked 2026-10-02), so
  `build.ps1` calls the compiler Windows ships — C# 5, hence no `$"..."` and no
  `?.` in `src/`.

## In-App Update Flow (2026-10-02)
- **Two halves, one number.** `VersionCheckService.check()`
  (`lib/services/version_check_service.dart`) still owns `min_version` from
  Firestore `app_config/version` (Remote Config as fallback), but it now takes a
  `latestVersionOverride`, and the launch gate passes the newest GitHub release's
  version into it. The release repository wins when it is *higher*: it is the only
  side that can serve a file, and a `latest_version` typed into a database offers
  an update nobody can install. The comparison lives once, in `lib/utils/semver.dart`
  (`compareVersions` / `isVersionLessThan`) — the gate and the updater ask the same
  question.
- **The update is one page, and that page is the developer modal.**
  `VersionCheckGate` (`lib/widgets/version_check_gate.dart`) sits *above*
  `MaterialApp` in `main.dart`, so `showDialog` from there finds no `Navigator`
  and no `MaterialLocalizations` above it — which is why the old soft-update
  offer's «تحديث الآن» button was dead. `DeveloperModal`
  (`lib/widgets/developer_modal_w.dart`) now carries the update itself: given an
  `UpdateService` it shows the banner, the «تحديث الآن» button, and the
  download / verify / install progress **in place of that button**. A forced launch
  replaces the app with that modal and passes no `onClose`, so a new version is
  the only way out; the optional update puts the same modal over the running app,
  so a reader with an open PDF keeps it. `service == null` is `main.dart`'s
  developer panel — information, with no update UI at all.
  `lib/widgets/update_screen.dart` was deleted on 2026-10-02: the overlay it
  provided was the second of the two pages a forced launch showed.
- **Forced and optional are the same page with two temperaments.** Forced
  replaces the app and passes no `onClose`, so nothing on it can be dismissed —
  the exit is a new version. Optional lays the same modal over the running app
  and passes `onClose`, which is what draws the «تخطّي الآن» button. «تخطّي الآن»
  means *not right now*: no version number is stored, and the gate's
  `_autoOpened` already limits the offer to once per launch. A skip that hid a
  version permanently would need that number written down, and nothing asked
  for it.
- **The page says what the release changed, before anything is pressed.**
  `_buildReleaseDetails` shows the new version, the download size, and the
  GitHub release body as Markdown (`flutter_markdown`, already in `pubspec.yaml`
  and imported nowhere until this). The style sheet is built field by field
  rather than with `MarkdownStyleSheet.fromTheme`, which asserts on a theme —
  and this panel renders above `MaterialApp`. The modal adopts the `release` the
  gate hands it in `initState`; the field existed but was never read, which spent
  a second GitHub call and kept the notes off the screen until after the press.
- **Nothing installs itself.** `UpdateScreen.autoInstall` went with it, and
  `_startUpdate` is the only path into a download — it runs from the reader's
  press. The forced launch used to schedule that download one frame after the
  screen appeared, so a reader who wanted nothing got 52 MB arriving anyway and
  a launch that lost its network had no button left to press.
- **`UpdateService`** (`lib/services/update_service.dart`) reads
  `api.github.com/repos/<owner>/<repo>/releases/latest`, picks the `.exe` asset,
  downloads it to `getTemporaryDirectory()` as `StudyFlowPDF_Setup_<version>.exe`
  with progress, verifies the `sha256:` digest and `Content-Length` (hashed as a
  stream, not `readAsBytes`), then starts it detached with `/VERYSILENT
  /CLOSEAPPLICATIONS /NORESTART /SUPPRESSMSGBOXES /LOG`.
  `ERROR_ELEVATION_REQUIRED` (740) retries through `powershell Start-Process -Verb
  RunAs`. The app then calls `exit(0)`: Setup cannot replace files that are in use,
  and Inno's `[Run]` entry starts the new build.
- **The release repository is the public source repository:**
  `abnmazin/StudyFlow-PDF`, named by `kUpdateRepoOwner` / `kUpdateRepoName` /
  `kUpdateReleasesPage`. It is public (`private: false`, verified 2026-10-02), so
  the app reads `releases/latest` with no token; a token shipped inside a client
  is a token given away. `tools/publish_release.ps1` is the publisher:
  version from `pubspec.yaml`, `flutter build windows --release`,
  `ISCC /DAppVersion=<version> installer.iss`, SHA-256, then the two GitHub REST
  calls (release, then asset). `installer.iss` takes the version through that
  define and keeps `1.1.0` only as a fallback, so Add/Remove Programs cannot
  disagree with the build inside.
- **`installer.iss` upgrade behaviour:** `AppId` is a fixed GUID (otherwise Inno
  derives one from `AppName`, and a later rename installs *beside* the old build),
  `CloseApplications=yes` is what makes `/CLOSEAPPLICATIONS` work, and
  `RestartApplications=no` because Setup's own restart would race the `[Run]` entry
  into a second instance — i.e. the "another instance is running" screen.
  `CleanOldFiles` wipes `{app}` on upgrade; user data is untouched by design,
  because it lives in `<Documents>\StudyFlowPdf` (`FileManagerService.init`), not
  under `{app}`.
- Deleted: `lib/widgets/update_dialog.dart` (the dead button's dialog).

## Dashboard Floating Panels (2026-10-01)
- The three floating panels on the dashboard — the notification bell's panel
  (`dashboard_notifications.dart`), the search results (`dashboard_search.dart`)
  and the task row's 3-dots menu (`dashboard_tasks_schedule.dart`) — all open
  through `OverlayPortal.overlayChildLayoutBuilder` and place themselves with a
  `Positioned` computed from `OverlayChildLayoutInfo`. There is **no
  `CompositedTransformTarget`/`Follower` anywhere in the dashboard**: the SDK
  forbids a follower between an `OverlayPortal` and its `Overlay`, and that is what
  crashed the bell's panel through a `Tooltip`. Each panel keeps a private
  `_geometry(info)` helper (pure, no `setState`) — the single place its placement
  rule lives.
- The dashboard page (`dashboard_page.dart`) owns one `ScrollController` shared by
  its `Scrollbar` and its `CustomScrollView`. They must share it: a `Scrollbar`
  with no controller takes the route's `PrimaryScrollController` while a
  `CustomScrollView` on Windows (`shouldInherit == false`) takes its own, and two
  different positions is the "has no `ScrollPosition` attached" assert.

## Knowledge Graph Tooling (2026-09-27)
- **Graphify** (`graphifyy` v0.9.69) builds a local, deterministic code graph at `graphify-out/graph.json` — no vector DB, no embeddings, no API key for the code path. Rebuilt **2026-10-02**: **3354 nodes / 4339 edges / 143 communities**, from commit `bb67018` plus the in-app updater work. (The first snapshot, 2026-09-27 from `001b0cd0`, was 2309 / 3021 / 86 in 13.7s — the numbers move, so read the JSON when a count matters.)
- Edge vocabulary present in this repo: `defines` (1963), `references` (442), `imports` (439), `inherits` (93), `contains` (41), `configures` (11), `exports` (9), `extends` (8), `imports_from` (6), `mixes_in` (4), `reads_from` (2), `implements` (1).
- Community hubs (navigation entry points): `app_state.dart` (242 nodes), `pdf_viewer_widget_w.dart` (112), `viewer_right_panel.dart` (108), `isar_models.dart` (89), `file_manager_service.dart` (65), `sync_service.dart` (62).
- Cline integration: `graphify` MCP server (stdio) exposing 10 tools (`query_graph`, `get_node`, `get_neighbors`, `get_community`, `god_nodes`, `graph_stats`, `shortest_path` auto-approved; `list_prs`, `get_pr_impact`, `triage_prs` not); agent protocol in `.clinerules/graphify.md`, which is loaded automatically, plus the root `AGENTS.md`.
- A graph-derived finding worth noting: `explain` shows `UniversityService` still referenced by `university_hub.dart` (L38) even though that file is documented here as deprecated — the widget is still wired into the app.
- Coverage caveats: Dart extraction is **regex-based**, not tree-sitter, so `part`/`part of` relationships (the 6 viewer parts) and mixin/extension edges are partial; `pubspec.yaml` and `firestore.rules` are outside the graph — treat the tables below as the source of truth for Firestore/RLS.

## UX Fixes & Migration (Phase 3/4 Extension)
- **`_migrateAdminAccount()`** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): Temporary function that creates a `universities/southern_technical_university` Firestore document and updates the current user's profile with `universityId` and `role: 'admin'`. Triggered by a "Setup University" button visible only to `developer`-role users without a `universityId`.
- **Dashboard Layout Optimization** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): Rearranged the landing page for university users to a side-by-side layout on wide screens. **Quick Actions** are now positioned below the Library, and the **"Add Task" button** (plus icon) has been restored to the "مهام اليوم" section.
- **UI Modernization** (`lib/widgets/university_cloud_library_w.dart`): Completely refactored the **Folder Detail View** with a "Developer Dashboard" aesthetic. Implemented glassmorphism app bars, midnight-blue color palettes, and premium file cards with metadata and integrated progress indicators.
- Bug fixed: Users with the `admin` role (assigned for university management) can now access Developer Settings and Dashboard without manually changing their role to `developer`. **Add Task** button restored.
- **`UniversityService.isReady`**: Added graceful getter check. If user has no `universityId`, the service exits silently — preventing null crashes and rebuild loops.
- **User Management Dialog Update** (`lib/widgets/developer_dashboard_v.dart`): `_modernUserDialog` now includes a `Role` dropdown (`student`/`admin`) and auto-assigns the creating admin's `universityId` to new user documents. Shows a university badge in the dialog.
- **`FolderViewScreen`**: Already calls `_restoreReadingProgress()` on file open from university hub — reading progress is fully wired.

## Cloud-First University Library (Phase 4)
- **`UniversityCloudLibraryWidget`** (`lib/widgets/university_cloud_library_w.dart`): **New primary dashboard component** for all university users. Displays "المكتبة الجامعية" header with university name, streaming folder grid (`streamFolders()`), admin create/upload/delete controls, and student download pipeline. Fully replaces the legacy local folder grid for university-tied users.
- **_FolderDetailScreen** (private, same file): Modernized folder detail as a **Floating Modal Panel** (650x600) with backdrop blur and glassmorphism. Lists files with metadata and integrated download/open pipeline. Features entry/exit animations (scale & fade).
- **Download method** (`UniversityService.downloadPdfToLocal`): Lightweight Supabase-to-disk download, saved to `getApplicationDocumentsDirectory` without Isar insertion. Import delegation to `FileManagerService` prevents file duplication.
- **Dashboard integration** (`pdf_viewer_widget_dashboard.dart`): `hasUniversity` check now injects `UniversityCloudLibraryWidget`. On desktop/wide screens, it uses a **Side-by-Side Layout**:
    - **Right (Flex 5)**: University Cloud Library followed by **Quick Actions** (Merge, Translation, etc.) with tight spacing.
    - **Left (Flex 2)**: Important Announcements & Daily Tasks (with **Add Task** button restored).
    - This ensures high-value information and tools are visible above the fold without excessive scrolling. Falls back to a vertical Column on mobile/tablet.

## Contextual Folder Announcements (2026-09-29)
- **Behaviour**: the two tabs in the sidebar's explorer row govern which list is on screen — "المكتبة الجامعية" (the folder chips from `CollegeCollectionWidget`, in `folderStyle` mode) or "الملفات المحلية" (the local class tree). Tapping a folder under "المكتبة الجامعية" swaps the main content area from the dashboard to that folder's announcements; tapping a file inside it swaps to the file viewer, and from there clicking the folder again in the sidebar releases the reader and brings the announcements back (the viewer's X returns to the dashboard instead, so it releases the folder too); collapsing the folder (or the header's back button) returns to the dashboard. Folders under "الملفات المحلية" are untouched — that tree is a different widget and never calls into this. Since the tabs are exclusive, the announcement entry points are off screen while the local tab is selected, and the two lists keep their state across switches (`maintainState`).
- **`FolderAnnouncementsView`** (`lib/widgets/announcements/folder_announcements_view.dart`): prop-driven page in the slot `_buildNoFilePlaceholder` leaves empty while no PDF is open. Four body states that must stay distinct: loading (spinner), failed read ("تعذّر تحميل الإعلانات" + retry), empty folder, and the list. A note's `title` and `body` are each optional — a photo-only post skips both. **Picture notes (2026-10-02)**: a note that carries a picture is not drawn in a bubble — `_AnnouncementBubble` drops its surface and its padding when `hasImage` — and `_AnnouncementImage` draws the picture under the prose at its own aspect ratio, capped at `maxHeight` 420, with `BoxFit.contain` and a retry control on failure; a tap on it opens `image_lightbox.dart` (`showImageLightbox` → `ImageLightboxDialog`), a black full-screen `InteractiveViewer` at 100%–600% with wheel and pinch zoom, «−»/«+»/reset against a percentage readout, and a close button or `Esc` to leave. The shared `imageCacheKey` in that file keeps one picture filed and fetched once for both the note and the viewer. It reads no provider, which is what keeps it pumpable in a test with no Isar and no Firebase.
- **`AnnouncementComposer`** (`lib/widgets/announcements/announcement_composer.dart`): the publish bar. Always expanded — one message field, an attach button and a send button — with a chosen picture previewed above it; the title field is gone from the channel UI, so the empty string is what a published note carries for it. Rendered only for staff, and it sits *under* the list, closing the page rather than floating over it. The attach control uploads through `pickAndUploadImage` (`lib/utils/image_upload_helper.dart`: `FilePicker` on desktop / `ImagePicker` on mobile, then `SupabaseStorageService`), and the result is previewed as a thumbnail whose tap removes it; `pickImage` is an injectable field so a widget test can answer without a native dialog. It applies `FolderAnnouncement.validationMessage` itself so a rejected draft never reaches the network, and a failed upload is reported rather than published as a note pointing at nothing.
- **State** (`lib/providers/app_state.dart`): `announcementsFolder` + `folderAnnouncements`/`isAnnouncementsLoaded`/`isAnnouncementsFailed`/`isPublishingAnnouncement`, with `canPublishAnnouncement` (`AppUser.isLecturer`) and `canModerateAnnouncements` (`AppUser.isAdmin`). One `snapshots()` subscription at a time, opened by `showFolderAnnouncements` and cancelled by `closeFolderAnnouncements` — the page is rebuilt on every provider notification, so subscribing in a build would re-subscribe per frame.
- **`FolderAnnouncementService`** (`lib/services/folder_announcement_service.dart`): `watchAnnouncements` / `publish` / `delete` on `university_folders/{folderId}/announcements`. `_assertCanPublish` turns a denied write into an Arabic sentence; the rules remain the boundary.
- **Date label** (`lib/utils/relative_date.dart`): `formatRelativeDate` reads `اليوم 2:30 م` / `أمس 9:05 ص` / `منذ 5 أيام` / `20/8/2026`. The clock is `formatClock` — 12-hour with an Arabic meridiem, no leading zero on the hour, and `12` for both midnight and noon.
- **Gotcha**: `UnsupportedError('x').toString()` is `"Unsupported operation: x"` and `ArgumentError('x').toString()` is `"Invalid argument(s): x"` — the message must be read off the object, not trimmed off the string.
## UI Phase (Phase 3/4) — Legacy Widgets (Deprecated for university users)
- **`UniversityHub`** (`lib/widgets/university_hub.dart`): Legacy university dashboard component, replaced by `UniversityCloudLibraryWidget`.
- **`FolderViewScreen`** (`lib/widgets/university_folder_view.dart`): File listing inside a university folder. Role-adaptive: admin sees "Upload PDF" button + swipe-to-delete on files; student sees "Open" download/button only. Restores reading progress from Firestore on open.
- **`UploadPdfDialog`** (`lib/widgets/university_upload_dialog.dart`): Admin-only dialog for picking and uploading a PDF. Uses `file_picker` for file selection, shows progress during hash computation → upload → Firestore record creation.

## App Structure
- `lib/main.dart`: app bootstrap, provider setup, Supabase/Firebase initialization, PDF viewer shell, floating window overlay.
- `lib/widgets/floating_window_manager.dart`: floating window lifecycle, stacking, drag, close, and z-order management.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps with constraint-aware card internals (adaptive icon/text sizing and expanded text slot) to prevent bottom overflow on narrow tiles.
- `lib/widgets/pdf_viewer_widget_w.dart`: main PDF workspace shell, now split-aware with independent primary and secondary PDF controllers. Enforces **primary-only context** for tools (Chat, Bookmarks, Page Counter) and navigation state.
- `lib/widgets/developer_modal_w.dart`: developer modal with diagnostics and version info.
- `lib/widgets/developer_dashboard_v.dart`: admin control panel — user management, device blacklisting, session/master bundle management, global stats. Contains `DeveloperDashboardView` only (legacy `GlobalSettingsModal` duplicate was removed).
- `lib/widgets/global_settings_modal.dart`: settings panel — master bundle join, version controls, logout. Canonical `GlobalSettingsModal`.
- `lib/widgets/draggable_text_widget.dart`: editable PDF note/comment bubbles, now with image attachment upload support and in-note image previews.
  - **LaTeX notes**: Shows formatting controls + image controls (if image present) + math buttons + live LaTeX preview
  - **Text notes with image**: Shows formatting controls + image controls only — NO math buttons or LaTeX preview
  - **Plain text notes**: No floating toolbar
- `lib/widgets/pdf_viewer_widget_overlay.dart`: Page overlay that renders `DraggableTextWidget` instances. Contains `onToggleLatex` callback that properly toggles isLatex ON/OFF.
- `lib/widgets/viewer_components/viewer_toolbar.dart`: responsive top toolbar with horizontally scrollable action clusters. Contains Hand, Select, and a **ToolSelectorButton** that toggles the floating `DrawingToolbar` (popup menu replaced). Page counter and tools are strictly bound to the **primary PDF controller**.
- `lib/widgets/viewer_components/drawing_toolbar.dart`: Floating bottom toolbar (toggleable) with horizontal scroll single-row layout (`SingleChildScrollView` + `Row(mainAxisSize: MainAxisSize.min)`). Contains tool chips (Pen, Highlight, Eraser, Arrow, Rectangle, Circle), stroke width slider, color picker, fill toggle, and eraser actions. Visibility governed by `_floatingToolbarSelectedTool` state in `pdf_viewer_widget_w.dart`.
- `lib/widgets/sidebar_w.dart`: navigation sidebar with dual-highlighting for active (blue) and secondary (gray) documents in split-screen mode. Its explorer is **two tabs in one row** — "المكتبة الجامعية" and "الملفات المحلية" — governed by a single `_ExplorerTab` field, so only one of the two lists is on screen at a time (they used to be two stacked collapsible sections, and the chevrons went with them). The selected word is white (`scheme.onSurface` in light mode, where white on the sidebar would vanish) and both words share font and size, so colour alone marks the selection. Tapping the selected tab does nothing; the "add local folder" button renders only on the local tab, its own action.

## Mini Apps
- `lib/widgets/viewer_components/mini_calculator_widget.dart`: scientific calculator with LaTeX display, texpr-powered calculations, and undo support.
- `lib/services/math_engine.dart`: unified mathematics engine combining texpr (symbolic & numerical), constant injection (`e`, `pi`), a UI-expression normalization filter, a nested AST formatter for readable derivatives, and equations package support for higher-degree polynomials.
- `lib/services/mcp_client_service.dart`: MCP bridge to `gemini-app-mcp` (Node.js MCP server). Third AI provider (`'mcp'`) driving the user's personal Gemini web app via browser automation — no API key. Spawns `npx gemini-app-mcp` child process, JSON-RPC 2.0 over stdio, session continuity, watchdog auto-restart. API: `start()`, `stop()`, `askQuestion()`, `getHealth()`, `setupAuth()`, `resetConversation()`, `isNodeAvailable`. AI fallback ring: `gemini → groq → mcp`.
- `lib/widgets/mini_apps/translator/mini_translator.dart`: translation mini app with AI and fast modes.
- `lib/widgets/mini_apps/power/power_calculator.dart`: short transmission line and 3-phase solver.
- `lib/widgets/mini_apps/matrix/matrix_calculator.dart`: matrix calculator for algebra and circuit analysis, using LTR matrix layout, compact glassmorphism cells, and bracket-style framing.

## Design Rules
- Mini apps must remain compact enough for floating windows.
- Math and code-oriented UI should stay LTR where needed, even inside Arabic UI shells.
- Premium surfaces use glassmorphism, subtle borders, and dark-mode friendly contrast.
- Equation solving in the mini calculator prefers the Python bridge when available and falls back to the local solver if Python is missing.

## State and Services
- `AppProvider`: central app state for active PDFs, split-screen mode, sessions, sync, dark mode, and sidebar/mobile UI state. Mutation listener registration now only restarts when the tracked file hash changes.
- `WindowManagerProvider`: manages floating window state and layering.
- `SupabaseStorageService`: uploads media files into Supabase Storage and returns public URLs for Firestore-backed records.
- **`UniversityService`** (NEW): Singleton service for all multi-tenant university backend operations — folder CRUD (scoped to `universityId`, admin-gated for writes), file upload pipeline (hash → dedup → Supabase upload → Firestore record), download pipeline (hash-based local Isar cache → Supabase download → local caching), and reading progress sync (Firestore `university_file_progress/{fileHash}_{userId}`).
- `PdfMutationService`: PDF Mutation Sync System (Syncfusion + Event-driven) for structural PDF modifications (Add/Delete pages).
- `SyncService`: broadcasts PDF mutations with client-side `seqNum` plus server timestamp for audit trail; sequences mutation delivery by `seqNum`.
- `TranslationService`: AI and fast translation backends.
- `PdfComment`: note/comment model supports optional `attachedMediaUrl` and `mediaHeight` fields.
- `IsarComment`: local comment cache persists `attachedMediaUrl` and `mediaHeight`, with generated schema accessors in `isar_models.g.dart`.

## Database & Sync Architecture

### Firestore Collections
| Collection | Purpose | Security |
|---|---|---|
| `users/{userId}` | User profiles with role + universityId | Self-only read/write |
| `universities/{universityId}` | University metadata + admin list | Members read, admins write |
| `university_folders/{folderId}` | Folders within a university | University isolation via RLS |
| `university_files/{fileId}` | PDF files within a folder | University isolation via RLS |
| `university_files/{fileId}/mutations/{mutationId}` | Page add/delete mutations | Authenticated + university check |
| `university_file_progress/{progressId}` | Per-user reading progress | Self-only read/write |
| `university_folders/{folderId}/announcements/{announcementId}` | Notes a professor posts to one library folder. Read by any signed-in user; written by `lecturer`/`admin`/`developer`; deleted by a manager, or by the author. `title` / `body` / `imageUrl` may each be empty as long as one of them is not. Served by the default single-field index (`orderBy createdAt desc`) — no composite index needed | Rules section 19 |
| `sync_sessions/{sessionCode}` | Live sync sessions | Authenticated (existing) |
| `timetable_entries/{entryId}` | Shared weekly timetable: one row per recurring lecture | Any signed-in user reads; admins write (delete allowed, see note) |
| `dashboard_quotes/{quoteId}` | The quotations the dashboard's quote panel rotates through, one row per sentence. `text` (≤280), `author` (≤80, required — an unattributed aphorism reads as the app's own claim), `pinned`, `updatedBy`, `createdAt`, `updatedAt`. Read by any signed-in user, written by an admin. "Only one is pinned" is enforced by `QuoteService.setPinned`'s write batch, **not** by the rules — a rule cannot ask whether any *other* document is pinned. Served by the default single-field index (`orderBy createdAt`) — no composite index needed | Rules section 20 |
| `pdfs/{fileHash}/mutations` | Live page mutations | Authenticated + university check |
| `app_config/installer` | Where the installer is, and the hash it must be: `version`, `url`, `path`, `pageUrl`, `sha256`, `size`, `notes`, `updatedAt`. Written by `tools/publish_installer_doc.mjs`, read by the standalone downloader (`E:\Programing\flutter\downloader`). `path` empty means the link is the public GitHub asset | Rules section 13 — any signed-in user reads, admins write |
| `app_config/tutorial` | The shared dashboard tutorial link: `youtube_url`, `updatedAt`, `updatedBy`. The dashboard reads it for every signed-in user; the global settings panel lets admins replace or clear it. | Rules section 13 — any signed-in user reads, admins write |

### Required Firestore Composite Indices
| Collection | Fields | Purpose |
|---|---|---|
| `university_folders` | `universityId` ASC, `isDeleted` ASC, `sortOrder` ASC | Dashboard folder listing |
| `university_files` | `universityId` ASC, `folderId` ASC, `isDeleted` ASC, `uploadedAt` ASC | Folder file listing |
| `pdfs/{fileHash}/mutations` | `seqNum` ASC | Real-time page sync (Single-field index only) |

### Supabase Storage Buckets
| Bucket | Visibility | Purpose |
|---|---|---|
| `university-pdfs` | Private (RLS) | University PDF file storage, path: `{universityId}/folders/{folderId}/{filename}` |

### Unified Role System (NEW)
- **Role Hierarchy**:
  - `admin` / `developer`: Top-level Superuser role. Has access to Developer Dashboard, University Management, and Lecturer tools.
  - `lecturer`: Teacher role. Access to Classroom Sync and Master Bundle creation.
  - `student` / `member`: End-user role. Read-only access to university libraries.
- **Implementation**: Managed via `AppUser` getters (`isAdmin`, `isLecturer`, `isDeveloper`, `isStudent`) to bridge legacy role names with the unified system.

### Key Models
- `AppUser`: uid, username, displayName, role (admin|lecturer|student), hardwareId, universityId, isBanned
- `UniversityFolder`: id, universityId, name, createdBy, createdAt, isDeleted, sortOrder
- `UniversityFile`: id, universityId, folderId, name, fileHash (SHA-256), storagePath, sizeBytes, uploadedBy, uploadedAt, totalPages, isDeleted
- `TimetableEntry`: id, title, room, weekday (1..7, numbered as `DateTime` numbers them), startMinutes, endMinutes, updatedBy — one shared weekly table, authored by admins from the dashboard's schedule card and read by every signed-in user
- `DashboardQuote`: id, text, author, pinned, updatedBy — one sentence of the dashboard's rotating quote panel, shared for the same reason the timetable is: an admin writes the list once and every signed-in device reads it. `pinned` ends the rotation and holds that one sentence until it is taken down, and only one quote may be pinned — a batch in `QuoteService.setPinned`, not a field and not a rule. `DashboardQuote.validationMessage` is the single wording for both the editor and the service, and the 280/80 ceilings are mirrored in rules section 20
- `FolderAnnouncement`: id, title, body, imageUrl, authorName, authorUid, createdAt — one professor's note on one university-library folder, at `university_folders/{folderId}/announcements/{id}`. `authorName` is snapshotted at write time so a profile rename does not rewrite history and a deleted profile does not blank the author; `authorUid` is what the rules compare against for a lecturer deleting their own. `imageUrl` is an optional public Supabase Storage URL (`maxImageUrlLength` 512) — the bytes stay in the bucket, because a Firestore document caps at 1 MiB. Validation lives in `FolderAnnouncement.validationMessage` and is applied by both the composer and `FolderAnnouncementService`: `title` ≤120, `body` ≤2000, `imageUrl` ≤512, and at least one of the three non-empty — a photo-only note is valid, an empty draft is not. The rule on `create` in section 19 mirrors all four tests. `displayTitle` names a note whose title is empty (its first body line, or «إعلان مصوّر»), which is what the delete dialog uses
- `PdfItem`: Local Isar model with fileHash for cross-device matching
- `ClassFolder`: Local Isar model for personal folder organization

### Cross-Device Sync Strategy
- **File identity**: SHA-256 fileHash is the universal identifier — no random local IDs
- **Reading progress**: Stored per `(fileHash + userId)` in `university_file_progress` collection
- **Page mutations**: Scoped under `university_files/{fileHash}/mutations` with client-side `seqNum` for ordering
- **Local cache**: Files downloaded to device are looked up by fileHash in local Isar DB
- **Split-Screen Isolation**: Only the **Primary PDF** (left pane) affects global viewer state (`_lastReportedPage`), AI chat context, and navigation tools. The **Secondary PDF** (right pane) is for reference only, though its scroll position is persisted.

## Notes
- Multi-tenant isolation is enforced at two levels: Firestore RLS (document access) and Supabase Storage RLS (file access), both keyed on `universityId`.
- Admins create folders/upload files; students have read-only access to their university's content.
- The shared timetable (`timetable_entries`) is deliberately **not** scoped per university, college, or stage: `AppUser` carries those fields but fills them inconsistently across the login paths, and a schedule that silently shows nothing because one `stage` string does not match is a worse failure than one table everybody reads. Consequence worth knowing: every student sees the table, whichever university they belong to.
- `timetable_entries` allows admin `delete`, unlike `announcements` (section 17 of the rules, delete `false`). The reason is the editor: the service exposes `deleteEntry`, and an append-only table would leave a mistyped lecture impossible to correct.
- The existing personal `ClassItem` structure remains for legacy support; new university content flows through `UniversityFolder`/`UniversityFile`.