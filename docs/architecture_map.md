# Architecture Map

## App Structure
- `lib/main.dart`: app bootstrap, provider setup, PDF viewer shell, floating window overlay.
- `lib/main.dart`: app bootstrap, provider setup, Supabase/Firebase initialization, PDF viewer shell, floating window overlay.
- `lib/widgets/floating_window_manager.dart`: floating window lifecycle, stacking, drag, close, and z-order management.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps with fixed-height cards for stable icon alignment.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps with top-anchored card content to keep icon alignment stable.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps with a taller tile ratio so the top-anchored layout fits without overflow.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps with constraint-aware card internals (adaptive icon/text sizing and expanded text slot) to prevent bottom overflow on narrow tiles.
- `lib/widgets/pdf_viewer_widget_w.dart`: main PDF workspace shell, now split-aware with independent primary and secondary PDF controllers.
- `lib/widgets/draggable_text_widget.dart`: editable PDF note/comment bubbles, now with image attachment upload support and in-note image previews.
- `lib/widgets/viewer_components/viewer_toolbar.dart`: responsive toolbar with horizontally scrollable action clusters for constrained widths.
- `lib/widgets/mini_apps/matrix/matrix_calculator.dart`: matrix input grid uses bracket borders and flat text cells without a Stack or per-cell blur layers.

## Mini Apps
- `lib/widgets/viewer_components/mini_calculator_widget.dart`: scientific calculator with LaTeX display and texpr-powered calculations.
- `lib/widgets/viewer_components/mini_calculator_widget.dart`: scientific calculator with LaTeX display, texpr-powered calculations, and undo support that restores the pre-result equation for quick edits.
- `lib/widgets/viewer_components/mini_calculator_widget.dart`: scientific calculator with LaTeX root-symbol fallbacks for standalone `√` and `∛` rendering compatibility.
- `lib/services/math_engine.dart`: unified mathematics engine combining texpr (symbolic & numerical), constant injection (`e`, `pi`), a UI-expression normalization filter (implicit multiplication, roots/log normalization), a nested AST formatter for readable derivatives, and equations package support for higher-degree polynomials.
- `lib/widgets/mini_apps/translator/mini_translator.dart`: translation mini app with AI and fast modes.
- `lib/widgets/mini_apps/power/power_calculator.dart`: short transmission line and 3-phase solver.
- `lib/widgets/mini_apps/matrix/matrix_calculator.dart`: matrix calculator for algebra and circuit analysis, using LTR matrix layout, compact glassmorphism cells, and bracket-style framing.

## Design Rules
- Mini apps must remain compact enough for floating windows.
- Mini app cards use fixed-height icon and text slots so multi-line titles do not shift icon alignment.
- Mini app cards are top-anchored so one-line and two-line labels share the same icon baseline.
- Mini app cards use a slightly taller grid cell ratio to preserve the top anchor and avoid bottom overflow on narrow tiles.
- Math and code-oriented UI should stay LTR where needed, even inside Arabic UI shells.
- Premium surfaces use glassmorphism, subtle borders, and dark-mode friendly contrast.
- Matrix panels use uniform rounded borders with glass accents to avoid border paint issues.
- Matrix input grids should avoid nested blur filters per cell; prefer flat cells inside a scrollable grid container.
- Equation solving in the mini calculator prefers the Python bridge when available and falls back to the local solver if Python is missing.

## State and Services
- `AppProvider`: central app state for active PDFs, split-screen mode, sessions, sync, dark mode, and sidebar/mobile UI state.
- `WindowManagerProvider`: manages floating window state and layering.
- `SupabaseStorageService`: uploads media files into Supabase Storage and returns public URLs for Firestore-backed records.
- `PdfComment`: note/comment model supports optional `attachedMediaUrl` and `mediaHeight` fields. `toJson()` / `fromJson()` handle serialization for both Isar and Firestore.
- `IsarComment`: local comment cache persists `attachedMediaUrl` and `mediaHeight`, with generated schema accessors in `isar_models.g.dart`.
- `AppProvider.endEditing()`: accepts optional `attachedMediaUrl` and `mediaHeight` from the UI layer to explicitly preserve attachments and their sizes during the final save commit.
- `AppProvider.updateComment()`: uses full `oldComment.toJson()` / `updated.toJson()` snapshots for undo-history entries so `PdfComment.fromJson()` can restore all fields — including `attachedMediaUrl` and `mediaHeight` — during Undo/Redo.
- `TranslationService`: AI and fast translation backends.

## Notes
- Matrix UI is intentionally wrapped in LTR for linear algebra readability.
- Core mathematical logic should stay isolated from presentation changes.
- Matrix input/output panels use compact 45px glass cells and premium control grouping for floating-window usage.
- Split-screen PDF view keeps the primary viewer toolbar-driven and uses a separate controller for the secondary pane.
- In split mode, the currently open PDF stays primary/left; tapping another PDF from file lists or recent-file surfaces assigns it to the secondary/right pane instead of replacing the primary selection.
- In split mode, switching folders preserves the current primary PDF and refreshes only the secondary selection for the newly opened folder when possible.
- Toolbar action clusters fall back to horizontal scrolling in split-screen and narrow layouts instead of overflowing.
- `draggable_text_widget.dart` aliases `math_expressions` as `me` to avoid symbol conflicts with Flutter widgets (`Stack`).
- Note attachment previews use `Image.network` with `loadingBuilder` and a manual "Retry" mechanism in `errorBuilder` to recover from intermittent network failures (e.g., closed connections).
- Build-shell overlays (search, text-selection, formatting toolbar, vertical slider) are anchored to the primary pane controller in split mode.
