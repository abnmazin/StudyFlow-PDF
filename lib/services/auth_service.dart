import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_user.dart';
import 'hardware_service.dart';

class AuthService {
  final FirebaseFirestore _firestore;
  final HardwareService _hardwareService;

  AuthService({FirebaseFirestore? firestore, HardwareService? hardwareService})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _hardwareService = hardwareService ?? HardwareService();

  /// Domain used to derive the Firebase Auth address from a username.
  ///
  /// AppUser has no email field, and the address cannot be looked up in
  /// Firestore before signing in, so it has to be derivable offline. The
  /// `users` domain keeps these addresses out of real inboxes.
  static const String authEmailDomain = String.fromEnvironment(
    'AUTH_EMAIL_DOMAIN',
    defaultValue: 'users.studyflow.app',
  );

  /// Firebase Auth address for a username.
  ///
  /// Must stay identical to tools/provision_auth.mjs, otherwise the account
  /// that script created cannot be found at login time.
  static String emailForUsername(String username) {
    final normalized = username.trim().toLowerCase();
    return '$normalized@$authEmailDomain';
  }


  /// Strictly enforces device binding and account sharing prevention.
  /// NO developers or special usernames (e.g., 'abn') can bypass these checks.
  Future<AppUser> secureLogin(String username, String password) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      throw Exception('اسم المستخدم مطلوب');
    }
    if (password.isEmpty) {
      throw Exception('كلمة المرور مطلوبة');
    }
    final appVersion = await _resolveAppVersion();

    // 1. GENERATE FINGERPRINT
    final currentFingerprint = await _hardwareService.getDeviceFingerprint();

    // 2. ESTABLISH THE FIREBASE AUTH SESSION
    // This has to come first. No Firestore read can succeed until
    // request.auth is non-null, and getUserData() resolves the caller as
    // users/{uid}, so the account's uid must be the users document id.
    await _signIn(normalizedUsername, password);

    // 3. BLACKLIST CHECK: Prevent blocked devices from logging in
    final blacklistDoc = await _firestore.collection('blacklisted_devices').doc(currentFingerprint).get();
    if (blacklistDoc.exists) {
      final reason = blacklistDoc.data()?['reason'] ?? 'هذا الجهاز محظور من الاستخدام بشكل نهائي';
      debugPrint('🚫 [Security] Blacklisted device denial: Fingerprint=$currentFingerprint');
      throw Exception(reason);
    }

    // 3. FETCH USER
    final query = await _firestore
        .collection('users')
        .where('username', isEqualTo: normalizedUsername)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('هذا الحساب غير مسجل، يرجى مراجعة المطور');
    }

    final doc = query.docs.first;
    final data = doc.data();
    final user = AppUser.fromFirestore(doc.id, data);

    // 4. USER BAN CHECK: Zero-tolerance policy
    if (user.isBanned) {
      debugPrint('🚫 [Security] Banned account denial: UID=${user.uid}, Username=${user.username}');
      throw Exception('تم حظر حسابك بسبب: ${user.banReason ?? "مشاركة الحساب مع جهاز آخر"}');
    }

    // 5. DEVICE BINDING & ACCOUNT SHARING DETECTION
    final primaryFingerprint = user.primaryDeviceFingerprint;

    if (primaryFingerprint == null || primaryFingerprint.isEmpty) {
      // FIRST LOGIN: Bind this device as the primary one
      await doc.reference.update({
        'primaryDeviceFingerprint': currentFingerprint,
        'displayName': user.displayName.isEmpty ? user.username : user.displayName,
        'hardwareId': currentFingerprint, // Migration fallback
        'appVersion': appVersion,
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [Security] Device binding success: User=${user.username} -> Fingerprint=$currentFingerprint');
      
      // Refresh user data after binding
      return AppUser.fromFirestore(doc.id, {
        ...data,
        'primaryDeviceFingerprint': currentFingerprint,
        'appVersion': appVersion,
      });
    } 
    
    if (primaryFingerprint != currentFingerprint) {
      // 🚨 VIOLATION DETECTED: ACCOUNT SHARING DETECTED
      debugPrint('🚨 [Security] Device mismatch denial: User=${user.username}');
      debugPrint('   Expected: $primaryFingerprint');
      debugPrint('   Received: $currentFingerprint');
      
      // IMMEDIATE ZERO-TOLERANCE EXECUTION
      await _executeImmediateBan(doc.reference, user, currentFingerprint);
      
      throw Exception('تم حظر حسابك بسبب مشاركة حسابك مع جهاز آخر. هذا الجهاز وجهازك الأصلي تم منعهما نهائيا.');
    }

    await _updateLoginMetadata(doc.reference, appVersion);
    debugPrint('✅ [Security] Secure Login successful for: ${user.username}');
    return user;
  }

  /// Signs in with Firebase Auth before touching Firestore.
  ///
  /// Every rule in firestore.rules is gated on isAuthenticated(), and
  /// getUserData() resolves the caller as users/{request.auth.uid}, so the
  /// Firebase uid has to equal the users document id. tools/provision_auth.mjs
  /// creates the accounts with exactly that uid; this method only has to find
  /// the address derived from the username.
  Future<void> _signIn(String username, String password) async {
    final email = emailForUsername(username);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint(
        '🔐 [Auth] Firebase session established for uid=${credential.user?.uid}',
      );
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('اسم المستخدم أو كلمة المرور غير صحيحة.');
        case 'user-disabled':
          throw Exception('هذا الحساب معطّل. راجع مدير النظام.');
        case 'too-many-requests':
          throw Exception('محاولات كثيرة متتالية. انتظر قليلاً ثم حاول مجدداً.');
        default:
          throw Exception('تعذّر تسجيل الدخول: ${e.message ?? e.code}');
      }
    } catch (e) {
      debugPrint('❌ [Auth] sign-in failed: $e');
      throw Exception('تعذّر الاتصال بخادم المصادقة. تحقق من الاتصال.');
    }
  }

  Future<String> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _updateLoginMetadata(
    DocumentReference<Map<String, dynamic>> userRef,
    String appVersion,
  ) async {
    try {
      await userRef.update({
        'appVersion': appVersion,
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ [Auth] Failed to update appVersion metadata: $e');
    }
  }

  /// Part of the ZERO-TOLERANCE policy. Bans the user and blacklists both devices.
  Future<void> _executeImmediateBan(DocumentReference userRef, AppUser user, String newFingerprint) async {
    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();

    // 1. BAN USER
    batch.update(userRef, {
      'isBanned': true,
      'banReason': 'مشاركة الحساب',
      'bannedAt': now,
    });

    // 2. BLACKLIST PRIMARY DEVICE
    if (user.primaryDeviceFingerprint != null) {
      final oldRef = _firestore.collection('blacklisted_devices').doc(user.primaryDeviceFingerprint);
      batch.set(oldRef, {
        'fingerprint': user.primaryDeviceFingerprint,
        'uid': user.uid,
        'username': user.username,
        'displayName': user.displayName,
        'reason': 'مشاركة الحساب (الجهاز الأصلي)',
        'bannedAt': now,
      });
    }

    // 3. BLACKLIST NEW DEVICE
    final newRef = _firestore.collection('blacklisted_devices').doc(newFingerprint);
    batch.set(newRef, {
      'fingerprint': newFingerprint,
      'uid': user.uid,
      'username': user.username,
      'displayName': user.displayName,
      'reason': 'مشاركة الحساب (جهاز غير مصرح به)',
      'bannedAt': now,
    });

    // 4. LOG SECURITY EVENT
    final eventRef = _firestore.collection('security_events').doc();
    batch.set(eventRef, {
      'type': 'account_sharing_detected',
      'uid': user.uid,
      'username': user.username,
      'displayName': user.displayName,
      'oldFingerprint': user.primaryDeviceFingerprint,
      'newFingerprint': newFingerprint,
      'action': 'ban_both_devices',
      'timestamp': now,
    });

    // 5. CREATE GLOBAL ANNOUNCEMENT
    final announceRef = _firestore.collection('announcements').doc();
    final banMsg = 'تم حظر ${user.displayName.isEmpty ? user.username : user.displayName} بسبب مشاركة حسابه مع جهاز آخر';
    batch.set(announceRef, {
      'title': '⚠️ تنبيه أمني',
      'body': banMsg,
      'type': 'security',
      'authorName': 'System',
      'targetAudience': 'all',
      'createdAt': now,
    });

    await batch.commit();
    debugPrint('🛡️ [Security] Immediate ban executed for ${user.username}. Both devices blacklisted.');
    debugPrint('📢 [Security] Security announcement published for ${user.username}');
  }

  }
