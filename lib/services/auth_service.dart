import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'hardware_service.dart';

class AuthService {
  final FirebaseFirestore _firestore;
  final HardwareService _hardwareService;

  AuthService({FirebaseFirestore? firestore, HardwareService? hardwareService})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _hardwareService = hardwareService ?? HardwareService();

  Future<AppUser> loginAndBind(String username) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      throw Exception('Username is required');
    }

    final currentUuid = await _hardwareService.getDeviceUUID();

    // 1. BLACKLIST CHECK: Prevent blocked devices from logging in
    final blacklistDoc = await _firestore.collection('blacklisted_devices').doc(currentUuid).get();
    if (blacklistDoc.exists) {
      throw Exception('هذا الجهاز محظور من استخدام النظام، يرجى مراجعة المطور');
    }

    final query = await _firestore
        .collection('users')
        .where('username', isEqualTo: normalizedUsername)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      // CLOSED REGISTRATION: User must be added by admin first
      throw Exception('هذا الحساب غير مسجل، يرجى مراجعة المطور');
    }

    final doc = query.docs.first;
    final data = doc.data();
    final role = (data['role'] ?? 'member').toString();
    final storedHardwareId = (data['hardwareId'] ?? '').toString();

    // DEVELOPER BYPASS: Developers can login from any device
    if (role == 'developer') {
      return AppUser.fromFirestore(doc.id, data);
    }

    // STRICT DEVICE BINDING: For everything else
    if (storedHardwareId.isEmpty) {
      // First-time login: bind the hardwareId
      await doc.reference.update({'hardwareId': currentUuid});
      data['hardwareId'] = currentUuid;
    } else if (storedHardwareId != currentUuid) {
      throw Exception('الحساب مسجل على جهاز آخر، يرجى مراجعة المطور لفك الارتباط');
    }

    return AppUser.fromFirestore(doc.id, data);
  }
}
