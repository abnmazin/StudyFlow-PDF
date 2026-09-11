# Changelog

## [2026-09-11] MCP Integration: Third AI Provider (Personal Gemini Account)

### Feature
Added **`mcp`** as a third AI provider alongside `gemini` and `groq`. MCP bridges the app to `gemini-app-mcp` (Node.js MCP server) via browser automation, using the user's **personal Google account** — **no API key required**.

### Architecture
- **NEW `lib/services/mcp_client_service.dart`** (singleton `McpClientService.instance`):
  - Spawns `npx -y gemini-app-mcp@latest` as a child process (stdin/stdout line-delimited JSON-RPC 2.0)
  - Implements MCP handshake: `initialize` → `notifications/initialized` → `tools/call`
  - Methods: `start()`, `stop()`, `askQuestion()`, `getHealth()`, `setupAuth()`, `resetConversation()`, `isNodeAvailable`, `isRunning`
  - Process watchdog: auto-restart on next call after crash; 90s request timeout (11min for `setup_auth` due to browser login)
  - Keeps `session_id` in memory for multi-turn conversation continuity
  - Detects Windows `npx.cmd` via `where.exe` (Dart's `Process.start` can't resolve `.cmd`)
  - Throws typed `McpException(code, message)` with codes `MCP_UNAVAILABLE`, `MCP_DIED`, `MCP_TIMEOUT`, `MCP_NOT_AUTHENTICATED`

### Files Modified
- `lib/providers/app_state.dart`:
  - Added `mcpModelsList`, `_mcpModel`, `_mcpSessionId`, getters, `setMcpModel()`, prefs key `studyflowpdf_mcp_model`
  - `currentModel` now ternary for all three providers
  - `setAiProvider()` accepts `'mcp'`; warms up MCP server when selected
  - `triggerAiFallback()` fallback ring now: `gemini → groq → mcp` / `groq → gemini → mcp` / `mcp → gemini → groq`
  - `dispose()` stops the MCP server
- `lib/services/translation_service.dart`: `translate()` dispatcher handles `'mcp'` via new `_translateMcp()`
- `lib/widgets/viewer_components/viewer_right_panel.dart`: `_generateAiReply()` dispatcher routes `'mcp'` → new `_generateMcpReply()` (system prompt + 8-message history concatenated into single question); error bubbles distinguish MCP auth/unavailable errors
- `lib/widgets/global_settings_modal.dart`: added `Gemini (الحساب الشخصي)` dropdown item, MCP model list, and a live status card with Node.js status, auth status, "ربط حساب Google" (calls `setupAuth`) and "قطع الاتصال" (calls `stop`) buttons

### Design Decisions
- MCP server starts **lazily** (on selecting provider or on boot if provider is `'mcp'`), never at app startup unless selected
- Chat history is passed inside the single `question` argument (MCP has no system-role support)
- Translation uses the same shared MCP session instance

### Known Limitations / Failed Attempts
- MCP auth expires after ~24h (server stores session on disk); requires re-linking via Settings
- Browser automation is slower than direct API calls (refresh of the web app per turn)
- `gemini-app-mcp` is unofficial/reverse-engineered — Google can change the web UI and break it (mitigated by `@latest` and fallback ring)
- Uses the user's personal Gemini account quota — ToS risk exists
- Requires Node.js + a Chromium browser on the machine; option auto-disables if `isNodeAvailable` is false

---

## [2026-09-11] Project Cleanup: Unused Files, Dead Code, Config Fixes

### Files Deleted (4 orphaned Dart files)
- `lib/screens/admin/dev_dashboard.dart` — empty deprecated placeholder
- `lib/services/python_equation_service.dart` — replaced by `math_engine.dart`, zero imports
- `lib/services/isolate_worker.dart` — `computePdfMetadataIsolate()` never called
- `lib/widgets/viewer_components/join_master_modal.dart` — superseded by inline join UI in `global_settings_modal.dart`

### Root Clutter Removed (~30 files)
- Python scripts (Telegram bots, Instagram scrapers)
- Academic PDFs, Excel data files, JSON artifacts
- Instagram session artifacts (security risk)
- `Final.tex`, `processes.txt`, `log.txt`, `pdf.png`
- `__pycache__/` directory

### Dead Code Removed from `developer_dashboard_v.dart`
- Removed dead duplicate `GlobalSettingsModal` class (lines 13–1664) shadowed by `global_settings_modal.dart`
- Removed dead `_buildAdminSectionHeader`, `_buildClearButton`, `_confirmWipe` methods
- File: 2708 → 974 lines
- Cleaned unused imports (services.dart, gestures.dart, package_info_plus, login_screen)

### Code Deduplication
- `lib/models/enums.dart`: Merged duplicate `ToolTypeExtension` + `ToolTypeX` into single `ToolTypeX` (getters)
- `lib/widgets/pdf_viewer_widget_gestures.dart`: Migrated `.isDrawingTool()` → `.isDrawing`
- `lib/services/auth_service.dart`: Removed deprecated `loginAndBind()` method (never called)

### Config Fixes
- `.gitignore`: Resolved git merge conflict (HEAD vs `55e3659`); added ignore rules for `__pycache__/`, `/*.pdf`, `/*.py`, `/*.xlsx`, `/*.tex`

### New Documentation
- `docs/performance_and_ram.md` — RAM usage research (migrated from `فف/RAM_NAVIGATION_RESEARCH.md`)
- `docs/gesture_conflict.md` — pdfrx vs overlay gesture conflict documentation
- `docs/deploy_guide.md` — GitHub Pages deployment guide (corrected paths)

### Scratch Directory Deleted
- `فف/` folder removed (old analyses, stale function index, code archives)

---

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