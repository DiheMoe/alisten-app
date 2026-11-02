import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/playlist_controller.dart';
import 'package:alisten/features/search/application/search_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchHarness harness;

  setUp(() async {
    harness = await SearchHarness.open();
  });

  tearDown(() => harness.dispose());

  const neteasePlaylist = PlaylistKey(TrackSource.netease, 'playlist');

  test('opening a playlist and returning keeps the search as it was', () async {
    await harness.search.submit('jazz', source: TrackSource.netease);
    final before = harness.state;

    final subscription = harness.container.listen(
      playlistControllerProvider(neteasePlaylist),
      (_, _) {},
    );
    final detail = await harness.container.read(
      playlistControllerProvider(neteasePlaylist).future,
    );
    expect(detail.tracks, hasLength(21));
    subscription.close();
    await pumpEventQueue();

    expect(harness.state.keyword, 'jazz');
    expect(harness.state.source, TrackSource.netease);
    expect(harness.state.status, isA<SearchLoaded>());
    expect(harness.state.tracks, hasLength(before.tracks.length));
    expect(harness.state.playlists, hasLength(before.playlists.length));
    final sent = [for (final request in harness.requests) request['type']];
    expect(sent, ['search.tracks', 'search.playlists', 'playlist.tracks']);
  });

  test('a source without playlists fails at once without a request', () async {
    const qqPlaylist = PlaylistKey(TrackSource.qq, 'playlist');
    final subscription = harness.container.listen(
      playlistControllerProvider(qqPlaylist),
      (_, _) {},
    );
    await pumpEventQueue();

    final state = harness.container.read(
      playlistControllerProvider(qqPlaylist),
    );
    expect(state.hasError, isTrue);
    expect(state.error, isA<PlaylistUnavailable>());
    expect((state.error! as PlaylistUnavailable).message, '该来源不支持歌单');
    expect(harness.requests, isEmpty);
    subscription.close();
  });

  test('a playlist opened while the room reconnects waits for the '
      'connection and is asked for once it is open', () async {
    harness.transport.disconnect();
    await pumpEventQueue();
    expect(
      harness.container.read(roomControllerProvider).status,
      RoomConnectionStatus.reconnecting,
    );

    final subscription = harness.container.listen(
      playlistControllerProvider(neteasePlaylist),
      (_, _) {},
    );
    await pumpEventQueue();
    var state = harness.container.read(
      playlistControllerProvider(neteasePlaylist),
    );
    expect(state.isLoading, isTrue);
    expect(state.hasError, isFalse);
    expect(harness.requests, isEmpty);

    harness.transport.emitHello();
    await pumpEventQueue();

    state = harness.container.read(playlistControllerProvider(neteasePlaylist));
    expect(state.value?.tracks, hasLength(21));
    final sent = [for (final request in harness.requests) request['type']];
    expect(sent, ['playlist.tracks']);
    subscription.close();
  });
}
