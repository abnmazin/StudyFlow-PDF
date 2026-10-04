import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/tutorial_video_config.dart';
import 'university_service.dart';

/// Reads and writes the shared dashboard tutorial link.
///
/// Firestore rules remain the security boundary. [currentUser] only turns a
/// denied write into a useful message before the request reaches the network.
class TutorialSettingsService {
  TutorialSettingsService({FirebaseFirestore? firestore, this.currentUser})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collectionPath = 'app_config';
  static const String documentId = 'tutorial';

  final FirebaseFirestore _firestore;
  AppUser? currentUser;

  DocumentReference<Map<String, dynamic>> get _document =>
      _firestore.collection(collectionPath).doc(documentId);

  Stream<TutorialVideoConfig> watchTutorial() {
    return _document.snapshots().map(
      (snapshot) => TutorialVideoConfig.fromFirestore(snapshot.data()),
    );
  }

  Future<TutorialVideoConfig> getTutorial() async {
    final snapshot = await _document.get();
    return TutorialVideoConfig.fromFirestore(snapshot.data());
  }

  Future<void> saveTutorialUrl(String value) async {
    final user = currentUser;
    if (user == null) throw UnsupportedError('يجب تسجيل الدخول أولاً');
    if (!user.isAdmin) {
      throw UnsupportedError('تعديل شرح التطبيق متاح للمدير فقط');
    }

    final url = value.trim();
    if (url.isEmpty) {
      await _document.set(
        const TutorialVideoConfig().toFirestore(updatedBy: null),
        SetOptions(merge: true),
      );
      return;
    }

    final videoId = UniversityService.videoIdFromUrl(url);
    if (videoId == null) {
      throw const FormatException('الرابط غير صالح. أدخل رابط فيديو يوتيوب.');
    }

    await _document.set(
      TutorialVideoConfig(
        youtubeUrl: 'https://www.youtube.com/watch?v=$videoId',
      ).toFirestore(updatedBy: user.displayName),
      SetOptions(merge: true),
    );
  }
}
