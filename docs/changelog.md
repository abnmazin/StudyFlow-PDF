# Changelog

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
