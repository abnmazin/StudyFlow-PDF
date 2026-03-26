import 'annotations.dart';

class PdfItem {
  final String id;
  final String name;
  final String path; // Local file path (can be temp)
  final String? originalPath; // Original persistence path
  final List<Highlight> highlights;
  final List<PdfComment> comments;
  final List<PdfBookmark> bookmarks;
  final String? fileHash; // SHA-256 hash of the content
  final int? pageCount; // Total number of pages
  double scrollTop; // Store scroll position
  int? lastPage; // Store last viewed page
  int? lastModified; // Timestamp of last modification to force reload

  PdfItem({
    required this.id,
    required this.name,
    required this.path,
    this.originalPath,
    this.fileHash,
    this.pageCount,
    List<Highlight>? highlights,
    List<PdfComment>? comments,
    List<PdfBookmark>? bookmarks,
    this.scrollTop = 0.0,
    this.lastPage,
    this.lastModified,
  }) : highlights = highlights ?? [],
       comments = comments ?? [],
       bookmarks = bookmarks ?? [];

  PdfItem copyWith({
    String? id,
    String? name,
    String? path,
    String? originalPath,
    String? fileHash,
    int? pageCount,
    List<Highlight>? highlights,
    List<PdfComment>? comments,
    List<PdfBookmark>? bookmarks,
    double? scrollTop,
    int? lastPage,
    int? lastModified,
  }) {
    return PdfItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      originalPath: originalPath ?? this.originalPath,
      fileHash: fileHash ?? this.fileHash,
      pageCount: pageCount ?? this.pageCount,
      highlights: highlights ?? this.highlights,
      comments: comments ?? this.comments,
      bookmarks: bookmarks ?? this.bookmarks,
      scrollTop: scrollTop ?? this.scrollTop,
      lastPage: lastPage ?? this.lastPage,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'originalPath': originalPath,
    'fileHash': fileHash,
    'pageCount': pageCount,
    'highlights': highlights.map((h) => h.toJson()).toList(),
    'comments': comments.map((c) => c.toJson()).toList(),
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
    'scrollTop': scrollTop,
    'lastPage': lastPage,
    'lastModified': lastModified,
  };

  factory PdfItem.fromJson(Map<String, dynamic> json) {
    return PdfItem(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      originalPath: json['originalPath'],
      fileHash: json['fileHash'],
      pageCount: json['pageCount'],
      highlights: (json['highlights'] as List?)
          ?.map((h) => Highlight.fromJson(h))
          .toList(),
      comments: (json['comments'] as List?)
          ?.map((c) => PdfComment.fromJson(c))
          .toList(),
      bookmarks: (json['bookmarks'] as List?)
          ?.map((b) => PdfBookmark.fromJson(b))
          .toList(),
      scrollTop: json['scrollTop'] ?? 0.0,
      lastPage: json['lastPage'],
      lastModified: json['lastModified'],
    );
  }
}

class ClassItem {
  final String id;
  final String name;
  final List<PdfItem> pdfs;
  String? lastActivePdfId; // Store last open PDF for this class

  ClassItem({
    required this.id,
    required this.name,
    List<PdfItem>? pdfs,
    this.lastActivePdfId,
  }) : pdfs = pdfs ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pdfs': pdfs.map((p) => p.toJson()).toList(),
    'lastActivePdfId': lastActivePdfId,
  };

  factory ClassItem.fromJson(Map<String, dynamic> json) {
    return ClassItem(
      id: json['id'],
      name: json['name'],
      pdfs: (json['pdfs'] as List?)?.map((p) => PdfItem.fromJson(p)).toList(),
      lastActivePdfId: json['lastActivePdfId'],
    );
  }
}
