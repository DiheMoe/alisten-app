import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playlists_test_doubles.dart';

const _a = Track(source: TrackSource.netease, id: 'a');
const _key = 'netease:a';

final _server = NotifierProvider<_Server, int>(_Server.new);

final class _Server extends Notifier<int> {
  @override
  int build() => 0;

  void next() => state++;
}

void main() {
  late FakePlaylistApi server;
  late FakePlaylistApi other;
  late OpenedPlaylists opened;
  late ProviderSubscription<MyPlaylistsState> list;
  late MyPlaylistsController controller;
  final pl1 = playlist('pl-1');
  final pl2 = playlist('pl-2');

  setUp(() async {
    server = FakePlaylistApi()
      ..playlists.addAll([favoritesPlaylist, pl1, pl2])
      ..contents['pl-1'] = []
      ..contents['pl-2'] = [];
    other = FakePlaylistApi()..playlists.add(playlist('elsewhere'));
    opened = await playlistsContainer(
      playlistApi: playlistApiProvider.overrideWith(
        (ref) => ref.watch(_server) == 0 ? server : other,
      ),
    );
    list = opened.container.listen(myPlaylistsControllerProvider, (_, _) {});
    await pumpEventQueue();
    controller = opened.container.read(myPlaylistsControllerProvider.notifier);
  });

  Set<String>? ticked() => list.read().memberships[_key];

  List<String> writes([FakePlaylistApi? api]) => [
    for (final call in (api ?? server).calls)
      if (call.startsWith('add ') || call.startsWith('remove ')) call,
  ];

  IdentityController identity() =>
      opened.container.read(identityControllerProvider.notifier);

  Future<void> signOut() => identity().signOut((api) => api.logout());

  Future<void> signIn() => identity().adoptSession(
    (api) => api.login(username: 'mao', password: 'password1'),
  );

  void switchServer() => opened.container.read(_server.notifier).next();

  group('containing', () {
    test('writes the playlists that hold the song', () async {
      server.contents['pl-2'] = [song('a')];

      expect(await controller.containing(_a), isNull);
      expect(ticked(), {'pl-2'});
    });

    test('a read overtaken by a later one is not written', () async {
      final first = server.hold('containing');
      final early = controller.containing(_a);
      await pumpEventQueue();
      server.contents['pl-1'] = [song('a')];
      await controller.containing(_a);
      first.complete();
      expect(await early, isNull);

      expect(ticked(), {'pl-1'});
    });

    test('a failed read returns why', () async {
      server.failNext('containing', networkError);

      expect(await controller.containing(_a), networkError.message);
      expect(ticked(), isNull);
    });
  });

  group('setMembership', () {
    test('one tick sends one add', () async {
      final result = await controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();

      expect(result, isA<MutationSucceeded<void>>());
      expect(writes(), ['add pl-1 $_key']);
      expect(ticked(), {'pl-1'});
    });

    test('the last tap wins: taps back and forth during an add send '
        'nothing more', () async {
      final gate = server.hold('add');
      final first = controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();

      expect(await controller.setMembership(pl1, _a, included: false), isNull);
      expect(await controller.setMembership(pl1, _a, included: true), isNull);
      gate.complete();

      expect(await first, isA<MutationSucceeded<void>>());
      await pumpEventQueue();
      expect(writes(), ['add pl-1 $_key']);
      expect(ticked(), {'pl-1'});
    });

    test('the last tap wins: an untick during an add removes it '
        'afterwards', () async {
      final gate = server.hold('add');
      final first = controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();

      expect(await controller.setMembership(pl1, _a, included: false), isNull);
      expect(ticked(), isEmpty);
      gate.complete();

      expect(await first, isA<MutationSucceeded<void>>());
      await pumpEventQueue();
      expect(writes(), ['add pl-1 $_key', 'remove pl-1 $_key']);
      expect(ticked(), isEmpty);
    });

    test('a conflict rolls back and tells the server message', () async {
      server.failNext('add', apiError('CONFLICT', message: '这首歌还在准备，准备好之后再保存'));

      final result = await controller.setMembership(pl1, _a, included: true);

      expect(
        result,
        isA<MutationFailed<void>>().having(
          (r) => r.message,
          'message',
          '这首歌还在准备，准备好之后再保存',
        ),
      );
      expect(ticked(), isEmpty);
    });

    test('a rate limit rolls back and was not carried out', () async {
      server.failNext(
        'add',
        apiError('RATE_LIMITED', message: '操作太频繁，请稍后再试。', status: 429),
      );

      final result = await controller.setMembership(pl1, _a, included: true);

      expect(result, isA<MutationNotSent<void>>());
      expect(ticked(), isEmpty);
      expect(writes(), ['add pl-1 $_key']);
    });

    test('a lost answer rolls back, then the server state is read', () async {
      server
        ..onCall = (method) {
          if (method == 'add') server.contents['pl-1']!.insert(0, song('a'));
        }
        ..failNext('add', networkError);
      final calibration = server.hold('containing');

      final result = await controller.setMembership(pl1, _a, included: true);
      expect(result, isA<MutationUnknown<void>>());
      expect(ticked(), isEmpty, reason: 'rolled back at once');

      calibration.complete();
      await pumpEventQueue();
      expect(ticked(), {'pl-1'}, reason: 'calibrated by the server');
    });

    test('a read that comes back during a sync keeps the playlist being '
        'synced as ticked', () async {
      final add = server.hold('add');
      final read = server.hold('containing');
      final sync = controller.setMembership(pl1, _a, included: true);
      final reading = controller.containing(_a);
      await pumpEventQueue();

      read.complete();
      await reading;
      expect(ticked(), contains('pl-1'));

      add.complete();
      await sync;
    });

    test('after a sync the memberships and the list are read again', () async {
      final reads = server.count('containing');
      final lists = server.count('listMine');

      await controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();

      expect(server.count('containing'), reads + 1);
      expect(server.count('listMine'), lists + 1);
    });

    test('a sheet closed during a sync does not stop it; the controller '
        'goes only once it ends', () async {
      final add = server.hold('add');
      final sync = controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();

      list.close();
      await opened.container.pump();
      expect(opened.container.exists(myPlaylistsControllerProvider), isTrue);

      add.complete();
      expect(await sync, isA<MutationSucceeded<void>>());
      await opened.container.pump();
      expect(opened.container.exists(myPlaylistsControllerProvider), isFalse);
      expect(writes(), ['add pl-1 $_key']);
    });

    test('a failure after a confirmed request rolls back to what it '
        'confirmed', () async {
      final add = server.hold('add');
      final first = controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();
      await controller.setMembership(pl1, _a, included: false);
      server.failNext('remove', apiError('CONFLICT', message: '歌单已经变了'));
      final calibration = server.hold('containing');
      add.complete();

      expect(await first, isA<MutationFailed<void>>());
      expect(writes(), ['add pl-1 $_key', 'remove pl-1 $_key']);
      expect(ticked(), {
        'pl-1',
      }, reason: 'the add stands; only the remove rolls back');
      calibration.complete();
      await pumpEventQueue();
      expect(ticked(), {'pl-1'});
    });

    test('syncs on two playlists at once keep each other and the controller '
        'until the last one ends', () async {
      final first = server.hold('add');
      final second = server.hold('add');
      final syncs = [
        controller.setMembership(pl1, _a, included: true),
        controller.setMembership(pl2, _a, included: true),
      ];
      await pumpEventQueue();
      list.close();

      first.complete();
      await syncs[0];
      await opened.container.pump();
      await pumpEventQueue();
      expect(opened.container.exists(myPlaylistsControllerProvider), isTrue);
      expect(
        opened.container.read(myPlaylistsControllerProvider).memberships[_key],
        {'pl-1', 'pl-2'},
        reason: 'the re-read after the first sync keeps the one still syncing',
      );

      second.complete();
      await syncs[1];
      await opened.container.pump();
      await pumpEventQueue();
      expect(opened.container.exists(myPlaylistsControllerProvider), isFalse);
      expect(writes(), ['add pl-1 $_key', 'add pl-2 $_key']);
    });

    test('a sync whose owner changed sends nothing more', () async {
      final add = server.hold('add');
      final sync = controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();
      await controller.setMembership(pl1, _a, included: false);

      await signOut();
      await pumpEventQueue();
      add.complete();
      // 加入已经在原来的账号上完成；之后的取消随归属一起作废。
      expect(await sync, isA<MutationSucceeded<void>>());
      await pumpEventQueue();

      expect(writes(), ['add pl-1 $_key']);
      expect(list.read().guest, isTrue);
      expect(list.read().memberships, isEmpty);
    });

    test('a refused tick replaces the identity, tells its text once and '
        'leaves the new identity alone', () async {
      // 服务端为替换的身份新建的是游客。
      opened.api.account = null;
      server.failNext('add', apiError('UNAUTHORIZED', status: 401));

      final result = await controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();

      expect(
        result,
        isA<MutationFailed<void>>()
            .having((r) => r.code, 'code', 'UNAUTHORIZED')
            .having((r) => r.message, 'message', signedOutNotice),
      );
      expect(opened.api.createMemberCalls, 1);
      expect(writes(), ['add pl-1 $_key']);
      expect(list.read().guest, isTrue);
      expect(list.read().memberships, isEmpty);
    });
  });

  group('copyTracks', () {
    final from = playlist('from');
    const b = Track(source: TrackSource.qq, id: 'b');

    // 服务端只复制来源歌单里确实有的歌。
    setUp(() {
      server.playlists.add(from);
      server.contents['from'] = [song('a'), song('b', source: TrackSource.qq)];
    });

    test('copies to every target and tells how many were new', () async {
      server.contents['pl-1'] = [song('a')];
      final lists = server.count('listMine');

      final results = await controller.copyTracks(
        from,
        const [_a, b],
        [pl1, pl2],
      );
      await pumpEventQueue();

      expect([for (final (target, _) in results) target.id], ['pl-1', 'pl-2']);
      expect(
        [
          for (final (_, result) in results)
            (result as MutationSucceeded<int>).value,
        ],
        [1, 2],
      );
      expect(server.count('listMine'), lists + 1);
    });

    test('a target that fails is told apart from those that work', () async {
      server.failNext(
        'copy',
        apiError('NOT_FOUND', message: '歌单不存在', status: 404),
      );

      final lists = server.count('listMine');

      final results = await controller.copyTracks(from, const [_a], [pl1, pl2]);
      await pumpEventQueue();

      final failures = [
        for (final (target, result) in results)
          if (result is MutationFailed<int>) target.id,
      ];
      expect(failures, ['pl-1']);
      expect(
        results.first.$2,
        isA<MutationFailed<int>>()
            .having((r) => r.code, 'code', 'NOT_FOUND')
            .having((r) => r.message, 'message', '歌单不存在'),
      );
      expect(
        results.where((r) => r.$2 is MutationSucceeded<int>),
        hasLength(1),
      );
      expect(server.count('listMine'), lists + 1);
    });

    test('several refused targets replace the identity once', () async {
      server
        ..failNext('copy', apiError('UNAUTHORIZED', status: 401))
        ..failNext('copy', apiError('UNAUTHORIZED', status: 401));

      final results = await controller.copyTracks(from, const [_a], [pl1, pl2]);

      expect(
        [
          for (final (_, result) in results)
            (result as MutationFailed<int>).code,
        ],
        ['UNAUTHORIZED', 'UNAUTHORIZED'],
      );
      expect(opened.api.createMemberCalls, 1);
    });

    test('ticks the targets saved to, only for songs already read', () async {
      await controller.containing(_a);
      expect(ticked(), {'from'});
      server.failNext(
        'copy',
        apiError('NOT_FOUND', message: '歌单不存在', status: 404),
      );

      await controller.copyTracks(from, const [_a, b], [pl1, pl2]);

      expect(ticked(), {'from', 'pl-2'});
      expect(list.read().memberships.containsKey(trackKey(b)), isFalse);
    });

    test('leaves the tick of a playlist still syncing as the user '
        'left it', () async {
      server.contents['pl-2'] = [song('a')];
      await controller.containing(_a);
      final remove = server.hold('remove');
      final sync = controller.setMembership(pl2, _a, included: false);
      await pumpEventQueue();

      await controller.copyTracks(from, const [_a], [pl2]);
      expect(ticked(), {'from'});

      remove.complete();
      await sync;
      expect(writes(), ['remove pl-2 $_key']);
    });
  });

  group('a new owner', () {
    test('does not get a read answered after signing out', () async {
      server.contents['pl-1'] = [song('a')];
      final stale = server.hold('containing');
      final reading = controller.containing(_a);
      await pumpEventQueue();

      await signOut();
      await pumpEventQueue();
      stale.complete();

      expect(await reading, isNull);
      expect(list.read().guest, isTrue);
      expect(list.read().memberships, isEmpty);
    });

    test('does not get a read answered after signing in again', () async {
      server.contents['pl-1'] = [song('a')];
      final stale = server.hold('containing');
      final reading = controller.containing(_a);
      await pumpEventQueue();

      await signOut();
      await signIn();
      await pumpEventQueue();
      server.contents['pl-1'] = [];
      stale.complete();

      expect(await reading, isNull);
      expect(list.read().playlists, isNotNull);
      expect(ticked(), isNull, reason: 'not read in this session yet');
    });

    test('does not get a read answered after a server switch', () async {
      server.contents['pl-1'] = [song('a')];
      final stale = server.hold('containing');
      final reading = controller.containing(_a);
      await pumpEventQueue();

      switchServer();
      await pumpEventQueue();
      stale.complete();

      expect(await reading, isNull);
      expect([for (final p in list.read().playlists!) p.id], ['elsewhere']);
      expect(list.read().memberships, isEmpty);
    });

    test('does not get a read answered as the server switches, before the '
        'list starts over', () async {
      server.contents['pl-1'] = [song('a')];
      final stale = server.hold('containing');
      final reading = controller.containing(_a);
      await pumpEventQueue();

      switchServer();
      stale.complete();

      expect(await reading, isNull);
      expect(list.read().memberships, isEmpty);
    });

    test('a failed read from before a switch is not told as the new '
        'owner\'s', () async {
      final stale = server.hold('containing');
      server.failNext('containing', networkError);
      final reading = controller.containing(_a);
      await pumpEventQueue();

      switchServer();
      await pumpEventQueue();
      stale.complete();

      expect(await reading, isNull);
    });

    test('is not rolled back into, nor read for, by a sync answered after a '
        'server switch', () async {
      server.contents['pl-1'] = [song('a')];
      await controller.containing(_a);
      final remove = server.hold('remove');
      final sync = controller.setMembership(pl1, _a, included: false);
      await pumpEventQueue();

      switchServer();
      await pumpEventQueue();
      remove.complete();
      final result = await sync;
      await pumpEventQueue();

      expect(
        result,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          doneOnOldServerText,
        ),
      );
      expect(list.read().memberships, isEmpty);
      expect(other.count('containing'), 0);
      expect(other.count('listMine'), 1);
      expect(writes(other), isEmpty);
    });

    test('is not rolled back into by a sync that fails after signing in '
        'again', () async {
      server.contents['pl-1'] = [song('a')];
      await controller.containing(_a);
      final remove = server.hold('remove');
      server.failNext('remove', apiError('NOT_FOUND', status: 404));
      final sync = controller.setMembership(pl1, _a, included: false);
      await pumpEventQueue();

      await signOut();
      await signIn();
      await pumpEventQueue();
      final reads = server.count('containing');
      remove.complete();
      expect(await sync, isA<MutationFailed<void>>());
      await pumpEventQueue();

      expect(ticked(), isNull);
      expect(server.count('containing'), reads);
    });

    test('can tick the same playlist while a sync from before signing in '
        'again is still waiting', () async {
      final stale = server.hold('add');
      final syncing = controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();

      await signOut();
      await signIn();
      await pumpEventQueue();
      final result = await controller.setMembership(pl1, _a, included: true);

      expect(result, isA<MutationSucceeded<void>>());
      expect(writes(), ['add pl-1 $_key', 'add pl-1 $_key']);
      stale.complete();
      await syncing;
    });

    test('reads the server state of a playlist a sync from before signing '
        'in again is still waiting on', () async {
      server.contents['pl-1'] = [song('a')];
      await controller.containing(_a);
      final stale = server.hold('remove');
      final syncing = controller.setMembership(pl1, _a, included: false);
      await pumpEventQueue();

      await signOut();
      await signIn();
      await pumpEventQueue();

      expect(await controller.containing(_a), isNull);
      expect(ticked(), {'pl-1'});
      stale.complete();
      await syncing;
    });

    test('keeps a sheet opened after a sync from before is voided', () async {
      final add = server.hold('add');
      final sync = controller.setMembership(pl1, _a, included: true);
      await pumpEventQueue();
      list.close();
      await signOut();
      await opened.container.pump();
      await pumpEventQueue();
      final reopened = opened.container.listen(
        myPlaylistsControllerProvider,
        (_, _) {},
      );
      await pumpEventQueue();

      add.complete();
      await sync;
      await opened.container.pump();
      await pumpEventQueue();

      expect(opened.container.exists(myPlaylistsControllerProvider), isTrue);
      expect(reopened.read().guest, isTrue);
    });

    test('is not read for by a multi-song save answered after a server '
        'switch', () async {
      server.contents['pl-2'] = [song('a')];
      final copy = server.hold('copy');
      final saving = controller.copyTracks(pl2, const [_a], [pl1]);
      await pumpEventQueue();

      switchServer();
      await pumpEventQueue();
      copy.complete();
      final results = await saving;
      await pumpEventQueue();

      expect(
        results.single.$2,
        isA<MutationNotSent<int>>().having(
          (r) => r.message,
          'message',
          doneOnOldServerText,
        ),
      );
      expect(server.contents['pl-1'], hasLength(1));
      expect(other.count('listMine'), 1);
    });
  });
}
