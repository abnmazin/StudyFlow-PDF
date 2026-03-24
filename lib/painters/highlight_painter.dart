import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/models.dart';

class HighlightPainter extends CustomPainter {
  final List<Highlight> highlights;
  final double scale;
  final bool isCurrent;
  // OPTIMIZATION: Cache quick-change signals for repaint decisions
  final int _highlightsHash;
  final String? _selectedHighlightId;

  HighlightPainter({
    required this.highlights,
    required this.scale,
    this.isCurrent = false,
    String? selectedHighlightId,
  })  : _highlightsHash = _calculateHighlightsHash(highlights),
        _selectedHighlightId = selectedHighlightId;

  static int _calculateHighlightsHash(List<Highlight> highlights) {
    // Simple hash to catch structural changes without deep comparison
    return highlights.length * 31 +
        (highlights.isEmpty ? 0 : highlights.last.hashCode);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale, scale);

    for (var h in highlights) {
      if (h.path.isEmpty && (h.rects == null || h.rects!.isEmpty)) continue;
      final isSelected = _selectedHighlightId != null &&
          h.id == _selectedHighlightId;

      // Base paint configuration - will be customized per shape type
      final paint = Paint()
        ..color = h.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = h.strokeWidth
        ..strokeCap = StrokeCap.round;

      if (h.type == HighlightType.pen) {
        // For freehand drawing, use round joins for smooth curves
        paint.strokeJoin = StrokeJoin.round;

        if (h.path.length < 2) {
          canvas.drawPoints(ui.PointMode.points, h.path, paint);
        } else {
          final path = Path();
          path.moveTo(h.path.first.dx, h.path.first.dy);
          for (int i = 1; i < h.path.length; i++) {
            path.lineTo(h.path[i].dx, h.path[i].dy);
          }
          canvas.drawPath(path, paint);
        }
      } else if (h.type == HighlightType.highlight ||
          h.type == HighlightType.text) {
        final highlightPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = h.color.withOpacity(0.45);
        if (h.rects != null && h.rects!.isNotEmpty) {
          for (final rect in h.rects!) canvas.drawRect(rect, highlightPaint);
        } else if (h.path.length >= 2) {
          final strokePaint = Paint()
            ..color = h.color.withOpacity(0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = h.strokeWidth * 1.4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          final path = Path();
          path.moveTo(h.path.first.dx, h.path.first.dy);
          for (int i = 1; i < h.path.length; i++) {
            path.lineTo(h.path[i].dx, h.path[i].dy);
          }
          canvas.drawPath(path, strokePaint);
        }
      } else if (h.path.length >= 2) {
        // For geometric shapes, use miter joins for sharp, clean corners
        paint.strokeJoin = StrokeJoin.miter;
        paint.strokeMiterLimit = 10.0; // Prevent extremely long miters

        final p1 = h.path.first;
        final p2 = h.path.last;

        if (h.type == HighlightType.arrow) {
          _drawProfessionalArrow(canvas, p1, p2, paint);
        } else if (h.type == HighlightType.rectangle) {
          _drawModernRectangle(canvas, p1, p2, paint, h);
        } else if (h.type == HighlightType.circle) {
          _drawPerfectEllipse(canvas, p1, p2, paint, h);
        }

        // رسم مقابض التحديد إذا كان الشكل هو المحدد حالياً
        if (isCurrent) {
          _drawSelectionHandles(canvas, p1, p2);
        }
      }

      if (isSelected) {
        _drawSelectedHighlightOverlay(canvas, h);
      }
    }
    canvas.restore();
  }

  void _drawSelectedHighlightOverlay(Canvas canvas, Highlight h) {
    final rect = _boundsForHighlight(h);
    if (rect == null) return;

    final normalizedRect = rect.inflate(math.max(6.0, h.strokeWidth + 2.0));

    final selectionPaint = Paint()
      ..color = const Color(0xFF2563EB).withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRect(normalizedRect, selectionPaint);

    final handlePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const handleRadius = 4.5;
    final points = <Offset>[
      normalizedRect.topLeft,
      normalizedRect.topRight,
      normalizedRect.bottomLeft,
      normalizedRect.bottomRight,
    ];

    for (final point in points) {
      canvas.drawCircle(point, handleRadius, handlePaint);
      canvas.drawCircle(point, handleRadius, borderPaint);
    }
  }

  Rect? _boundsForHighlight(Highlight h) {
    if (h.rects != null && h.rects!.isNotEmpty) {
      var left = h.rects!.first.left;
      var top = h.rects!.first.top;
      var right = h.rects!.first.right;
      var bottom = h.rects!.first.bottom;
      for (final r in h.rects!) {
        left = math.min(left, r.left);
        top = math.min(top, r.top);
        right = math.max(right, r.right);
        bottom = math.max(bottom, r.bottom);
      }
      return Rect.fromLTRB(left, top, right, bottom);
    }

    if (h.path.isNotEmpty) {
      var left = h.path.first.dx;
      var top = h.path.first.dy;
      var right = h.path.first.dx;
      var bottom = h.path.first.dy;
      for (final p in h.path) {
        left = math.min(left, p.dx);
        top = math.min(top, p.dy);
        right = math.max(right, p.dx);
        bottom = math.max(bottom, p.dy);
      }
      return Rect.fromLTRB(left, top, right, bottom);
    }

    return null;
  }

  void _drawProfessionalArrow(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
  ) {
    if (p1 == p2) return;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final angle = math.atan2(dy, dx);
    final distance = math.sqrt(dx * dx + dy * dy);

    final arrowLength = 20.0 + (paint.strokeWidth * 2);
    final effectiveArrowLength = math.min(arrowLength, distance * 0.6);
    final arrowWidth = effectiveArrowLength * 0.35;

    final arrowBase = Offset(
      p2.dx - effectiveArrowLength * math.cos(angle),
      p2.dy - effectiveArrowLength * math.sin(angle),
    );

    // Draw arrow line with miter join for sharp connection
    canvas.drawLine(p1, arrowBase, paint);

    // Calculate arrowhead triangle vertices from the base
    // Use perpendicular angles to get left and right wing points
    final perpAngle = angle + math.pi / 2;

    // Right wing point (perpendicular offset from base)
    final rightWing = Offset(
      arrowBase.dx + arrowWidth * math.cos(perpAngle),
      arrowBase.dy + arrowWidth * math.sin(perpAngle),
    );

    // Left wing point (perpendicular offset from base, opposite direction)
    final leftWing = Offset(
      arrowBase.dx - arrowWidth * math.cos(perpAngle),
      arrowBase.dy - arrowWidth * math.sin(perpAngle),
    );

    // Create closed triangular path for arrowhead
    final arrowPath = Path()
      ..moveTo(p2.dx, p2.dy) // Tip of arrow
      ..lineTo(rightWing.dx, rightWing.dy) // Right wing
      ..lineTo(leftWing.dx, leftWing.dy) // Left wing
      ..close(); // CRITICAL: Close the path for perfect triangle

    // Fill arrowhead with solid color and miter joins for sharp edges
    final headPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill
      ..strokeJoin = StrokeJoin.miter;

    canvas.drawPath(arrowPath, headPaint);
  }

  void _drawModernRectangle(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
    Highlight h,
  ) {
    final rect = Rect.fromPoints(p1, p2);
    final radius = math.max(4.0, paint.strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 1. Draw Fill (Background)
    // Use specific background color if set, otherwise use default semi-transparent
    final fillColor = h.backgroundColor != null
        ? Color(h.backgroundColor!)
        : h.color.withValues(alpha: 0.1);

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rrect, fillPaint);

    // 2. Draw Border (Stroke) - uses the main color with miter joins
    final strokePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = paint.strokeCap
      ..strokeJoin = StrokeJoin.miter
      ..strokeMiterLimit = 10.0;

    canvas.drawRRect(rrect, strokePaint);
  }

  void _drawPerfectEllipse(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
    Highlight h,
  ) {
    final rect = Rect.fromPoints(p1, p2);

    // 1. Draw Fill (Background)
    // Use specific background color if set, otherwise use default semi-transparent
    final fillColor = h.backgroundColor != null
        ? Color(h.backgroundColor!)
        : h.color.withValues(alpha: 0.1);

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    canvas.drawOval(rect, fillPaint);

    // 2. Draw Border (Stroke) - uses the main color
    canvas.drawOval(rect, paint);
  }

  void _drawSelectionHandles(Canvas canvas, Offset p1, Offset p2) {
    final handlePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final points = [p1, p2, Offset(p1.dx, p2.dy), Offset(p2.dx, p1.dy)];
    for (var point in points) {
      canvas.drawCircle(point, 6, handlePaint);
      canvas.drawCircle(point, 6, borderPaint);
    }

    final selectionRect = Rect.fromPoints(p1, p2);
    final selectionPaint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5; // إطار متصل بدلاً من متقطع لتجنب الأخطاء
    canvas.drawRect(selectionRect, selectionPaint);
  }

  @override
  bool shouldRepaint(covariant HighlightPainter oldDelegate) {
    // Always repaint while drawing to keep live feedback smooth
    if (isCurrent || oldDelegate.isCurrent) return true;

    // Scale changes affect all geometry
    if (scale != oldDelegate.scale) return true;

    // Quick hash comparison for fast bail-out
    if (_highlightsHash != oldDelegate._highlightsHash) return true;

    // Selection state can change overlay handles
    if (_selectedHighlightId != oldDelegate._selectedHighlightId) return true;

    // Cheap length check
    if (highlights.length != oldDelegate.highlights.length) return true;

    // Shallow per-item checks to catch property edits without heavy work
    for (int i = 0; i < highlights.length; i++) {
      final current = highlights[i];
      final previous = oldDelegate.highlights[i];

      if (current.id != previous.id) return true;
      if (current.color != previous.color) return true;
      if (current.strokeWidth != previous.strokeWidth) return true;
      if (current.backgroundColor != previous.backgroundColor) return true;
      if (current.type != previous.type) return true;

      // Path/rect changes — approximate check to avoid expensive deep diff
      if (current.path.length != previous.path.length) return true;
      if (!_pathsAreEqual(current.path, previous.path)) return true;
      if ((current.rects?.length ?? 0) != (previous.rects?.length ?? 0)) {
        return true;
      }
    }

    return false;
  }

  bool _pathsAreEqual(List<Offset> path1, List<Offset> path2) {
    if (path1.length != path2.length) return false;
    for (int i = 0; i < path1.length; i++) {
      if ((path1[i] - path2[i]).distance > 0.01) return false;
    }
    return true;
  }
}
