import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../firebase_options.dart';
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
  /// Many usernames in this project are Arabic or contain spaces, and Firebase
  /// rejects a local part containing a space, so everything outside
  /// [a-z0-9._-] is dropped. A name that reduces to nothing falls back to a
  /// hash of the username, which is computable before signing in.
  ///
  /// MUST stay identical to emailLocalPart in
  /// tools/provision_auth.mjs, otherwise this looks for an address that script
  /// never created and login fails.
  static String emailForUsername(String username) {
    final lower = username.trim().toLowerCase();
    var ascii = lower.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    ascii = ascii.replaceAll(RegExp(r'^[._-]+'), '');
    ascii = ascii.replaceAll(RegExp(r'[._-]+$'), '');
    ascii = ascii.replaceAll(RegExp(r'\.{2,}'), '.');
    if (ascii.length < 2) {
      final digest = sha256.convert(utf8.encode(lower)).toString();
      return 'u${digest.substring(0, 12)}@$authEmailDomain';
    }
    return '$ascii@$authEmailDomain';
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
    final signedInUid = await _signIn(normalizedUsername, password);


    // 3. BLACKLIST CHECK: Prevent blocked devices from logging in
    final blacklistDoc = await _firestore.collection('blacklisted_devices').doc(currentFingerprint).get();
    if (blacklistDoc.exists) {
      final reason = blacklistDoc.data()?['reason'] ?? 'هذا الجهاز محظور من الاستخدام بشكل نهائي';
      debugPrint('🚫 [Security] Blacklisted device denial: Fingerprint=$currentFingerprint');
      throw Exception(reason);
    }

    // 3. FETCH USER
    // Read by document id, taken from the verified credential rather than
    // from what was typed. The /users rule only grants a get when the id
    // equals request.auth.uid, so a get succeeds while a query on username
    // can never be proven safe by the rules and is denied outright. Reading
    // the credential also means the typed name can no longer decide whose
    // profile is loaded.
    final doc = await _firestore.collection('users').doc(signedInUid).get();

    if (!doc.exists) {
      debugPrint(
        '🚫 [Security] No users document for uid=$signedInUid. The Auth '
        'account exists but the profile was never provisioned.',
      );
      throw Exception('هذا الحساب غير مسجل، يرجى مراجعة المطور');
    }

    final data = doc.data();
    final user = AppUser.fromFirestore(doc.id, data!);

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

  /// Returns the uid Firebase Auth resolved for these credentials.
  ///
  /// Every rule in firestore.rules is gated on isAuthenticated(), and
  /// getUserData() resolves the caller as users/{request.auth.uid}, so the
  /// Firebase uid has to equal the users document id. tools/provision_auth.mjs
  /// creates the accounts with exactly that uid; this method only has to find
  /// the address derived from the username.
  Future<String> _signIn(String username, String password) async {
    final email = emailForUsername(username);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('تعذّر تسجيل الدخول: لم يُرجَع معرّف المستخدم.');
      }
      debugPrint('🔐 [Auth] Firebase session established for uid=$uid');
      return uid;
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
    final now = FieldValue.serverTimestamp();

    // The durable ban record is admin-only in firestore.rules, so a client
    // cannot write it. Firestore batches are atomic, so keeping it in one
    // batch would have meant the refusal of a single write discarded the rest
    // and the caller surfaced a permission error instead of the ban notice.
    // The access denial itself does not depend on any of this succeeding.
    try {
      final batch = _firestore.batch();

      // 1. BAN USER
      batch.update(userRef, {
        'isBanned': true,
        'banReason': 'مشاركة الحساب',
        'bannedAt': now,
      });

      // 2. BLACKLIST PRIMARY DEVICE
      if (user.primaryDeviceFingerprint != null) {
        final oldRef = _firestore
            .collection('blacklisted_devices')
            .doc(user.primaryDeviceFingerprint!);
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

      // 4. CREATE GLOBAL ANNOUNCEMENT
      final announceRef = _firestore.collection('announcements').doc();
      final banMsg =
          'تم حظر ${user.displayName.isEmpty ? user.username : user.displayName} بسبب مشاركة حسابه مع جهاز آخر';
      batch.set(announceRef, {
        'title': '⚠️ تنبيه أمني',
        'body': banMsg,
        'type': 'security',
        'authorName': 'System',
        'targetAudience': 'all',
        'createdAt': now,
      });

      await batch.commit();
    } catch (e) {
      debugPrint(
        '⚠️ [Security] Durable ban record not written, the rules reserve it '
        'for admins and an admin has to record it from the dashboard: $e',
      );
    }

    // 5. LOG SECURITY EVENT
    // The one write a client is still allowed to make, and the one worth
    // keeping even when the record above is refused, so it gets its own batch.
    try {
      await _firestore.collection('security_events').add({
        'type': 'account_sharing_detected',
        'uid': user.uid,
        'username': user.username,
        'displayName': user.displayName,
        'oldFingerprint': user.primaryDeviceFingerprint,
        'newFingerprint': newFingerprint,
        'action': 'ban_both_devices',
        'timestamp': now,
      });
    } catch (e) {
      debugPrint('⚠️ [Security] Could not append the security event: $e');
    }

    debugPrint(
      '🚫 [Security] Device mismatch handled for ${user.username}. The login is '
      'refused whether or not the durable record could be written.',
    );
  }

  /// Creates a Firebase Auth account from the admin UI, with a password the
  /// admin chooses, and writes the matching users/{uid} profile.
  ///
  /// Firebase Auth passwords are write-only, so no client API can set another
  /// person's password. What a client *can* do is create an account, and
  /// createUserWithEmailAndPassword signs the caller in as the new user. On
  /// the default app instance that would sign the admin out mid-task, so the
  /// account is created on a secondary FirebaseApp with the same options: its
  /// session is independent, and signing out of it leaves the admin's own
  /// session untouched.
  ///
  /// Note the account's address is derived from the username, so the username
  /// is what the new owner types at the login screen, not the address.
  Future<String> provisionAccount({
    required String username,
    required String password,
    required String displayName,
    required String role,
    String? universityId,
  }) async {
    if (username.trim().isEmpty) {
      throw Exception('اسم المستخدم مطلوب');
    }
    if (password.length < 6) {
      throw Exception('كلمة المرور يجب ألا تقل عن 6 أحرف');
    }

    final email = emailForUsername(username);

    const provisioningAppName = 'account-provisioning';
    final existing = Firebase.apps
        .where((a) => a.name == provisioningAppName)
        .toList();
    final provisioningApp = existing.isNotEmpty
        ? existing.first
        : await Firebase.initializeApp(
            name: provisioningAppName,
            options: DefaultFirebaseOptions.currentPlatform,
          );
    final auth = FirebaseAuth.instanceFor(app: provisioningApp);

    String? uid;
    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      uid = credential.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('لم يُرجع Firebase معرّفًا للمستخدم الجديد.');
      }

      // authProvisioned marks the profile as backed by a real Auth account,
      // which is what separates it from the orphaned documents the old
      // add-user form produced, where a random document id could never sign in.
      await _firestore.collection('users').doc(uid).set({
        'username': username.trim(),
        'displayName': displayName.trim().isEmpty ? username.trim() : displayName.trim(),
        'role': role,
        'authProvisioned': true,
        'createdAt': FieldValue.serverTimestamp(),
        // primaryDeviceFingerprint is intentionally left unset. The first
        // person to sign in binds their own device, and a second one from
        // anywhere else is what the sharing policy is for.
        if (universityId != null && universityId.isNotEmpty)
          'universityId': universityId,
      });
    } on FirebaseAuthException catch (e) {
      throw Exception(_describeProvisioningError(e.code));
    } finally {
      // Never leave the provisioning instance holding a session.
      try {
        await auth.signOut();
      } catch (_) {}
    }

    debugPrint('✅ [Auth] Provisioned $email as uid=$uid with role=$role');
    return uid;
  }

  String _describeProvisioningError(String code) {
    switch (code) {
      case 'email-already-exists':
        return 'يوجد حساب بهذا اسم المستخدم بالفعل.';
      case 'invalid-email':
        return 'اسم المستخدم لا ينتج بريدًا صالحًا.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة، استخدم 6 أحرف على الأقل.';
      case 'operation-not-allowed':
        return 'يجب تفعيل Email/Password في Authentication ← Sign-in method.';
      case 'network-request-failed':
        return 'تعذّر الاتصال بخادم المصادقة. تحقق من الاتصال.';
      default:
        return 'تعذّر إنشاء الحساب: $code';
    }
  }
}
