import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void expectNotLoaded(AppConfig config, String mediaUrl) {
    fakeAsync((async) {
      final h = PlaybackHarness(async, config: config);
      h.hello(
        nowPlayingWith(mediaUrl: mediaUrl),
        serverNow: trackStart + 30000,
      );
      async.elapse(const Duration(seconds: 5));

      expect(h.engine.loadCalls, 0);
      expect(h.state.status, LocalPlaybackStatus.error);
      h.dispose();
    });
  }

  test('non-HTTP media sources are not loaded', () {
    expectNotLoaded(testAppConfig, 'file:///private/track');
  });

  test('release playback rejects an insecure resolved media URL', () {
    expectNotLoaded(
      AppConfig(baseUrl: 'https://server.test', isRelease: true),
      'http://media.test/a',
    );
  });
}
