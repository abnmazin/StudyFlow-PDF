# Gesture Conflict: pdfrx vs Custom Drawing Overlay

> This document records the known gesture conflict between the `pdfrx` PDF viewer and the custom drawing overlay. This is the primary known blocker for seamless zoom+draw interactions.

## The Problem

The integration between `pdfrx` and the custom drawing overlay breaks for complex gestures:

- **pdfrx Interaction**: Handles zooming, scrolling, and page navigation via internal `GestureDetector`.
- **Overlay Interaction**: The `DrawingOverlay` (`pdf_viewer_widget_overlay.dart`) needs to capture pen/highlight/comment gestures.
- **The Conflict**: When a user tries to draw while the PDF is zoomed/scrolled, gestures are either swallowed by the PDF viewer or misaligned in coordinate space.

## Current Coordinate Mapping

In `pdf_viewer_widget_gestures.dart`:
```dart
final pdfPos = pdfController.viewRectToPdfRect(localPos);
```

## Requirements for Resolution

1. **Selective pass-through** of gestures based on `ToolType` (drawing tools should bypass pdfrx's gesture detector).
2. **Seamless coordinate transformation** between Flutter screen space and pdfrx internal PDF space.
3. **Pointer drift prevention** during rapid drawing while the view is settling after a scroll.

## Related Files

- `lib/widgets/pdf_viewer_widget_overlay.dart` — the overlay layer
- `lib/widgets/pdf_viewer_widget_gestures.dart` — gesture handling + coordinate mapping
- `lib/widgets/pdf_viewer_widget_w.dart` — tool state + panel tool selection
- `lib/widgets/pdf_viewer_widget_style.dart` — shape selection and hit testing
