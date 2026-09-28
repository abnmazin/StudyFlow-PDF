import 'package:flutter/material.dart';
import 'enums.dart';

class Highlight {
  final String id;
  final String? createdBy;
  final List<Offset> path;
  final Color color; // Stroke/border color
  final int page;
  final double strokeWidth;
  final HighlightType type;
  final List<Rect>? rects;
  final int? backgroundColor; // Fill color for shapes (nullable, stored as int)
  final bool isSynced;
  final int updatedAt; // Timestamp for conflict resolution

  Highlight({
    required this.id,
    this.createdBy,
    required this.path,
    required this.color,
    required this.page,
    this.strokeWidth = 5.0,
    this.type = HighlightType.highlight,
    this.rects,
    this.backgroundColor, // Optional background color
    this.isSynced = false,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Path? _cachedPath;
  Path get cachedPath {
    if (_cachedPath != null) return _cachedPath!;
    final p = Path();
    if (path.isNotEmpty) {
      p.moveTo(path.first.dx, path.first.dy);
      for (var i = 1; i < path.length; i++) {
        p.lineTo(path[i].dx, path[i].dy);
      }
    }
    _cachedPath = p;
    return p;
  }

  Map<String, dynamic> toJson({bool isExisting = false}) => {
    'id': id,
    if (createdBy != null) 'createdBy': createdBy,
    'path': path.map((o) => {'dx': o.dx, 'dy': o.dy}).toList(),
    'color': color.value,
    'page': page,
    'strokeWidth': strokeWidth,
    'type': type.toString(),
    if (isExisting) 'isExisting': true,
    'isSynced': isSynced,
    'updatedAt': updatedAt,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (rects != null)
      'rects': rects!
          .map((r) => {'L': r.left, 'T': r.top, 'R': r.right, 'B': r.bottom})
          .toList(),
  };

  factory Highlight.fromJson(Map<String, dynamic> json) {
    return Highlight(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      createdBy: json['createdBy'] as String?,
      path: (json['path'] as List)
          .map((p) => Offset(p['dx'], p['dy']))
          .toList(),
      color: Color(json['color']),
      page: json['page'],
      strokeWidth: json['strokeWidth'] ?? 5.0,
      type: json['type'] != null
          ? HighlightType.values.firstWhere(
              (e) => e.toString() == json['type'],
              orElse: () => HighlightType.highlight,
            )
          : HighlightType.highlight,
      backgroundColor:
          json['backgroundColor'], // Load background color if present
      isSynced: json['isSynced'] ?? false,
      updatedAt: json['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      rects: (json['rects'] as List?)?.map((r) {
        return Rect.fromLTRB(r['L'], r['T'], r['R'], r['B']);
      }).toList(),
    );
  }
  Highlight copyWith({
    String? id,
    String? createdBy,
    List<Offset>? path,
    Color? color,
    int? page,
    double? strokeWidth,
    HighlightType? type,
    List<Rect>? rects,
    int? backgroundColor,
    bool? isSynced,
    int? updatedAt,
  }) {
    return Highlight(
      id: id ?? this.id,
      createdBy: createdBy ?? this.createdBy,
      path: path ?? this.path,
      color: color ?? this.color,
      page: page ?? this.page,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      type: type ?? this.type,
      rects: rects ?? this.rects,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PdfComment {
  final String id;
  final int page;
  final Offset position;
  final String content;
  final String? attachedMediaUrl;
  final double? mediaHeight;
  final DateTime date;
  final Color color;
  final String? createdBy;
  final double fontSize;
  final bool isBold;
  final bool isLatex;
  final String fontFamily;
  final bool showBorder;
  final Color borderColor;
  final Color bgColor;
  final bool isSynced;
  final int updatedAt;

  PdfComment({
    required this.id,
    required this.page,
    required this.position,
    required this.content,
    this.attachedMediaUrl,
    this.mediaHeight,
    required this.date,
    this.createdBy,
    this.color = Colors.black,
    this.fontSize = 14.0,
    this.isBold = false,
    this.isLatex = false,
    this.fontFamily = 'Times New Roman',
    this.showBorder = true,
    this.borderColor = const Color(0xFF000000),
    this.bgColor = const Color(0xFFFEF3C7),
    this.isSynced = false,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson({bool isExisting = false}) => {
    'id': id,
    'page': page,
    'dx': position.dx,
    'dy': position.dy,
    'content': content,
    'date': date.toIso8601String(),
    if (attachedMediaUrl != null && attachedMediaUrl!.isNotEmpty)
      'attachedMediaUrl': attachedMediaUrl,
    if (attachedMediaUrl != null && attachedMediaUrl!.isNotEmpty)
      'mediaUrl': attachedMediaUrl,
    if (mediaHeight != null) 'mediaHeight': mediaHeight,
    if (createdBy != null && createdBy!.isNotEmpty) 'createdBy': createdBy,
    'color': color.value,
    'fontSize': fontSize,
    'isBold': isBold,
    'isLatex': isLatex,
    'fontFamily': fontFamily,
    'showBorder': showBorder,
    'borderColor': borderColor.value,
    'bgColor': bgColor.value,
    if (isExisting) 'isExisting': true,
    'isSynced': isSynced,
    'updatedAt': updatedAt,
  };

  factory PdfComment.fromJson(Map<String, dynamic> json) {
    return PdfComment(
      id: json['id'],
      page: json['page'],
      position: Offset(json['dx'], json['dy']),
      content: json['content'],
      date: DateTime.parse(json['date']),
      color: Color(json['color'] ?? 0xFF000000),
      fontSize: json['fontSize']?.toDouble() ?? 14.0,
      isBold: json['isBold'] ?? false,
      isLatex: json['isLatex'] ?? false,
      fontFamily: json['fontFamily'] ?? 'Times New Roman',
      showBorder: json['showBorder'] ?? true,
      borderColor: Color(json['borderColor'] ?? 0xFF000000),
      bgColor: Color(json['bgColor'] ?? 0xFFFEF3C7),
      isSynced: json['isSynced'] ?? false,
      updatedAt: json['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      createdBy: json['createdBy'] as String?,
      attachedMediaUrl:
          (json['attachedMediaUrl'] as String?) ??
          (json['mediaUrl'] as String?),
      mediaHeight: (json['mediaHeight'] as num?)?.toDouble(),
    );
  }

  PdfComment copyWith({
    String? id,
    int? page,
    Offset? position,
    String? content,
    DateTime? date,
    Color? color,
    double? fontSize,
    bool? isBold,
    bool? isLatex,
    String? fontFamily,
    bool? showBorder,
    Color? borderColor,
    Color? bgColor,
    bool? isSynced,
    int? updatedAt,
    String? createdBy,
    String? attachedMediaUrl,
    double? mediaHeight,
  }) {
    return PdfComment(
      id: id ?? this.id,
      page: page ?? this.page,
      position: position ?? this.position,
      content: content ?? this.content,
      date: date ?? this.date,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
      isLatex: isLatex ?? this.isLatex,
      fontFamily: fontFamily ?? this.fontFamily,
      showBorder: showBorder ?? this.showBorder,
      borderColor: borderColor ?? this.borderColor,
      bgColor: bgColor ?? this.bgColor,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      attachedMediaUrl: attachedMediaUrl ?? this.attachedMediaUrl,
      mediaHeight: mediaHeight ?? this.mediaHeight,
    );
  }
}

class PdfBookmark {
  final String id;
  final int page;
  final String name;

  PdfBookmark({required this.id, required this.page, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'page': page, 'name': name};

  factory PdfBookmark.fromJson(Map<String, dynamic> json) {
    return PdfBookmark(id: json['id'], page: json['page'], name: json['name']);
  }
}
