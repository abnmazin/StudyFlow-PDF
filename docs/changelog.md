# Changelog
 
## 2026-05-11
- Task: Refined Split-Screen Context Awareness and Navigation.
- What changed:
    - **PDF Viewer Isolation** (`lib/widgets/pdf_viewer_widget_w.dart`): Fixed state leakage in `onPageChanged` where scrolling the secondary PDF would overwrite global variables (`_lastReportedPage`) and trigger primary-pane maintenance routines.
    - **Sidebar UX Polish** (`lib/widgets/sidebar_w.dart`): Added a subtle secondary highlight (muted gray) for the file currently open in the secondary pane. Added `secondaryPdfId` getter to `AppProvider` to fix the missing property error.
    - **Tool Binding Validation**: Verified and reinforced that AI Chat, Bookmarks, and Page Counter are strictly bound to the primary PDF controller and ID, preventing tool confusion in split-screen mode.
- Bug fixed: Secondary PDF interactions no longer pollute the primary document's navigation state or tool context.
- Task: Unified University Roles and Standardized Permission Checks.
- What changed:
    - **Unified Role Logic** (`lib/models/app_user.dart`): Added high-level getters (`isAdmin`, `isLecturer`, `isDeveloper`) that treat the new `admin` role as a superuser.
    - **Gated Access Unification**: Updated `GlobalSettingsModal`, `DeveloperDashboardView`, `AppProvider`, and `Session Cards` to use the new permission getters instead of hardcoded role strings.
    - **User Management Labels**: Updated `DeveloperDashboardView` to display "مشرف (آدمن)" for administrative accounts.
    - **Infrastructure Fix** (`lib/services/university_service.dart`): Refactored `downloadPdfToLocal` to save PDFs to a permanent subdirectory (`university_pdfs`) instead of temporary storage, ensuring files remain accessible after app restart.
    - **Dashboard Layout Optimization** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): Rearranged the landing page for university users to a side-by-side layout on wide screens. **Quick Actions** are now positioned below the Library, and the **"Add Task" button** (plus icon) has been restored.
    - **Bug Fix (Navigation/UI)**: Resolved an issue where the sidebar toggle button in the toolbar was using a hardcoded threshold (768px) inconsistent with the global breakpoint (600px). This caused the button to appear as a "visual-only" hamburger menu on medium screens without actually triggering the sidebar.
    - **Sidebar Enhancements**: Added a `panelLeftClose` button to the desktop toolbar when the sidebar is open, allowing users to collapse it directly from the viewer interface.
    - **UI Modernization** (`lib/widgets/university_cloud_library_w.dart`): Completely refactored the **Folder Detail View** into a **Floating Modal Panel** (650x600). Implemented Backdrop Blur, entry animations (scale/fade), and a centered fixed-size glassmorphism container.
- Bug fixed: Users with the `admin` role (assigned for university management) can now access Developer Settings and Dashboard without manually changing their role to `developer`. **Add Task** button restored.


## 2026-05-10
- Task: Optimized Mutation Sync query to remove composite index requirement.
- What changed:
    - REFACTORED: `SyncService.listenToMutations` to use server-side `.where('seqNum', isGreaterThan: ...)` filter.
    - REFACTORED: Removed explicit `descending: false` from `orderBy` to simplify query plan.
    - DOCUMENTED: Updated `architecture_map.md` to reflect that only a single-field index is now required for `mutations`.
- Bug fixed: Mutation sync now works without requiring a manual composite index in most Firestore environments.
- Failed Attempts: None.

## 2026-05-10
- Task: Diagnosed "Failed to load university data" (Firestore Index Error).
- What changed:
    - IDENTIFIED: `UniversityService.streamFolders()` and `streamFilesInFolder()` were failing due to missing composite indices.
    - DOCUMENTED: Added "Required Firestore Composite Indices" section to `architecture_map.md`.
    - INSTRUCTED: User needs to create indices for `university_folders` and `university_files` via the Firebase Console links.
- Bug fixed: once indices are deployed in Firebase, the University Library will load correctly.
- Failed Attempts: None.

## 2026-05-08
- Task: Diagnosed bidirectional mutation sync — insert_page not received.
- What changed:
    - READ A: Confirmed `_addPage` passes `'insert_page'` as action string — correct.
    - READ B: Confirmed `listenToMutations` checks `'insert_page'` — strings match exactly.
    - READ C: Confirmed log messages already present in both add/delete broadcast methods.
    - FIX 1/2/3 NOT needed — no code mismatch found.
    - ROOT CAUSE: Missing Firestore composite index on `pdfs/{fileHash}/mutations` for `seqNum`.
    - SOLUTION: Manually create Firestore composite index: Collection `mutations`, Field `seqNum` Ascending, `__name__` Ascending, scope `Collection`.
- Bug fixed: Receiver now gets Firestore documents after index creation. insert_page mutations will be delivered and applied.
- OPTIMIZATION: Removed explicit `orderBy('seqNum', descending: false)` and added server-side `.where('seqNum', isGreaterThan: ...)` to avoid composite index requirements while maintaining correct processing order.
- Failed Attempts: None.

## 2026-05-08
- Task: Full bidirectional mutation sync hardening (both lecturer + student add/delete pages sync).
- What changed:
    - AUDITED: confirmed `broadcastMutation` in `pdf_viewer_widget_actions.dart` has NO role gate (both roles broadcast unconditionally).
    - AUDITED: confirmed `listenToMutations` in `app_state.dart` (`setActivePdf` + `setSessionCode`) has NO role gate (both roles listen unconditionally).
    - Added `_appliedMutationIds` Map<String, Set<String>> — Firestore document ID-based deduplication.
    - Primary dedup: skip mutations whose `change.doc.id` was already applied (survives listener reattach).
    - Secondary dedup: skip mutations with `seqNum <= lastSeen` with diagnostic log.
    - Added page index bounds validation before applying `delete_page` or `insert_page`.
    - Reset `_lastMutationListenerHash = null` in `setActivePdf` when switching PDFs (FIX D from prior session, verified still applied).
    - `_lastProcessedSeqNum` uses direct assignment instead of `putIfAbsent` (FIX F from prior session, verified still applied).
    - `_appliedMutationIds.clear()` in `dispose()`.
- Bug fixed: Receiver now has proper dedup so concurrent mutations from two devices don't collide. Page index validation prevents corruption from out-of-sync mutations.
- NOTE: You must create a Firestore composite index in the Firebase Console: Collection `pdfs/{fileHash}/mutations`, Field `seqNum` Ascending.
- Failed Attempts: First attempt at multi-block replace failed due to SEARCH mismatch; split into smaller scoped edits.

## 2026-05-08
- Task: Fix mutation sync echo problem + add anti-echo + raw debug log.
- What changed:
    - Added `_deviceSessionId` to `SyncService` — a unique per-instance ID.
    - Added `senderId` field to `broadcastMutation` writes to Firestore.
    - Added anti-echo check in `listenToMutations`: if `senderId == _deviceSessionId`, skip execution.
    - Added `📨 [RECEIVER RAW]` debug log to see every raw Firestore document change.
    - Renamed receiver log from `[MutationSync] Received` to `🔥 [SYNC RECEIVER] New mutation detected`.
- Bug fixed: Same-device echo mutations no longer execute locally (was causing double page deletions).
- Failed Attempts: None.

## 2026-05-08
- Task: Fix page mutations not persisting after app restart (txn vs writeTxn bug).
- What changed:
    - Fixed `deletePage` and `addPage` in `app_state.dart` to use `writeTxn` instead of `txn` for persisting workingPath to Isar.
    - Isar's `txn()` is read-only — writes inside it were silently ignored, causing the modified PDF to revert to originalPath on restart.
    - Refactored to: use `txn()` only for the read, then `writeTxn()` for the write.
    - Added diagnostic debug logs for both methods.
- Bug fixed: Deleting or adding pages now survives app restart because `workingPath` and `totalPages` are actually persisted to Isar.
- Failed Attempts: None.

## 2026-05-06
- Task: PDF Mutation Sync, Annotation Shifting Fixes, and Performance Optimization.
- What changed:
    - Fixed PDF Mutation Sync by replacing the clock-skew prone timestamp filter with a robust `isFirstLoad` bypass and `limit(1)` query.
    - Fixed Multi-Device Page Sync by switching to global `fileHash` targeting instead of local Isar IDs.
    - Implemented robust timestamp filtering (`isGreaterThan: now`) in the mutation listener to prevent race conditions.
    - Forced `pdfrx` viewer rebuilds using a `ValueKey` based on the file path and last modified timestamp.
    - Fixed image zoom scaling by applying `widget.scale` to all media dimensions and constraints in `DraggableTextWidget`.
    - Resolved persistent disk caching failures by stripping dynamic query tokens from Supabase URLs for a stable `cacheKey`.
    - Fixed 0-based vs 1-based index bug in annotation shifts (Page Shift Problem).
    - Unified `app_state` deletion logic and added `shiftAnnotationsOnPageInsert`.
    - Wired up `listenToMutations` in the PDF open lifecycle (`setActivePdf`) to ensure real-time structural sync.
    - Fixed "Ghost Annotations" by routing page-deletion items through the formal trash system (`removeComment`/`removeHighlight`).
    - Added real-time sync support for inserted pages (Add Page).
    - Implemented `PdfMutationService.insertPageLocally` using Syncfusion.
    - Replaced `Image.network` with `CachedNetworkImage` for Supabase bandwidth optimization.
    - Implemented native Clipboard Image Pasting via `pasteboard` for Windows.
- Bug fixed: Annotations were misaligned after page deletion. App crashed on Windows clipboard concurrency. Supabase egress high due to lack of caching.
- Failed Attempts: Direct UI-based `deletePage` without awaiting the future led to broadcast race conditions. Fixed by awaiting results.

## 2026-05-06
- Task: Fixed Note data model to serialize and deserialize mediaUrl to/from Firestore and Isar.
- What changed:
  - Fixed image aspect ratio in notes by using `BoxFit.contain` and removing forced width.
  - Resolved state loss in View Mode by persisting `mediaHeight` to the Isar database and updating hydration mapping.
  - Fixed "disappearing new images" bug by allowing notes with empty text to be saved if they contain an image attachment.
  - Audited all save triggers to ensure media URL and height are explicitly passed to the provider.
- Bug fixed: Image distortion fixed; custom sizes now persist in view mode; image-only notes no longer self-delete.
- Failed Attempts: None.

## 2026-05-06
- Task: Fix `Stack` symbol collision in draggable note widget.
- What changed: Aliased `math_expressions` import in `draggable_text_widget.dart` and prefixed parser/evaluator usages (`me.Parser`, `me.Expression`, `me.ContextModel`, `me.EvaluationType`).
- Bug fixed: Flutter `Stack` now resolves correctly in attachment preview UI, eliminating compile-time ambiguity.
- Failed Attempts: None in this pass; a scoped import alias was sufficient.

## 2026-05-06
- Task: Finalize image attachment persistence pipeline for PDF notes.
- What changed: Regenerated Isar artifacts after adding `attachedMediaUrl` to `IsarComment`, verified generated schema/query accessors in `isar_models.g.dart`, and kept JSON compatibility for both `attachedMediaUrl` and legacy `mediaUrl` keys through file mapping/hydration.
- Bug fixed: Note image URLs now persist through local Isar cache and reload correctly after restart instead of disappearing after edit/save cycles.
- Failed Attempts: A prior interrupted build left generated output inconsistent; rerunning `dart run build_runner build --delete-conflicting-outputs` completed schema alignment.

## 2026-05-05
- Task: Preserve the primary PDF when switching folders in split mode.
- What changed: Updated `AppProvider.setActiveClass()` so folder switches in split mode keep the current primary PDF instead of auto-promoting the new folder's last active file, and let `activePdf` resolve globally while split mode is on so the left pane remains visible.
- Bug fixed: Opening a new folder no longer replaces the primary document with a file from that folder when split mode is enabled.
- Failed Attempts: Reusing the existing auto-open-last-active behavior inside `setActiveClass()` kept promoting the new folder's document to primary, so the split-mode branch now explicitly preserves the current primary and only refreshes secondary selection.

## 2026-05-05
- Task: Keep the active PDF as the primary pane in split mode.
- What changed: Updated PDF selection entry points so, when split mode is enabled, the current active PDF remains the left/primary pane and any newly selected PDF from file lists or recent-file surfaces becomes the secondary/right pane via `setSecondaryPdf()` instead of replacing the active selection.
- Bug fixed: Choosing another file while split mode is on no longer swaps out the current primary document.
- Failed Attempts: Letting `setActivePdf()` handle split-mode selection was too aggressive because it promoted the tapped file to primary; the sidebar now routes split selections explicitly.

## 2026-05-05
- Task: Stabilize mini app grid card layout and reduce calculator root-symbol rendering warnings.
- What changed: Reworked mini app card internals in `mini_apps_menu.dart` to use `LayoutBuilder`-driven compact sizing with an `Expanded` text region, preventing repeated bottom `RenderFlex` overflow on constrained tiles. Added LaTeX conversion fallbacks for `∛(` plus standalone `√`/`∛` in `mini_calculator_widget.dart`.
- Bug fixed: The recurring `RenderFlex overflowed by 11 pixels on the bottom` in mini app cards is addressed by responsive sizing, and flutter_math warnings for unknown root symbols are reduced for unicode-root inputs.
- Failed Attempts: Static top padding and fixed icon/text blocks were not robust across small tile heights; moving to constraint-aware sizing solved the overflow path.

## 2026-05-05
- Task: Master Math Engine Overhaul: Roots, Exponents, Variables, and Fractions.
- What changed: Updated calculator LaTeX fraction parsing to treat `*` as a top-level boundary, injected `e` and `pi` into evaluation variables, expanded implicit multiplication (`2x`, `)(` patterns), converted `√(...)` and `cbrt(...)` into power form, and added calculus exponent/multiplier cleanup rules in AST simplification.
- Bug fixed: `ln(e)` now evaluates reliably, root inputs avoid parser syntax failures, fraction rendering no longer swallows multiplied terms into denominators, and symbolic derivative text is cleaner for edge exponent forms.
- Failed Attempts: Direct `sqrt`/`cbrt` passthrough and narrow fraction delimiters were too brittle across parser/rendering paths, so normalization and boundary handling were centralized.

## 2026-05-05
- Task: Make symbolic derivative output print implicit multiplication and cleaner powers.
- What changed: Changed AST multiplication formatting to omit `*` in readable output, and added a small simplifier that collapses trivial `^1` and `^0` forms after AST flattening.
- Bug fixed: Derivatives now render as `2x` instead of `2*x^1` or similar noisy intermediate forms.
- Failed Attempts: Leaving multiplication as `*` was mathematically correct but too verbose for the calculator UI, so the formatter now prefers compact algebraic notation.

## 2026-05-05
- Task: Preserve operator precedence while simplifying texpr AST output in `MathEngine`.
- What changed: Wrapped each flattened `BinaryOp` in parentheses inside `_processBinaryOp()` and added an outer-parentheses cleanup pass in `_simplifyAstString()` so nested powers and subtractions stay grouped correctly.
- Bug fixed: Derivative output no longer collapses `x^(2-1)` into a misleading flat string like `x^2-1`.
- Failed Attempts: A plain string concatenation flattening step removed precedence information, so the fix now preserves grouping first and only removes fully redundant outer wrappers afterward.

## 2026-05-05
- Task: Normalize UI-friendly math symbols before sending expressions to texpr.
- What changed: Added `_normalizeForTexpr()` to convert `ln(` to `log(`, `√(` to `sqrt(`, expand `log10(x)` into `log(x)/log(10)`, and expand `cbrt(x)` into a power form before evaluation, differentiation, integration, and equation solving.
- Bug fixed: Expressions entered through the calculator UI no longer fail just because `texpr` expects a different function name or does not directly understand `√`, `log10`, or `cbrt`.
- Failed Attempts: None in this pass; the normalization was added directly at the `MathEngine` boundary so all downstream math operations share the same input format.

## 2026-05-05
- Task: Fix AST cleanup in `MathEngine` so regex capture groups resolve correctly in Dart.
- What changed: Replaced `replaceAll(RegExp(...), r'$1')` with `replaceAllMapped(...)` in `_simplifyAstString()` for `NumberLiteral`, `Variable`, and `FunctionCall` cleanup.
- Bug fixed: Derivative formatting no longer leaks literal `$1` tokens into the output when simplifying texpr AST strings.
- Failed Attempts: The previous cleanup relied on regex replacement strings behaving like backreferences; Dart treats them as plain text, so the fix now uses mapped replacements.

## 2026-05-05
- Task: Make the mini calculator Undo button return to editable equation mode after calculation errors or results.
- What changed: Snapshotted the current expression before evaluation, taught `UNDO` to restore the previous equation from the undo stack or history, and cleared the error state so the user can edit the expression immediately and press `=` again.
- Bug fixed: Users no longer need to retype the whole equation after a failed or completed calculation just to change one symbol.
- Failed Attempts: None in this pass; the change was limited to the calculator button handler and result flow.

## 2026-05-05
- Task: Fix AST parser compile error in `math_engine.dart`.
- What changed: Replaced the unsupported `String.isAlphaNumeric` check inside `_splitBinaryOp()` with an inline ASCII alphanumeric test so nested BinaryOp parsing compiles cleanly on Dart.
- Bug fixed: The derivative formatter no longer fails on the character-scan loop used to extract `BinaryOperator.*` names.
- Failed Attempts: The first pass assumed `String` had an `isAlphaNumeric` getter; Dart does not provide that API, so the fix now uses explicit `codeUnitAt()` range checks instead.

## 2026-05-05 [Major: Migration from math_expressions + PythonEquationService → texpr + equations]
- Task: Migrate calculator math engine from math_expressions/Python bridge to native Dart texpr library with equations package fallback.
- What changed:
  - Created `lib/services/math_engine.dart`: unified math engine that:
    - Uses `texpr` for LaTeX-aware expression parsing, evaluation, symbolic differentiation/integration, and equation solving
    - Falls back to `equations` package for cubic, quartic, and higher-degree polynomial solving
    - Supports complex numbers (`i`), implicit multiplication, and all standard mathematical functions
    - Provides numerical integration (Simpson's rule) and numerical differentiation
  - Rewrote `mini_calculator_widget.dart` to:
    - Remove dependency on `math_expressions` (which doesn't support complex numbers)
    - Remove dependency on `PythonEquationService` (eliminates Python runtime requirement)
    - Use `MathEngine` for all mathematical operations
    - Preserve all existing UI/UX behavior (dark mode, LaTeX display, buttons, state management)
  - Updated `pubspec.yaml`: added `texpr: ^0.1.4` and `equations: ^6.0.0`
- Benefits:
  - ✅ Self-contained .exe (no Python runtime needed)
  - ✅ True complex number support (fixes the `i` button)
  - ✅ Symbolic derivatives/integrals beyond polynomials (sin, cos, tan, log, exp, etc.)
  - ✅ Better equation solving (linear, quadratic, cubic, quartic)
  - ✅ Faster performance (Dart VM vs Python subprocess)
  - ✅ LaTeX is first-class (texpr understands LaTeX natively)
- Failed Attempts:
  - First attempt used `math_expressions.Parser` inside `MathEngine`; replaced with `texpr` which properly supports degree/radian modes and complex numbers
  - Tried to delegate `_trimNumber` and `_approximateFraction` to `MathResult` static methods; kept them local in widget for consistency

## 2026-05-05
- Task: Add a real Python/SymPy bridge for equation solving in the mini calculator.
- What changed: Added `python_equation_service.dart` to spawn Python on Windows, run SymPy in a separate process, and return structured results; wired `_calculateResult()` to use the bridge for equations containing `=` and fall back to the local solver only when Python is unavailable.
- Bug fixed: The calculator now has an actual Python-backed equation path instead of a purely local approximation.
- Failed Attempts: The first review path assumed the app already depended on `flutter_python_bridge`, but that package was not present in `pubspec.yaml`, so the integration was implemented directly with `Process.run()` for a sturdier runtime path.

## 2026-05-05
- Task: Remove matrix grid Stack and inner BackdropFilters.
- What changed: Replaced the `_buildMatrixInput` matrix grid container with a horizontal scrollable Column/Row grid and flat `TextField` cells, removing the bracket `Stack` and per-cell `BackdropFilter` layers.
- Bug fixed: The bottom row of matrix inputs no longer clips halfway, and the grid is more performant because it no longer nests blur filters in every cell.
- Failed Attempts: None in this pass; the fix was applied as a direct replacement of the offending grid block.

## 2026-05-05
- Task: Prevent bottom overflow in the mini apps grid after top anchoring the cards.
- What changed: Added a slightly taller `childAspectRatio` in `mini_apps_menu.dart` so the fixed top padding, icon slot, and text slot fit inside the grid tile.
- Bug fixed: `RenderFlex overflowed by 6.8 pixels on the bottom` in the mini apps cards.
- Failed Attempts: Keeping the card vertically centered avoided overflow but reintroduced icon drift, so the layout stayed top-anchored and the grid tile height was expanded instead.

## 2026-05-05
- Task: Re-anchor mini app cards from the top.
- What changed: Reworked `_buildAppCard` in `mini_apps_menu.dart` to use a top padding anchor, `MainAxisAlignment.start`, fixed icon/text spacing, and consistent text line height.
- Bug fixed: The Matrix Calculator card no longer shifts its icon vertically when the title wraps to two lines.
- Failed Attempts: The previous centered-column approach still allowed vertical drift between one-line and two-line labels, so it was replaced with a strict top-down layout.

## 2026-05-05
- Task: Fix mini app grid icon alignment and add subtle premium card styling.
- What changed: Reworked `_buildAppCard` in `mini_apps_menu.dart` to use fixed-height icon and text regions, centered icon placement, and glassmorphism-style border/shadow accents.
- Bug fixed: The Matrix Calculator card no longer pushes its icon upward when its title wraps to two lines.
- Failed Attempts: The first pass introduced a nested `InkWell`; it was removed immediately to keep the card interaction clean.

## 2026-05-09
- Task: Fixed Dashboard Selector rebuild logic — UniversityCloudLibraryWidget now renders instantly after migration
- What changed:
    - **`_buildDashboard` Selector** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): Added `prev.user?.role != next.user?.role` and `prev.user?.universityId != next.user?.universityId` to `shouldRebuild`. The old code only checked `prev.user?.uid != next.user?.uid` — since `uid` doesn't change after `setCurrentUser` (only `role`/`universityId` change), the Selector never fired a rebuild, leaving the dashboard frozen on the legacy view.
    - **Debug print** added to `_buildMainContentArea`: Logs `hasUniversity`, `universityId`, and `role` on every build — visible in the console.
- Bug fixed: Clicking "Setup University" now instantaneously transitions from legacy local folders to `UniversityCloudLibraryWidget`.
- Failed Attempts: None.
- `dart analyze` passes with zero warnings and zero errors.

## 2026-05-09
- Task: Fixed Admin Migration optimistic local state update
- What changed:
    - **`_migrateAdminAccount`** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): After Firestore write succeeds, now creates an optimistic `copyWith()` of `AppUser` with `role: 'admin'` and `universityId: 'southern_technical_university'`, then calls `app.setCurrentUser(updatedUser)` + `UniversityService().init(updatedUser)`. This triggers an immediate `Selector` rebuild, flipping `hasUniversity` to `true` and rendering `UniversityCloudLibraryWidget` without requiring a restart.
    - **`AppUser.copyWith`** (`lib/models/app_user.dart`): Added `copyWith()` method to create modified copies while preserving all other fields.
- Bug fixed: Clicking "Setup University" now instantly transitions the dashboard to the Cloud Library UI instead of requiring a manual app restart.
- Failed Attempts: None.
- `dart analyze` passes with zero warnings and zero errors.

## 2026-05-09
- Task: Cloud-First University Library — Dashboard Overhaul, Download Pipeline, Cloud Library UI
- What changed:
    - **New Widget** `lib/widgets/university_cloud_library_w.dart`: Full `UniversityCloudLibraryWidget` that replaces the legacy local folder grid for university users. Displays university name header, streaming folder grid, admin create/upload/delete controls, student download pipeline. `_FolderDetailScreen` (private) shows files inside a folder with download buttons and progress indicators.
    - **Download Pipeline** (`lib/services/university_service.dart`): Added `downloadPdfToLocal(UniversityFile)` — lightweight method that downloads Supabase bytes to `getApplicationDocumentsDirectory()` without inserting into Isar. The UI layer calls `FileManagerService.importAndOpenPdf()` to finalize import into Isar + open in viewer.
    - **Dashboard Overhaul** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): When `hasUniversity` is true, `UniversityCloudLibraryWidget` replaces the legacy personal folder grid (`_buildRealFolderGrid`) AND quick actions (`_buildQuickActionChips`). Announcements and To-Do list sections remain visible for all users.
    - **Import**: Added `import 'university_cloud_library_w.dart'` to `pdf_viewer_widget_w.dart`.
- Architecture decisions:
    - Cloud library is the PRIMARY view for university users — no legacy "مجلداتي" or "إجراءات سريعة" sections shown.
    - Admin/developer sees folder creation + upload controls on folder cards + upload button in folder detail.
    - Student sees download icon on each file in folder detail; download triggers the pipeline: Supabase SDK → local file → `importAndOpenPdf` → `setActivePdf`.
    - Download button shows a spinner during download and is disabled for duplicate taps.
- Failed Attempts: None.
- `dart analyze` passes with zero warnings and zero errors on all modified/new files.

## 2026-05-09
- Task: UX Fixes, Migration Script, Reading Progress Wiring, User Management Update
- What changed:
    - **Null Safety Fix** (`lib/services/university_service.dart`, `lib/widgets/university_hub.dart`): Added `isReady` getter to gracefully exit when `universityId` is missing instead of throwing. UniversityHub now silently renders nothing (not even a loading spinner) when user has no universityId — no rebuild loops.
    - **Reading Progress Wiring Instructions** (`lib/widgets/pdf_viewer_widget_w.dart`): Added import for `UniversityService`. The `FolderViewScreen` already calls `_restoreReadingProgress()` automatically on file open — core flow is wired end-to-end.
    - **Admin Migration Button** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): Added `_migrateAdminAccount()` function that creates a `universities/southern_technical_university` document and updates the current user's Firestore profile with `universityId: 'southern_technical_university'` and `role: 'admin'`. A "Setup University" button appears in the dashboard when the user is a `developer` role without a `universityId`.
    - **User Management Update** (`lib/widgets/developer_dashboard_v.dart`): Updated `_modernUserDialog` — role dropdown now has `student`/`admin` options. New users created by an admin automatically inherit the admin's `universityId`. A visual badge shows the assigned university.
- Failed Attempts: The `!` operator on `user.universityId!` caused a compile error when accessed unconditionally on a nullable — fixed with `user.universityId?.isNotEmpty == true`.
- `dart analyze` passes with zero warnings and zero errors on all modified files.

## 2026-05-08
- Task: Phase 3/4 — UI Implementation: UniversityHub, FolderViewScreen, UploadPdfDialog, Dashboard Integration
- What changed:
    - **UniversityHub** (`lib/widgets/university_hub.dart`): Stateful widget that initializes UniversityService, streams folders in real-time, displays them in a grid. Role-adaptive: admin sees "New Folder" button + delete controls on cards; student sees read-only grid. Replaces legacy "مجلداتي" section when user has a `universityId`.
    - **FolderViewScreen** (`lib/widgets/university_folder_view.dart`): File listing inside a university folder. Streams `UniversityFile`s in real-time. Role-adaptive: admin sees "Upload PDF" app bar button + swipe-to-delete on file tiles; student sees read-only file list with "Open" button. Download pipeline: checks local Isar cache → downloads from Supabase → opens via AppProvider. Restores reading progress from Firestore on open.
    - **UploadPdfDialog** (`lib/widgets/university_upload_dialog.dart`): Admin dialog using `file_picker` to select PDFs. Shows progress indicator during upload pipeline. Calls `UniversityService.uploadPdf()` for the 4-step upload process.
    - **Dashboard Integration** (`lib/widgets/pdf_viewer_widget_dashboard.dart`): `_buildMainContentArea` now checks `app.currentUser.universityId` — if present and non-empty, renders `UniversityHub` instead of the legacy personal folder grid (`_buildRealFolderGrid`). Falls back to old behavior for users without a university. Import added to `pdf_viewer_widget_w.dart`.
- Architecture design decisions:
    - UniversityHub is injected at the same position as the old "مجلداتي" section — no layout restructuring.
    - Navigation to FolderViewScreen uses standard `Navigator.push` (not a route change) to keep the dashboard as the root.
    - File download uses hash-based local cache check first (no redundant downloads).
    - Reading progress is restored silently when opening a file from a university folder (snackbar notification shown).
    - All three new widgets match the existing glassmorphism design language (dark/light mode colors, rounded borders, indigo accents).
- Failed Attempts: First folder_view had `findAll()` on Isar instead of `findFirst()` — fixed. Had trailing imports at bottom of file — moved to top. Had `cloudUpload` icon which doesn't exist in lucide_icons — replaced with `upload`. Had unnecessary `localPath` variable — refactored to null-check pattern.
- `dart analyze` passes with zero errors and zero warnings on all new/modified files.

## 2026-05-08
- Task: Phase 2 — UniversityService: Backend Services for Folder/File CRUD, Upload/Download Pipeline, Reading Progress Sync
- What changed:
    - **UniversityService** (`lib/services/university_service.dart`): Full singleton service implementing:
        - Folder CRUD: `getFolders()`, `streamFolders()`, `createFolder()`, `updateFolder()`, `deleteFolder()` — all scoped to the user's `universityId`, write operations gated by `_assertAdmin()`.
        - File listing: `getFilesInFolder()`, `streamFilesInFolder()` — Firestore queries filtered by `universityId + folderId` with real-time streaming.
        - Upload pipeline (`uploadPdf`): 4-step process — (1) SHA-256 hash computation via existing `FileHashService`, (2) dedup check against Firestore `university_files` by `fileHash`, (3) binary upload to Supabase `university-pdfs` bucket, (4) Firestore `UniversityFile` document creation with page count extraction via `pdfrx`.
        - Download pipeline (`downloadPdf`): 3-step process — (1) local Isar cache lookup by `fileHash` (reuses existing `PdfDocument` model), (2) Supabase download to `StudyFlowPdf/UniversityCache/sha256_<hash>.pdf`, (3) Isar `PdfDocument` record insertion.
        - Cache check helpers: `isFileCachedLocally()`, `getCachedPath()` — look up by `fileHash`.
        - Reading progress sync: `saveReadingProgress()`, `getReadingProgress()`, `streamReadingProgress()`, `deleteReadingProgress()` — Firestore `university_file_progress/{fileHash}_{userId}` documents with `lastPage`, `scrollTop`, `lastReadAt`, `deviceId`.
        - Utility: `deleteFile()` (soft-delete), `_formatBytes()`.
    - **architecture_map.md**: Added UniversityService to State and Services section with full description.
- Architecture design decisions:
    - Singleton pattern to match existing `FileManagerService` pattern.
    - `init(AppUser user)` must be called before any operations — enforces university scoping at the service level.
    - Role checks (`_assertAdmin()`) happen at the method level, not service level — same service handles both admin and student operations.
    - Reading progress doc path `{fileHash}_{userId}` ensures per-user isolation per Firestore RLS.
    - Uses existing `PdfDocument` Isar model for local cache — no new Isar schema needed.
- Failed Attempts: First file had `scheduler` unused import + `null` comparison warnings on `originalPath` (non-nullable String). Fixed by removing the import and simplifying the `??` coalesce chain to skip the unnecessary null check.
- No `build_runner` needed (no new Isar models).
- `dart analyze` passes with zero issues.

## 2026-05-08
- Task: Phase 1 — Multi-Tenant University Database & Security (Architecture Implementation)
- What changed:
    - **firestore.rules**: Complete rewrite with strict multi-tenant RLS for `users`, `universities`, `university_folders`, `university_files`, and `university_file_progress` collections. Helper functions for `userUniversityId()`, `userRole()`, `isAdminOfUniversity()`, `isStudentOfUniversity()`, `belongsToSameUniversity()`.
    - **supabase_setup.sql**: Created `university-pdfs` private bucket (50 MB limit, PDF only). Added RLS policies for SELECT (university members), INSERT/DELETE/UPDATE (admins only), keyed on first path segment matching user's `universityId`. Helper functions `storage.get_user_university_id()` and `storage.get_user_role()`.
    - **AppUser model** (`lib/models/app_user.dart`): Added `universityId` field (String?), refined `role` to explicitly support 'admin' | 'student'. Added convenience getters `isAdmin` and `isStudent`.
    - **UniversityFolder model** (`lib/models/university_folder.dart`): New Firestore model with `id`, `universityId`, `name`, `createdBy`, `createdAt`, `isDeleted`, `sortOrder`. Full `fromFirestore`, `toJson`, `fromJson`, `copyWith`.
    - **UniversityFile model** (`lib/models/university_file.dart`): New Firestore model with `id`, `universityId`, `folderId`, `name`, `fileHash` (SHA-256 — primary cross-device sync key), `storagePath`, `sizeBytes`, `uploadedBy`, `uploadedAt`, `totalPages`, `isDeleted`. Full serialization support.
    - **models.dart**: Added exports for new models.
    - **architecture_map.md**: Updated with new Firestore collections table, Storage bucket table, key models section, cross-device sync strategy, and multi-tenant notes.
- Architecture design decisions:
    - File identity strictly uses SHA-256 fileHash (no random local IDs) to prevent ID desync.
    - Data isolation enforced at Firestore RLS + Supabase Storage RLS, both keyed on `universityId`.
    - Admins create/upload; students read-only — enforced at both DB and Storage layers.
    - New models are pure Dart/Firestore serialization (no Isar annotations), so no `build_runner` generation needed.
    - Existing `ClassItem`/`ClassFolder` local Isar models remain for legacy personal folders; new university content flows through new models.
- Failed Attempts: None.

## 2026-05-08
- Task: Stabilize PDF mutation sync delivery between peers.
- What changed:
  - Replaced mutation broadcasts with client-side `seqNum` values while keeping `serverTimestamp` only as an audit field.
  - Reworked `listenToMutations()` to process `seqNum` in ascending order, skip replayed mutations, and delegate page changes back through `AppProvider`.
  - Added listener hash tracking in `AppProvider` so `setActivePdf()` only restarts the mutation subscription when the file hash changes.
  - Reset mutation tracking state on `SyncService.dispose()` so rejoining a session starts cleanly.
- Bug fixed: Pending `serverTimestamp` nulls no longer block first delivery, concurrent mutations are not collapsed by a `limit(1)` snapshot, and the receiver now uses the provider state machine instead of mutating files inline.
- Failed Attempts: The original listener path depended on `timestamp`-based filtering and direct file edits inside `SyncService`, which proved too fragile under pending writes and re-subscription churn.

## 2026-05-05
- Task: Prevent toolbar overflow in split-screen and narrow windows.
- What changed: Wrapped the left and right toolbar action groups in horizontal `SingleChildScrollView` containers, and kept the center section unchanged so the toolbar can shrink gracefully without RenderFlex overflow.
- Bug fixed: `RenderFlex overflowed by 61 pixels on the right` in `viewer_toolbar.dart` when the app is narrowed or opened in split-screen mode.
- Failed Attempts: The first combined patch hit stale context after the left section changed; the fix was re-applied as smaller scoped edits.

## 2026-05-06
- Task: Add Supabase storage setup for StudyFlowPDF.
- What changed: Added `supabase_flutter` to `pubspec.yaml`, initialized Supabase in `main.dart` before `runApp()`, and created `SupabaseStorageService` for uploading image/audio files to a public bucket and returning public URLs.
- Bug fixed: The app now has a dedicated storage integration path for media uploads instead of relying on manual dashboard steps only.
- Failed Attempts: None in code; the first pass used a compile-time bucket lookup, which was corrected to read `SUPABASE_BUCKET_NAME` from `.env` so the app stays configurable at runtime.

## 2026-05-06
- Task: Attach images to PDF notes.
- What changed: Added `image_picker` and wired the note/comment editor in `draggable_text_widget.dart` to pick an image from the gallery, upload it through `SupabaseStorageService`, persist the returned URL on `PdfComment`, and render an inline preview inside the note bubble.
- Bug fixed: Notes can now carry an attached image instead of being text-only, and the attachment survives edit/save cycles because it is stored with the comment model.
- Failed Attempts: None in code; the feature was wired into the existing comment bubble instead of inventing a separate notes panel so it matches the current editor flow.

## 2026-05-06
- Task: Fix Windows note image picker crash.
- What changed: Switched the note attachment picker to use `file_picker` on desktop platforms, keeping `image_picker` only as a mobile fallback. This avoids the Windows `file_selector_windows` channel failure while preserving the Supabase upload flow.
- Bug fixed: Clicking the image attach button no longer crashes the Windows desktop app when opening the gallery/file chooser.
- Failed Attempts: Using `image_picker` directly on Windows triggered the platform channel error, so the picker was moved to the already-working `file_picker` path for desktop.

## 2026-04-29
- Task: Fix split-screen compile errors in `pdf_viewer_widget_w.dart`.
- What changed: Replaced out-of-scope `showOverlays` and `controller` usages inside `build()` with valid primary-pane references (`primaryController`) and kept overlay conditions local to the main viewer shell.
- Bug fixed: Undefined identifier errors in the main widget build tree after split-screen refactor.
- Failed Attempts: None in this pass.

## 2026-04-29
- Task: Implement split-screen (side-by-side) PDF viewer.
- What changed: Added split-screen state to `AppProvider` (`isSplitMode`, `secondaryPdf`, `toggleSplitMode`, `setSecondaryPdf`) with persistence, updated `PDFViewerWidget` to render two independent `PdfViewerController` panes, and added a split toggle button in `StudyFlowToolbar`.
- Bug fixed: Prevented controller coupling by assigning a dedicated controller lifecycle to each pane and restricting editing/search overlays to the primary pane.
- Failed Attempts: A first patch for `_buildPdfViewerCore` failed due to stale context during a large replacement; the method was then patched in smaller scoped edits and revalidated.

## 2026-04-29
- Task: Repair matrix calculator UI after corrupted edit.
- What changed: Rebuilt `MatrixCalculatorWidget` cleanly, kept the math logic intact, and moved the premium matrix UI into the correct methods only.
- Bug fixed: Restored the syntax tree after stray UI fragments were introduced outside of valid widget methods.
- Failed Attempts: A previous UI patch injected layout code into the class body, which broke the file structure; the file was reconstructed from scratch to remove the corruption safely.

## 2026-04-29
- Task: Matrix bracket border paint fix.
- What changed: Replaced the non-uniform matrix bracket border with a uniform rounded border and subtle bracket accents to preserve the glassmorphism look without triggering Flutter paint assertions.
- Bug fixed: `A borderRadius can only be given on borders with uniform colors` in the matrix calculator UI.
- Failed Attempts: The first premium bracket treatment used different border colors per side, which Flutter rejected during paint; the fix now uses a uniform border plus interior accent bars.

## 2026-04-29
- Task: Premium Matrix Calculator UI overhaul.
- What changed: Refactored `MatrixCalculatorWidget` presentation only; enforced LTR for matrix pair layout, compact square-ish matrix cells, glassmorphism panels, and cleaner operation buttons.
- Bug fixed: Matrix A/B ordering now stays left-to-right for linear algebra clarity inside the Arabic app shell.
- Failed Attempts: A first pass on label translation and styling was too broad for the current file state, so the update was re-applied with tighter context and validation.

## 2026-04-29
- Task: Matrix calculator translation cleanup.
- What changed: Converted matrix UI labels, button captions, and result messages to English.
- Failed Attempts: None after the final patch; formatting and diagnostics passed.
