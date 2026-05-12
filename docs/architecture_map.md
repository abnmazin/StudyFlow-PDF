# Architecture Map

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

## UI Phase (Phase 3/4) — Legacy Widgets (Deprecated for university users)
- **`UniversityHub`** (`lib/widgets/university_hub.dart`): Legacy university dashboard component, replaced by `UniversityCloudLibraryWidget`.
- **`FolderViewScreen`** (`lib/widgets/university_folder_view.dart`): File listing inside a university folder. Role-adaptive: admin sees "Upload PDF" button + swipe-to-delete on files; student sees "Open" download/button only. Restores reading progress from Firestore on open.
- **`UploadPdfDialog`** (`lib/widgets/university_upload_dialog.dart`): Admin-only dialog for picking and uploading a PDF. Uses `file_picker` for file selection, shows progress during hash computation → upload → Firestore record creation.

## App Structure
- `lib/main.dart`: app bootstrap, provider setup, Supabase/Firebase initialization, PDF viewer shell, floating window overlay.
- `lib/widgets/floating_window_manager.dart`: floating window lifecycle, stacking, drag, close, and z-order management.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps with constraint-aware card internals (adaptive icon/text sizing and expanded text slot) to prevent bottom overflow on narrow tiles.
- `lib/widgets/pdf_viewer_widget_w.dart`: main PDF workspace shell, now split-aware with independent primary and secondary PDF controllers. Enforces **primary-only context** for tools (Chat, Bookmarks, Page Counter) and navigation state.
- `lib/widgets/draggable_text_widget.dart`: editable PDF note/comment bubbles, now with image attachment upload support and in-note image previews. Contains `_MathOverlayWidget` — a unified floating toolbar that adapts its content based on note type:
  - **LaTeX notes**: Shows formatting controls + image controls (if image present) + math buttons + live LaTeX preview
  - **Text notes with image**: Shows formatting controls + image controls only — NO math buttons or LaTeX preview
  - **Plain text notes**: No floating toolbar
- `lib/widgets/pdf_viewer_widget_overlay.dart`: Page overlay that renders `DraggableTextWidget` instances. Contains `onToggleLatex` callback that properly toggles isLatex ON/OFF.
- `lib/widgets/viewer_components/viewer_toolbar.dart`: responsive toolbar with horizontally scrollable action clusters. Page counter and tools are strictly bound to the **primary PDF controller**.
- `lib/widgets/sidebar_w.dart`: navigation sidebar with dual-highlighting for active (blue) and secondary (gray) documents in split-screen mode.

## Mini Apps
- `lib/widgets/viewer_components/mini_calculator_widget.dart`: scientific calculator with LaTeX display, texpr-powered calculations, and undo support.
- `lib/services/math_engine.dart`: unified mathematics engine combining texpr (symbolic & numerical), constant injection (`e`, `pi`), a UI-expression normalization filter, a nested AST formatter for readable derivatives, and equations package support for higher-degree polynomials.
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
| `sync_sessions/{sessionCode}` | Live sync sessions | Authenticated (existing) |
| `pdfs/{fileHash}/mutations` | Live page mutations | Authenticated + university check |

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
- The existing personal `ClassItem` structure remains for legacy support; new university content flows through `UniversityFolder`/`UniversityFile`.