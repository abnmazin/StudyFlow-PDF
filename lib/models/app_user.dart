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
}
