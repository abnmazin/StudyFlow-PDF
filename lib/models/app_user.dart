import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String username;
  final String displayName;
  final String role;
  final String hardwareId;
  final String? primaryDeviceFingerprint;
  final String? primaryDeviceId;
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
    this.isBanned = false,
    this.banReason,
    this.bannedAt,
  });

  factory AppUser.fromFirestore(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      username: (data['username'] ?? '').toString(),
      displayName: (data['displayName'] ?? data['username'] ?? '').toString(),
      role: (data['role'] ?? 'member').toString(),
      hardwareId: (data['hardwareId'] ?? '').toString(),
      primaryDeviceFingerprint: data['primaryDeviceFingerprint']?.toString(),
      primaryDeviceId: data['primaryDeviceId']?.toString(),
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
      isBanned: json['isBanned'] as bool? ?? false,
      banReason: json['banReason'] as String?,
      bannedAt: json['bannedAt'] != null 
          ? DateTime.parse(json['bannedAt'] as String) 
          : null,
    );
  }
}
