import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a folder within a university's content structure.
/// Mapped to the Firestore collection: `university_folders/{folderId}`
class UniversityFolder {
  final String id;
  final String universityId;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final bool isDeleted;
  final int sortOrder;

  const UniversityFolder({
    required this.id,
    required this.universityId,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    this.isDeleted = false,
    this.sortOrder = 0,
  });

  factory UniversityFolder.fromFirestore(String id, Map<String, dynamic> data) {
    return UniversityFolder(
      id: id,
      universityId: (data['universityId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
      sortOrder: data['sortOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'universityId': universityId,
      'name': name,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
      'sortOrder': sortOrder,
    };
  }

  factory UniversityFolder.fromJson(Map<String, dynamic> json) {
    return UniversityFolder(
      id: json['id'] as String,
      universityId: json['universityId'] as String,
      name: json['name'] as String,
      createdBy: json['createdBy'] as String,
      createdAt: json['createdAt'] is DateTime
          ? json['createdAt'] as DateTime
          : DateTime.parse(json['createdAt'] as String),
      isDeleted: json['isDeleted'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  UniversityFolder copyWith({
    String? id,
    String? universityId,
    String? name,
    String? createdBy,
    DateTime? createdAt,
    bool? isDeleted,
    int? sortOrder,
  }) {
    return UniversityFolder(
      id: id ?? this.id,
      universityId: universityId ?? this.universityId,
      name: name ?? this.name,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
