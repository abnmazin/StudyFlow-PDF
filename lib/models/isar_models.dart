import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

part 'isar_models.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ClassFolder: Organises PDFs into user-created subject groups
// ─────────────────────────────────────────────────────────────────────────────

@collection
class ClassFolder {
  Id id = Isar.autoIncrement;

  @Index()
  String uuid = '';

  @Index()
  String name = '';

  String? icon;
  int? color;

  @Index()
  int orderIndex = 0;

  List<String> pdfIds = [];

  /// Use this factory to create new instances with auto-generated UUIDs.
  static ClassFolder create({
    String? uuid,
    required String name,
    String? icon,
    int? color,
    int orderIndex = 0,
    List<String>? pdfIds,
  }) {
    return ClassFolder()
      ..uuid = uuid ?? const Uuid().v4()
      ..name = name
      ..icon = icon
      ..color = color
      ..orderIndex = orderIndex
      ..pdfIds = pdfIds ?? [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PdfDocument: Tracks every imported PDF and its working copy
// ─────────────────────────────────────────────────────────────────────────────

@collection
class PdfDocument {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String uuid = '';

  @Index()
  String originalPath = '';

  String? workingPath;
  DateTime? workingCreatedAt;
  DateTime? workingModifiedAt;

  DateTime? lastOpenedAt;
  int lastPage = 1;
  double lastZoom = 1.0;
  double lastScroll = 0.0;

  int totalPages = 0;
  int fileSize = 0;

  @Index()
  String? classId;

  int annotationCount = 0;
  int commentCount = 0;

  List<String> tags = [];
  bool isPinned = false;

  bool isEditing = false;
  bool hasUnsavedChanges = false;

  String? thumbnailPath;

  DateTime createdAt = DateTime.now();

  static PdfDocument create({
    String? uuid,
    required String originalPath,
    String? workingPath,
    DateTime? workingCreatedAt,
    DateTime? workingModifiedAt,
    DateTime? lastOpenedAt,
    int lastPage = 1,
    double lastZoom = 1.0,
    double lastScroll = 0.0,
    int totalPages = 0,
    int fileSize = 0,
    String? classId,
    int annotationCount = 0,
    int commentCount = 0,
    List<String>? tags,
    bool isPinned = false,
    bool isEditing = false,
    bool hasUnsavedChanges = false,
    String? thumbnailPath,
    DateTime? createdAt,
  }) {
    return PdfDocument()
      ..uuid = uuid ?? const Uuid().v4()
      ..originalPath = originalPath
      ..workingPath = workingPath
      ..workingCreatedAt = workingCreatedAt
      ..workingModifiedAt = workingModifiedAt
      ..lastOpenedAt = lastOpenedAt
      ..lastPage = lastPage
      ..lastZoom = lastZoom
      ..lastScroll = lastScroll
      ..totalPages = totalPages
      ..fileSize = fileSize
      ..classId = classId
      ..annotationCount = annotationCount
      ..commentCount = commentCount
      ..tags = tags ?? []
      ..isPinned = isPinned
      ..isEditing = isEditing
      ..hasUnsavedChanges = hasUnsavedChanges
      ..thumbnailPath = thumbnailPath
      ..createdAt = createdAt ?? DateTime.now();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PdfSnapshot: Point-in-time copy of a working PDF (history / undo layer)
// ─────────────────────────────────────────────────────────────────────────────

@collection
class PdfSnapshot {
  Id id = Isar.autoIncrement;

  String uuid = '';

  @Index()
  String pdfId = '';

  String filePath = '';
  int version = 1;
  String? description;

  int annotationCount = 0;
  int commentCount = 0;

  DateTime createdAt = DateTime.now();
  String? createdBy;

  static PdfSnapshot create({
    String? uuid,
    required String pdfId,
    required String filePath,
    required int version,
    String? description,
    int annotationCount = 0,
    int commentCount = 0,
    DateTime? createdAt,
    String? createdBy = 'user',
  }) {
    return PdfSnapshot()
      ..uuid = uuid ?? const Uuid().v4()
      ..pdfId = pdfId
      ..filePath = filePath
      ..version = version
      ..description = description
      ..annotationCount = annotationCount
      ..commentCount = commentCount
      ..createdAt = createdAt ?? DateTime.now()
      ..createdBy = createdBy;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TrashItem: Soft-deleted PDFs held for 30 days before permanent removal
// ─────────────────────────────────────────────────────────────────────────────

@collection
class TrashItem {
  Id id = Isar.autoIncrement;

  String uuid = '';

  @Index()
  String originalPdfId = '';

  String name = '';
  String filePath = '';
  int fileSize = 0;

  @Index()
  DateTime deletedAt = DateTime.now();

  @Index()
  DateTime expiresAt = DateTime.now();

  String? originalClassId;
  String? originalDataJson;

  bool canRestore = true;

  static TrashItem create({
    String? uuid,
    required String originalPdfId,
    required String name,
    required String filePath,
    int fileSize = 0,
    DateTime? deletedAt,
    DateTime? expiresAt,
    String? originalClassId,
    String? originalDataJson,
    bool canRestore = true,
  }) {
    final now = DateTime.now();
    return TrashItem()
      ..uuid = uuid ?? const Uuid().v4()
      ..originalPdfId = originalPdfId
      ..name = name
      ..filePath = filePath
      ..fileSize = fileSize
      ..deletedAt = deletedAt ?? now
      ..expiresAt = expiresAt ?? now.add(const Duration(days: 30))
      ..originalClassId = originalClassId
      ..originalDataJson = originalDataJson
      ..canRestore = canRestore;
  }
}
