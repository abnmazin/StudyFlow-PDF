import 'package:cloud_firestore/cloud_firestore.dart';

/// The shared YouTube tutorial configured by an administrator.
///
/// Stored at `app_config/tutorial` so changing the onboarding video does not
/// require rebuilding the app on every device.
class TutorialVideoConfig {
  final String youtubeUrl;

  const TutorialVideoConfig({this.youtubeUrl = ''});

  factory TutorialVideoConfig.fromFirestore(
    Map<String, dynamic>? data,
  ) {
    final value = data?['youtube_url'];
    return TutorialVideoConfig(
      youtubeUrl: value is String ? value.trim() : '',
    );
  }

  Map<String, dynamic> toFirestore({String? updatedBy}) => {
    'youtube_url': youtubeUrl,
    'updatedAt': FieldValue.serverTimestamp(),
    if (updatedBy != null && updatedBy.trim().isNotEmpty)
      'updatedBy': updatedBy.trim(),
  };
}
