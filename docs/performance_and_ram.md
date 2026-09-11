# Performance & RAM Usage Research

> Researched 2026-03-27. Documents how the app uses memory and opportunities for improvement.

## Summary

The app benefits from RAM during page navigation via:

1. **In-Memory State via Provider** (`AppProvider`) at the app level — survives navigation between LoginScreen and MainLayout.
2. **IndexedStack** in `viewer_right_panel.dart` keeps tab widgets alive in RAM without rebuilding on tab switch.
3. **Image Cache** (`imageCache`) with pinned limits to prevent unbounded growth.
4. **SharedPreferences** integration for persistent state across restarts (not RAM, but complements it).

## Evidence from Code

### 1. Global State Provider
- `main.dart` creates `ChangeNotifierProvider(create: (_) => AppProvider())` inside `MultiProvider`.
- `AppProvider` state lives in RAM for the entire app lifetime — not lost on `pushReplacement` between screens.

### 2. Navigation Pattern
- LoginScreen → `pushReplacement` → MainLayout.
- Logout → `pushAndRemoveUntil` → LoginScreen.
- Because `AppProvider` sits above `MaterialApp`, shared state persists during normal navigation.

### 3. IndexedStack for Tabs
- `viewer_right_panel.dart` uses `IndexedStack` for the right panel tabs.
- This preserves each tab's state in RAM instead of rebuilding on every tab switch.

### 4. Image Cache (Pinned)
- `main.dart`:
  - `PaintingBinding.instance.imageCache.maximumSizeBytes = 10 * 1024 * 1024`
  - `PaintingBinding.instance.imageCache.maximumSize = 20`
- Intentional RAM cache for PDF thumbnails with a hard cap.

### 5. RAM + Disk Persistence Integration
- `AppProvider` holds `classes`, `activeClassId`, `activePdfId` in memory.
- Same state loaded/saved via `SharedPreferences` in `_loadState()` / `_saveState()`.
- Result: Fast runtime access (RAM) + continuity after app close (Disk).

## What Was NOT Found

- No `PageStorage` usage.
- No `AutomaticKeepAliveClientMixin` usage.
- No `RestorationMixin` usage in `lib/`.

## Recommendations for Improvement

- Add `PageStorageKey` to lists/scroll views for scroll position restoration.
- Use `AutomaticKeepAliveClientMixin` for heavy `TabBarView` screens.
- Use `RestorationMixin` for precise state restoration after OS kills the app.
