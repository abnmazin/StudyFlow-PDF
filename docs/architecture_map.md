# Architecture Map

## App Structure
- `lib/main.dart`: app bootstrap, provider setup, PDF viewer shell, floating window overlay.
- `lib/widgets/floating_window_manager.dart`: floating window lifecycle, stacking, drag, close, and z-order management.
- `lib/widgets/mini_apps_menu.dart`: launcher grid for mini apps.
- `lib/widgets/pdf_viewer_widget_w.dart`: main PDF workspace shell, now split-aware with independent primary and secondary PDF controllers.

## Mini Apps
- `lib/widgets/viewer_components/mini_calculator_widget.dart`: scientific calculator with LaTeX display.
- `lib/widgets/mini_apps/translator/mini_translator.dart`: translation mini app with AI and fast modes.
- `lib/widgets/mini_apps/power/power_calculator.dart`: short transmission line and 3-phase solver.
- `lib/widgets/mini_apps/matrix/matrix_calculator.dart`: matrix calculator for algebra and circuit analysis, using LTR matrix layout, compact glassmorphism cells, and bracket-style framing.

## Design Rules
- Mini apps must remain compact enough for floating windows.
- Math and code-oriented UI should stay LTR where needed, even inside Arabic UI shells.
- Premium surfaces use glassmorphism, subtle borders, and dark-mode friendly contrast.
- Matrix panels use uniform rounded borders with glass accents to avoid border paint issues.

## State and Services
- `AppProvider`: central app state for active PDFs, split-screen mode, sessions, sync, dark mode, and sidebar/mobile UI state.
- `WindowManagerProvider`: manages floating window state and layering.
- `TranslationService`: AI and fast translation backends.

## Notes
- Matrix UI is intentionally wrapped in LTR for linear algebra readability.
- Core mathematical logic should stay isolated from presentation changes.
- Matrix input/output panels use compact 45px glass cells and premium control grouping for floating-window usage.
- Split-screen PDF view keeps the primary viewer toolbar-driven and uses a separate controller for the secondary pane.
- Build-shell overlays (search, text-selection, formatting toolbar, vertical slider) are anchored to the primary pane controller in split mode.
