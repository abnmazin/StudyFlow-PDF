import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/tutorial_video_config.dart';

void main() {
  test('reads and writes the shared YouTube URL field', () {
    const config = TutorialVideoConfig(
      youtubeUrl: 'https://www.youtube.com/watch?v=abc12345678',
    );

    final restored = TutorialVideoConfig.fromFirestore(config.toFirestore());

    expect(restored.youtubeUrl, config.youtubeUrl);
  });

  test('missing remote configuration produces an empty URL', () {
    expect(TutorialVideoConfig.fromFirestore(null).youtubeUrl, isEmpty);
    expect(
      TutorialVideoConfig.fromFirestore(<String, dynamic>{}).youtubeUrl,
      isEmpty,
    );
    expect(
      TutorialVideoConfig.fromFirestore(<String, dynamic>{'youtube_url': 42})
          .youtubeUrl,
      isEmpty,
    );
  });
}