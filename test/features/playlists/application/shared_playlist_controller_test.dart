import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../playlists_test_doubles.dart';

final _server = NotifierProvider<_Server, int>(_Server.new);

final class _Server extends Notifier<int> {
  @override
  int build() => 0;

  void next() => state++;
}

SharedPlaylist _shared(String name, String id) => SharedPlaylist(
  name: name,
  favorites: false,
  ownerName: '阿柚',
  ownerAvatarHash: '',
  items: [song(id)],
);

void main() {
  late FakePlaylistApi server;

  setUp(() {
    server = FakePlaylistApi()..sharedPlaylist = _shared('夜跑', 'a');
  });

  Future<(OpenedPlaylists, ProviderSubscription<SharedPlaylistState>)> open({
    bool restored = true,
  }) async {
    final opened = await playlistsContainer(
      playlists: server,
      restored: restored,
    );
    final page = opened.container.listen(
      sharedPlaylistControllerProvider(shareIdA),
      (_, _) {},
    );
    expect(page.read().loading, isTrue);
    await pumpEventQueue();
    return (opened, page);
  }

  test('reads the shared playlist without asking for an identity', () async {
    final (opened, page) = await open(restored: false);

    expect(page.read().playlist?.name, '夜跑');
    expect(server.calls, ['shared $shareIdA']);
    expect(opened.api.getMeCalls, 0);
    expect(opened.api.createMemberCalls, 0);
  });

  test('a share that is gone is expired', () async {
    server.sharedPlaylist = null;
    final (_, page) = await open();

    expect(page.read().expired, isTrue);
    expect(page.read().playlist, isNull);
  });

  test('a failed read says why, and a retry reads again', () async {
    server.failNext('shared', networkError);
    final (opened, page) = await open();
    expect(page.read().error, networkError.message);

    await opened.container
        .read(sharedPlaylistControllerProvider(shareIdA).notifier)
        .load();

    expect(page.read().error, isNull);
    expect(page.read().playlist?.items, hasLength(1));
  });

  test('a rate limited read shows the wait', () async {
    server.failNext(
      'shared',
      apiError(
        'RATE_LIMITED',
        status: 429,
        retryAfter: const Duration(seconds: 30),
      ),
    );
    final (_, page) = await open();

    expect(page.read().error, contains('30'));
  });

  group('after a server switch', () {
    late FakePlaylistApi other;
    late OpenedPlaylists opened;

    Override switchable() => playlistApiProvider.overrideWith(
      (ref) => ref.watch(_server) == 0 ? server : other,
    );

    setUp(() async {
      other = FakePlaylistApi()..sharedPlaylist = _shared('别处', 'b');
      opened = await playlistsContainer(
        playlists: server,
        playlistApi: switchable(),
      );
    });

    test('a read answered as the server changes is dropped, and the share '
        'is never asked of the new server', () async {
      final shown = <String>[];
      final page = opened.container.listen(
        sharedPlaylistControllerProvider(shareIdA),
        (_, next) {
          final name = next.playlist?.name;
          if (name != null) shown.add(name);
        },
      );
      final stale = server.hold('shared');
      await pumpEventQueue();

      opened.container.read(_server.notifier).next();
      stale.complete();
      await pumpEventQueue();
      await opened.container
          .read(sharedPlaylistControllerProvider(shareIdA).notifier)
          .load();

      expect(shown, isEmpty);
      expect(other.count('shared'), 0);
      expect(page.read().expired, isTrue);
      expect(page.read().playlist, isNull);
    });

    test('a copy is sent to neither server', () async {
      opened.container
        ..listen(myPlaylistsControllerProvider, (_, _) {})
        ..listen(sharedPlaylistControllerProvider(shareIdA), (_, _) {});
      await pumpEventQueue();
      final controller = opened.container.read(
        sharedPlaylistControllerProvider(shareIdA).notifier,
      );

      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      final result = await controller.copy('夜跑');

      expect(
        result,
        isA<MutationNotSent<MyPlaylist>>().having(
          (r) => r.message,
          'message',
          serverChangedNotice,
        ),
      );
      expect(server.count('copyShared') + other.count('copyShared'), 0);
    });
  });

  test('a copy on the same server is made in my playlists', () async {
    final (opened, _) = await open();
    final list = opened.container.listen(
      myPlaylistsControllerProvider,
      (_, _) {},
    );
    await pumpEventQueue();

    final result = await opened.container
        .read(sharedPlaylistControllerProvider(shareIdA).notifier)
        .copy(' 夜跑 ');

    final copied = (result as MutationSucceeded<MyPlaylist>).value;
    expect(server.calls, contains('copyShared $shareIdA 夜跑'));
    expect(list.read().playlists, contains(copied));
  });
}
