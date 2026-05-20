# Changelog

## [2026-05-17] Toolbar Redesign: ToolSelectorButton + Floating DrawingToolbar

### Changes Made

#### `lib/widgets/viewer_components/viewer_toolbar.dart`
- **Added** `floatingToolbarSelectedTool` (ToolType?) and `onFloatingToolbarToggle` (ValueChanged<ToolType?>?) parameters to `StudyFlowToolbar`
- **Added** static helper `StudyFlowToolbar.iconForTool(ToolType)` mapping each tool to its Lucide icon
- **Replaced** the popup menu (`_showToolSelector` / `_buildToolMenuItem`) with a toggle `ToolSelectorButton`:
  - Icon changes dynamically to reflect the currently selected tool in the floating toolbar
  - Highlights blue when active
  - First click → shows floating toolbar + activates Pen tool
  - Second click → hides floating toolbar + resets to Hand (cursor) tool
- **Removed** unused `_toolSelectorKey` GlobalKey, `_showToolSelector()`, `_buildToolMenuItem()`, `isSelectedShapeTool`, `isSelectedHighlightTool` local variables, and `package:flutter/rendering.dart` import

#### `lib/widgets/pdf_viewer_widget_w.dart`
- **Added** `_floatingToolbarSelectedTool` (ToolType?) state variable — null = hidden, non-null = visible with that tool
- **Passed** new params (`floatingToolbarSelectedTool`, `onFloatingToolbarToggle`) to `StudyFlowToolbar`
- **Replaced** `_shouldShowDrawingToolbar(panelTool)` condition with `_floatingToolbarSelectedTool != null` for `DrawingToolbar` visibility
- **Updated** `DrawingToolbar.onToolChanged` callback to also sync `_floatingToolbarSelectedTool`
- **Removed** legacy `_shouldShowDrawingToolbar()` method

#### `lib/widgets/viewer_components/drawing_toolbar.dart`
- **No changes needed** — already uses `SingleChildScrollView` + `Row(mainAxisSize: MainAxisSize.min)` for horizontal scroll

### Architecture
- Top toolbar now shows: sidebar toggle, close PDF, split mode, page counter, hand tool, select tool, **ToolSelectorButton**, zoom controls, search, bookmarks, settings, sync
- Floating `DrawingToolbar` appears at bottom-center when `ToolSelectorButton` is active
- `TextFormattingToolbar` remains unchanged for text editing
- Dark mode supported throughout

### Behavior
- **ToolSelectorButton click (hidden)**: Shows floating toolbar with Pen tool, activates Pen
- **ToolSelectorButton click (visible)**: Hides floating toolbar, resets to Hand tool
- **Tool chip selected in DrawingToolbar**: Updates ToolSelectorButton icon + activates tool
- **No regression** on keyboard focus fix, PDF navigation, or text editing

---

## [2026-05-13] Resolved: Keyboard focus conflict during text editing — prevented Space/Arrows from PDF viewer while editing

### Root Cause
During text editing, the PDF viewer was consuming Space key (page scroll) and Arrow keys (navigation), interfering with normal text input. Additionally, blocking all keys broke TextField functionality entirely.

### Solution
- **`lib/widgets/draggable_text_widget.dart`**: Already correct — `_focusNode` initializes cleanly; `addListener` triggers `setKeyboardLock` when TextField gains focus
- **`lib/widgets/pdf_viewer_widget_w.dart`**: 
  - `Focus.onKeyEvent` now blocks **Space key only** (checked with `LogicalKeyboardKey.space`) when `isKeyboardLocked` is true, preventing PDF page scrolling
  - `enableKeyboardNavigation` includes `!app.isKeyboardLocked` condition to disable Arrow key navigation when editing

### Result
When editing a text annotation:
- Arrow keys, Backspace, Delete, and all other keys work normally in TextField
- Space key is blocked from scrolling the PDF (still not typed in TextField — separate issue to solve via `pdfrx` config)
- Arrow navigation in PDF is disabled via `enableKeyboardNavigation=false`

---

## [2026-05-12] Corrected: Image notes showing LaTeX math toolbar — switched to proper toolbar (TextFormattingToolbar)

### Root Cause
Two floating toolbars exist when editing notes:
1. **`TextFormattingToolbar`** (`pdf_viewer_widget_w.dart` lines 1818-1983) — appears at bottom of screen when text tool is active. Already had `hasAttachedImage`, `onIncreaseImageSize`, `onDecreaseImageSize`, `onRemoveImage` parameters defined but NOT wired.
2. **`_MathOverlayWidget`** (`draggable_text_widget.dart`) — appears as overlay on the note. Should ONLY handle LaTeX math editing.

The bug was that `_MathOverlayWidget` was incorrectly triggered for notes with images (`widget.isLatex || _attachedMediaUrl != null`), and previously I had wrongly added image controls TO `_MathOverlayWidget` instead of wiring the existing `TextFormattingToolbar`.

### Changes Made

#### `lib/widgets/draggable_text_widget.dart`
- **Removed `hasAttachedImage`, `onIncreaseImageSize`, `onDecreaseImageSize`, `onRemoveImage`** from `_MathOverlayWidget` — image controls DO NOT belong here
- **Fixed `_showOverlay()`** — only shows for `widget.isLatex` (removed `|| _attachedMediaUrl != null`)
- **Fixed `initState()`** — only shows math overlay for LaTeX notes
- **Fixed `didUpdateWidget()`** — entering edit mode only shows overlay for LaTeX; exiting LaTeX always removes overlay (no longer keeps it for images)
- **Kept `isLatex` param** in `_MathOverlayWidget` — correctly controls conditional rendering of LaTeX preview and math buttons

#### `lib/widgets/pdf_viewer_widget_overlay.dart`
- **Fixed `onToggleLatex`** — changed from hardcoded `isLatex: false` to proper toggle `isLatex: !(styles['isLatex'] as bool)` (unchanged from before)

### Behavior After Fix
- **LaTeX notes**: `_MathOverlayWidget` shows with formatting + math buttons + live LaTeX preview
- **Text notes with image**: `TextFormattingToolbar` shows at bottom with font controls + image controls — `_MathOverlayWidget` does NOT appear
- **Plain text notes**: `TextFormattingToolbar` shows at bottom with font controls only
- **Toggle LaTeX**: Properly toggles ON/OFF (was always OFF before)