import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/features/playback/application/audio_engine.dart';
import 'package:alisten/features/playback/data/unavailable_audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';

void main() {
  test('every load fails, and nothing else fails or reports events', () async {
    const engine = UnavailableAudioEngine();
    final events = <AudioEngineEvent>[];
    final subscription = engine.events.listen(events.add);
    addTearDown(subscription.cancel);

    await expectLater(
      engine.load(
        AudioLoadRequest(
          load: 1,
          identity: const PlaybackIdentity(entryId: 'entry', startedAtMs: 1),
          uri: Uri.parse('https://media.test/1'),
          meta: testTrackMeta,
          durationMs: 180000,
          positionMs: 0,
        ),
      ),
      throwsA(isA<AudioUnavailableException>()),
    );
    await engine.play();
    await engine.pause();
    await engine.seek(const Duration(seconds: 3));
    await engine.setVolume(0.5);
    await engine.release();

    expect(engine.position, Duration.zero);
    expect(events, isEmpty);
  });
}
