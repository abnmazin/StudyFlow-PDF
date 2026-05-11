import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String username;
  final String displayName;
  final String role; // 'admin' | 'student' (refined from generic 'member')
  final String hardwareId;
  final String? primaryDeviceFingerprint;
  final String? primaryDeviceId;
  final String? universityId; // NEW: Links user to their university
  final bool isBanned;
  final String? banReason;
  final DateTime? bannedAt;

  const AppUser({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.role,
    required this.hardwareId,
    this.primaryDeviceFingerprint,
    this.primaryDeviceId,
    this.universityId, // NEW
    this.isBanned = false,
    this.banReason,
    this.bannedAt,
  });

  factory AppUser.fromFirestore(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      username: (data['username'] ?? '').toString(),
      displayName: (data['displayName'] ?? data['username'] ?? '').toString(),
      role: (data['role'] ?? 'student').toString(),
      hardwareId: (data['hardwareId'] ?? '').toString(),
      primaryDeviceFingerprint: data['primaryDeviceFingerprint']?.toString(),
      primaryDeviceId: data['primaryDeviceId']?.toString(),
      universityId: data['universityId']?.toString(), // NEW
      isBanned: data['isBanned'] ?? false,
      banReason: data['banReason']?.toString(),
      bannedAt: data['bannedAt'] is Timestamp
          ? (data['bannedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'username': username,
      'displayName': displayName,
      'role': role,
      'hardwareId': hardwareId,
      'primaryDeviceFingerprint': primaryDeviceFingerprint,
      'primaryDeviceId': primaryDeviceId,
      'universityId': universityId, // NEW
      'isBanned': isBanned,
      'banReason': banReason,
      'bannedAt': bannedAt != null ? Timestamp.fromDate(bannedAt!) : null,
    };
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] as String,
      username: json['username'] as String,
      displayName: (json['displayName'] ?? json['username'] ?? '') as String,
      role: json['role'] as String,
      hardwareId: json['hardwareId'] as String,
      primaryDeviceFingerprint: json['primaryDeviceFingerprint'] as String?,
      primaryDeviceId: json['primaryDeviceId'] as String?,
      universityId: json['universityId'] as String?, // NEW
      isBanned: json['isBanned'] as bool? ?? false,
      banReason: json['banReason'] as String?,
      bannedAt: json['bannedAt'] != null
          ? DateTime.parse(json['bannedAt'] as String)
          : null,
    );
  }

  /// Convenience getters for role checking
  bool get isAdmin => role == 'admin' || role == 'developer';
  bool get isLecturer => role == 'lecturer' || isAdmin;
  bool get isDeveloper => role == 'developer' || role == 'admin';
  bool get isStudent => role == 'student' || role == 'member';

  /// Creates a copy of this AppUser with the given fields replaced.
  AppUser copyWith({
    String? uid,
    String? username,
    String? displayName,
    String? role,
    String? hardwareId,
    String? primaryDeviceFingerprint,
    String? primaryDeviceId,
    String? universityId,
    bool? isBanned,
    String? banReason,
    DateTime? bannedAt,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      hardwareId: hardwareId ?? this.hardwareId,
      primaryDeviceFingerprint:
          primaryDeviceFingerprint ?? this.primaryDeviceFingerprint,
      primaryDeviceId: primaryDeviceId ?? this.primaryDeviceId,
      universityId: universityId ?? this.universityId,
      isBanned: isBanned ?? this.isBanned,
      banReason: banReason ?? this.banReason,
      bannedAt: bannedAt ?? this.bannedAt,
    );
  }
}
