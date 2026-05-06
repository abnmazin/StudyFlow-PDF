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
  
  String? lastActivePdfId;

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

  @Index()
  String? originalDisplayName;

  @Index()
  String? fileHash;

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
    String? originalDisplayName,
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
    String? fileHash,
  }) {
    return PdfDocument()
      ..uuid = uuid ?? const Uuid().v4()
      ..originalPath = originalPath
      ..originalDisplayName = originalDisplayName
      ..fileHash = fileHash
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

// ─────────────────────────────────────────────────────────────────────────────
// StudyTask: Daily to-do items persisted via Isar
// ─────────────────────────────────────────────────────────────────────────────

@embedded
class IsarPoint {
  double? dx;
  double? dy;
}

@embedded
class IsarRect {
  double? left;
  double? top;
  double? right;
  double? bottom;
}

@collection
class IsarHighlight {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String uuid = ''; // Matches Highlight.id

  @Index()
  String pdfUuid = ''; // Links to PdfDocument.uuid

  List<IsarPoint> path = [];
  int color = 0;
  int page = 1;
  double strokeWidth = 5.0;
  String type = ''; // HighlightType enum name
  List<IsarRect>? rects;
  int? backgroundColor;
  bool isSynced = false;
  int updatedAt = 0;
}

@collection
class IsarComment {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String uuid = ''; // Matches PdfComment.id

  @Index()
  String pdfUuid = ''; // Links to PdfDocument.uuid

  String createdBy = '';

  int page = 1;
  IsarPoint? position;
  String content = '';
  String attachedMediaUrl = '';
  DateTime date = DateTime.now();
  int color = 0;
  double fontSize = 14.0;
  bool isBold = false;
  bool isLatex = false;
  String fontFamily = 'Times New Roman';
  bool showBorder = true;
  int borderColor = 0;
  int bgColor = 0;
  bool isSynced = false;
  int updatedAt = 0;
}

@collection
class IsarBookmark {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String uuid = ''; // Matches PdfBookmark.id

  @Index()
  String pdfUuid = ''; // Links to PdfDocument.uuid

  int page = 1;
  String name = '';
}

// ─────────────────────────────────────────────────────────────────────────────
// DeletedAnnotation: Stores soft-deleted items as JSON snapshots for auditing/restoration
// ─────────────────────────────────────────────────────────────────────────────

@collection
class DeletedAnnotation {
  Id id = Isar.autoIncrement;

  @Index()
  late String originalId; // The ID of the comment/highlight

  @Index()
  late String pdfId;

  late String itemType; // 'comment', 'highlight', 'drawing', 'math'
  late int pageNumber;
  late String deletedBy; // Username who deleted it
  late DateTime deletedAt;
  late String contentSnapshot; // The full JSON representation of the deleted item
  bool isSynced = false;

  Map<String, dynamic> toJson() {
    return {
      'originalId': originalId,
      'pdfId': pdfId,
      'itemType': itemType,
      'pageNumber': pageNumber,
      'deletedBy': deletedBy,
      'deletedAt': deletedAt.millisecondsSinceEpoch,
      'contentSnapshot': contentSnapshot,
    };
  }

  static DeletedAnnotation fromJson(Map<String, dynamic> json) {
    return DeletedAnnotation()
      ..originalId = json['originalId'] ?? ''
      ..pdfId = json['pdfId'] ?? ''
      ..itemType = json['itemType'] ?? ''
      ..pageNumber = json['pageNumber'] ?? 0
      ..deletedBy = json['deletedBy'] ?? ''
      ..deletedAt = DateTime.fromMillisecondsSinceEpoch(json['deletedAt'] ?? 0)
      ..contentSnapshot = json['contentSnapshot'] ?? ''
      ..isSynced = true;
  }
}

@collection
class StudyTask {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String uuid = '';

  @Index()
  String title = '';

  bool isDone = false;

  DateTime createdAt = DateTime.now();

  static StudyTask create({
    String? uuid,
    required String title,
    bool isDone = false,
    DateTime? createdAt,
  }) {
    return StudyTask()
      ..uuid = uuid ?? const Uuid().v4()
      ..title = title
      ..isDone = isDone
      ..createdAt = createdAt ?? DateTime.now();
  }
}
