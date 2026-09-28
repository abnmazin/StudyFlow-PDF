import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a YouTube video link within a university folder.
/// Mapped to the Firestore collection: `university_videos/{videoId}`
///
/// Videos live in their own collection, separate from [UniversityFile],
/// so the PDF storage/download pipeline stays untouched.
/// [videoId] is the 11-char YouTube ID used for the embedded player.
class UniversityVideo {
  final String id;
  final String universityId;
  final String folderId;
  final String title;
  final String videoId; // 11-char YouTube video ID
  final String
  videoUrl; // Normalized watch URL (https://www.youtube.com/watch?v=<id>)
  final String uploadedBy;
  final DateTime uploadedAt;
  final bool isDeleted;
  final int sortOrder; // Manual order index (drag & drop reorder)

  const UniversityVideo({
    required this.id,
    required this.universityId,
    required this.folderId,
    required this.title,
    required this.videoId,
    required this.videoUrl,
    required this.uploadedBy,
    required this.uploadedAt,
    this.isDeleted = false,
    this.sortOrder = 0,
  });

  factory UniversityVideo.fromFirestore(String id, Map<String, dynamic> data) {
    return UniversityVideo(
      id: id,
      universityId: (data['universityId'] ?? '').toString(),
      folderId: (data['folderId'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      videoId: (data['videoId'] ?? '').toString(),
      videoUrl: (data['videoUrl'] ?? '').toString(),
      uploadedBy: (data['uploadedBy'] ?? '').toString(),
      uploadedAt: data['uploadedAt'] is Timestamp
          ? (data['uploadedAt'] as Timestamp).toDate()
          : DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
      sortOrder: data['sortOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'universityId': universityId,
      'folderId': folderId,
      'title': title,
      'videoId': videoId,
      'videoUrl': videoUrl,
      'uploadedBy': uploadedBy,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'isDeleted': isDeleted,
      'sortOrder': sortOrder,
    };
  }

  UniversityVideo copyWith({
    String? id,
    String? universityId,
    String? folderId,
    String? title,
    String? videoId,
    String? videoUrl,
    String? uploadedBy,
    DateTime? uploadedAt,
    bool? isDeleted,
    int? sortOrder,
  }) {
    return UniversityVideo(
      id: id ?? this.id,
      universityId: universityId ?? this.universityId,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      videoId: videoId ?? this.videoId,
      videoUrl: videoUrl ?? this.videoUrl,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
