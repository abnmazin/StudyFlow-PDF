# Changelog

## 2026-05-06
- Task: PDF Mutation Sync, Annotation Shifting Fixes, and Performance Optimization.
- What changed:
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
