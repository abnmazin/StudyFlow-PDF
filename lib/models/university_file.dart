import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a PDF file within a university folder.
/// Mapped to the Firestore collection: `university_files/{fileId}`
///
/// The [fileHash] is the SHA-256 digest of the file content, used as the
/// primary identifier for cross-device sync and deduplication.
/// This prevents ID desync issues between devices (per the architecture rule:
/// "strictly rely on File Hashes rather than random Local IDs").
class UniversityFile {
  final String id;
  final String universityId;
  final String folderId;
  final String name;
  final String fileHash; // SHA-256 hash — digital footprint for sync
  final String storagePath; // Full Supabase storage path
  final int sizeBytes;
  final String mimeType;
  final String uploadedBy;
  final DateTime uploadedAt;
  final int? totalPages;
  final bool isDeleted;

  const UniversityFile({
    required this.id,
    required this.universityId,
    required this.folderId,
    required this.name,
    required this.fileHash,
    required this.storagePath,
    required this.sizeBytes,
    this.mimeType = 'application/pdf',
    required this.uploadedBy,
    required this.uploadedAt,
    this.totalPages,
    this.isDeleted = false,
  });

  factory UniversityFile.fromFirestore(String id, Map<String, dynamic> data) {
    return UniversityFile(
      id: id,
      universityId: (data['universityId'] ?? '').toString(),
      folderId: (data['folderId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      fileHash: (data['fileHash'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      sizeBytes: data['sizeBytes'] ?? 0,
      mimeType: (data['mimeType'] ?? 'application/pdf').toString(),
      uploadedBy: (data['uploadedBy'] ?? '').toString(),
      uploadedAt: data['uploadedAt'] is Timestamp
          ? (data['uploadedAt'] as Timestamp).toDate()
          : DateTime.now(),
      totalPages: data['totalPages'] as int?,
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'universityId': universityId,
      'folderId': folderId,
      'name': name,
      'fileHash': fileHash,
      'storagePath': storagePath,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
      'uploadedBy': uploadedBy,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'totalPages': totalPages,
      'isDeleted': isDeleted,
    };
  }

  factory UniversityFile.fromJson(Map<String, dynamic> json) {
    return UniversityFile(
      id: json['id'] as String,
      universityId: json['universityId'] as String,
      folderId: json['folderId'] as String,
      name: json['name'] as String,
      fileHash: json['fileHash'] as String,
      storagePath: json['storagePath'] as String,
      sizeBytes: json['sizeBytes'] as int,
      mimeType: json['mimeType'] as String? ?? 'application/pdf',
      uploadedBy: json['uploadedBy'] as String,
      uploadedAt: json['uploadedAt'] is DateTime
          ? json['uploadedAt'] as DateTime
          : DateTime.parse(json['uploadedAt'] as String),
      totalPages: json['totalPages'] as int?,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  UniversityFile copyWith({
    String? id,
    String? universityId,
    String? folderId,
    String? name,
    String? fileHash,
    String? storagePath,
    int? sizeBytes,
    String? mimeType,
    String? uploadedBy,
    DateTime? uploadedAt,
    int? totalPages,
    bool? isDeleted,
  }) {
    return UniversityFile(
      id: id ?? this.id,
      universityId: universityId ?? this.universityId,
      folderId: folderId ?? this.folderId,
      name: name ?? this.name,
      fileHash: fileHash ?? this.fileHash,
      storagePath: storagePath ?? this.storagePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      totalPages: totalPages ?? this.totalPages,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}