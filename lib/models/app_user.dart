class AppUser {
  final String uid;
  final String username;
  final String role;
  final String hardwareId;

  const AppUser({
    required this.uid,
    required this.username,
    required this.role,
    required this.hardwareId,
  });

  factory AppUser.fromFirestore(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      username: (data['username'] ?? '').toString(),
      role: (data['role'] ?? 'member').toString(),
      hardwareId: (data['hardwareId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'username': username,
      'role': role,
      'hardwareId': hardwareId,
    };
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] as String,
      username: json['username'] as String,
      role: json['role'] as String,
      hardwareId: json['hardwareId'] as String,
    );
  }
}
