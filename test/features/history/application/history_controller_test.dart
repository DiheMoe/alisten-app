import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';
import '../history_test_doubles.dart';

const _now = 1782864000000;

const _refused = ApiException(code: 'INTERNAL', message: '服务器出错了', status: 500);

const _lost = ApiException(
  code: LocalErrorCodes.network,
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeAlistenApi apiB;
  late FakeCredentialStores stores;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory rooms;
  late FakeHistoryExporter exporter;
  late ProviderContainer container;
  late HistoryController history;
  var seq = 1;

  HistoryState state() => container.read(historyControllerProvider);
  List<String>? titles() =>
      state().listens?.map((listen) => listen.meta.title).toList();

  setUp(() async {
    api = FakeAlistenApi()
      ..rooms = [roomListing(id: 'room-id', slug: 'listen')];
    apiB = FakeAlistenApi();
    stores = FakeCredentialStores();
    credentials = stores(testEnvironment.defaultServerId)
      ..memberToken = 'guest-token'
      ..tickets['room-id'] = 'ticket';
    rooms = FakeRoomTransportFactory();
    exporter = FakeHistoryExporter();
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: stores,
      api: api,
      apis: {serverB.id: apiB},
      rooms: rooms,
      extra: [
        historyExporterProvider.overrideWithValue(exporter),
        historyNowProvider.overrideWithValue(() => _now),
      ],
    );
    history = container.read(historyControllerProvider.notifier);
    seq = 1;
  });

  // 和打开的页面一样监听控制器：没有监听者时，它听的 provider 不会主动刷新，
  // 服务器变化要等下一次读取才送达。
  Future<void Function()> openWith(List<Listen> listens) async {
    api.listens = listens;
    final page = container.listen(historyControllerProvider, (_, _) {});
    final close = history.open();
    await pumpEventQueue();
    return () {
      close();
      page.close();
    };
  }

  Future<void> enterRoom() async {
    await container.read(roomControllerProvider.notifier).openRoom('listen');
    rooms.last.emitHello(
      testRoomSnapshot().copyWith(term: 1, seq: 1, nowPlaying: _song('a')),
    );
    seq = 1;
    await pumpEventQueue();
  }

  void play(NowPlaying? nowPlaying) {
    rooms.last.emit(
      RoomEventReceived(
        PlaybackUpdatedEvent(term: 1, seq: ++seq, nowPlaying: nowPlaying),
      ),
    );
  }

  Future<void> signIn() => container
      .read(identityControllerProvider.notifier)
      .adoptSession(
        (server) => server.login(username: 'mao', password: 'password1'),
      );

  group('reading', () {
    test('each opening reads once, and a second opening shows the last list '
        'while it reads again', () async {
      final first = await openWith([heard('a')]);
      first();
      expect(titles(), ['a']);
      expect(api.listMyListensCalls, 1);

      final read = Completer<List<Listen>>();
      api.listMyListensResults.add(read);
      final second = history.open();
      await pumpEventQueue();
      expect(titles(), ['a']);
      expect(api.listMyListensCalls, 2);

      read.complete([heard('b'), heard('a')]);
      await pumpEventQueue();
      expect(titles(), ['b', 'a']);
      second();
    });

    test('without a member token the list is empty, and nothing is sent or '
        'created', () async {
      credentials.memberToken = null;

      final close = history.open();
      await pumpEventQueue();

      expect(state().listens, isEmpty);
      expect(api.listMyListensCalls, 0);
      expect(api.createMemberCalls, 0);
      close();
    });

    test('credentials that cannot be read say so', () async {
      credentials.readMemberTokenError = Exception('locked');

      final close = history.open();
      await pumpEventQueue();

      expect(state().listens, isNull);
      expect(state().error, '身份凭据暂时无法读取，请稍后重试。');
      expect(api.listMyListensCalls, 0);
      close();
    });

    test('a failed first read keeps its reason, and trying again clears it '
        'and reads', () async {
      api.listMyListensError = _lost;
      final close = history.open();
      await pumpEventQueue();
      expect(state().listens, isNull);
      expect(state().error, '网络请求失败，请检查网络后重试。');

      api
        ..listMyListensError = null
        ..listens = [heard('a')];
      final retry = history.load();
      expect(state().error, isNull);
      await retry;

      expect(titles(), ['a']);
      close();
    });

    test('a failed later read keeps the list it has', () async {
      final close = await openWith([heard('a')]);

      api.listMyListensError = _refused;
      await history.load();

      expect(titles(), ['a']);
      expect(state().error, '服务器出错了');
      close();
    });

    test('of two reads answered out of order, the earlier one is '
        'dropped', () async {
      final first = Completer<List<Listen>>();
      final second = Completer<List<Listen>>();
      api.listMyListensResults.addAll([first, second]);
      final close = history.open();
      await pumpEventQueue();
      unawaited(history.load());
      await pumpEventQueue();

      second.complete([heard('new')]);
      await pumpEventQueue();
      first.complete([heard('old')]);
      await pumpEventQueue();

      expect(titles(), ['new']);
      close();
    });
  });

  group('the song playing in the room', () {
    test('a new song is read while the page is open', () async {
      await enterRoom();
      final close = await openWith([heard('a')]);
      final reads = api.listMyListensCalls;

      play(_song('b'));
      await pumpEventQueue();

      expect(api.listMyListensCalls, reads + 1);
      close();
    });

    test('no song, the same song again, or a closed page read '
        'nothing', () async {
      await enterRoom();
      final close = await openWith([heard('a')]);
      final reads = api.listMyListensCalls;

      rooms.last.emitHello(
        testRoomSnapshot().copyWith(term: 1, seq: 1, nowPlaying: _song('a')),
      );
      seq = 1;
      await pumpEventQueue();
      play(null);
      await pumpEventQueue();
      expect(api.listMyListensCalls, reads);

      close();
      play(_song('c'));
      await pumpEventQueue();
      expect(api.listMyListensCalls, reads);
    });

    test('a read scheduled for a new song does nothing once the controller '
        'is gone', () async {
      await enterRoom();
      await openWith([heard('a')]);
      final reads = api.listMyListensCalls;

      play(_song('b'));
      // 停在新歌送达的那一刻：读取已经排进微任务，还没有开始。
      for (
        var hops = 0;
        container.read(roomControllerProvider).snapshot?.nowPlaying?.entry.id !=
            'entry-b';
        hops++
      ) {
        expect(hops, lessThan(50));
        await Future<void>.value();
      }
      container.dispose();
      await pumpEventQueue();

      expect(api.listMyListensCalls, reads);
    });
  });

  group('deleting', () {
    test('a delete the server took takes the song off the list', () async {
      final close = await openWith([heard('a'), heard('b')]);

      final result = await history.remove(heard('a', at: 99));

      expect(result, isA<MutationSucceeded<void>>());
      expect(titles(), ['b']);
      expect(api.removedListens.map(trackKey), ['netease:a']);
      close();
    });

    test('a read in flight during a delete is dropped and read '
        'again', () async {
      final close = await openWith([heard('a'), heard('b')]);
      final stale = Completer<List<Listen>>();
      api.listMyListensResults.add(stale);
      unawaited(history.load());
      await pumpEventQueue();

      expect(await history.remove(heard('a')), isA<MutationSucceeded<void>>());
      await pumpEventQueue();
      stale.complete([heard('a'), heard('b')]);
      await pumpEventQueue();

      expect(titles(), ['b']);
      expect(api.listenRequests, ['list', 'list', 'remove', 'list']);
      close();
    });

    test('a delete the server refuses leaves the list and gives its '
        'reason', () async {
      final close = await openWith([heard('a'), heard('b')]);
      api.removeMyListenError = _refused;

      final result = await history.remove(heard('a'));

      expect(
        result,
        isA<MutationFailed<void>>().having(
          (failed) => failed.message,
          'message',
          '服务器出错了',
        ),
      );
      expect(titles(), ['a', 'b']);
      close();
    });

    test('a delete with an unknown result reads the list again and is not '
        'sent twice', () async {
      final close = await openWith([heard('a'), heard('b')]);
      api.removeMyListenError = _lost;
      final reads = api.listMyListensCalls;

      final result = await history.remove(heard('a'));
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<void>>());
      expect(api.listMyListensCalls, reads + 1);
      expect(api.removedListens, hasLength(1));
      close();
    });

    test('a rate limited delete says when to try again', () async {
      final close = await openWith([heard('a')]);
      api.removeMyListenError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: Duration(seconds: 30),
      );

      final result = await history.remove(heard('a'));

      expect((result as MutationFailed<void>).message, '请求太频繁，请 30 秒后再试');
      close();
    });

    test('a delete without a member token is not sent', () async {
      final close = await openWith([heard('a')]);
      api.removeMyListenError = const ApiException(
        code: LocalErrorCodes.noToken,
        message: '缺少身份凭据，请重新进入后再试。',
        status: null,
      );

      final result = await history.remove(heard('a'));

      expect((result as MutationNotSent<void>).message, '缺少身份凭据，请重新进入后再试。');
      expect(titles(), ['a']);
      close();
    });

    test('a delete with an unknown result reads nothing while the page is '
        'closed', () async {
      final close = await openWith([heard('a')]);
      close();
      api.removeMyListenError = _lost;
      final reads = api.listMyListensCalls;

      expect(await history.remove(heard('a')), isA<MutationUnknown<void>>());
      await pumpEventQueue();

      expect(api.listMyListensCalls, reads);
      expect(titles(), ['a']);
    });

    test('two deletes in flight both take their songs off the list', () async {
      final close = await openWith([heard('a'), heard('b'), heard('c')]);
      final gate = api.removeMyListenGate = Completer<void>();
      final first = history.remove(heard('a'));
      final second = history.remove(heard('b'));
      await pumpEventQueue();
      expect(api.removedListens.map(trackKey), ['netease:a', 'netease:b']);

      gate.complete();

      expect(await first, isA<MutationSucceeded<void>>());
      expect(await second, isA<MutationSucceeded<void>>());
      expect(titles(), ['c']);
      close();
    });

    test('of two deletes in flight, one refused keeps its song and the other '
        'still takes its own off', () async {
      final close = await openWith([heard('a'), heard('b'), heard('c')]);
      final refusing = api.removeMyListenGate = Completer<void>();
      final refused = history.remove(heard('a'));
      await pumpEventQueue();
      final taking = api.removeMyListenGate = Completer<void>();
      final took = history.remove(heard('b'));
      await pumpEventQueue();

      taking.complete();
      expect(await took, isA<MutationSucceeded<void>>());
      api.removeMyListenError = _refused;
      refusing.complete();

      expect(await refused, isA<MutationFailed<void>>());
      expect(titles(), ['a', 'c']);
      close();
    });
  });

  group('clearing', () {
    test('a clear the server took empties the list', () async {
      final close = await openWith([heard('a'), heard('b')]);

      expect(await history.clear(), isA<MutationSucceeded<void>>());

      expect(state().listens, isEmpty);
      expect(api.clearMyListensCalls, 1);
      close();
    });

    test('a clear the server refuses leaves the list', () async {
      final close = await openWith([heard('a')]);
      api.clearMyListensError = _refused;

      final result = await history.clear();

      expect((result as MutationFailed<void>).message, '服务器出错了');
      expect(titles(), ['a']);
      close();
    });

    test('a read in flight during a clear is dropped and read again', () async {
      final close = await openWith([heard('a'), heard('b')]);
      final stale = Completer<List<Listen>>();
      api.listMyListensResults.add(stale);
      unawaited(history.load());
      await pumpEventQueue();

      expect(await history.clear(), isA<MutationSucceeded<void>>());
      await pumpEventQueue();
      stale.complete([heard('a'), heard('b')]);
      await pumpEventQueue();

      expect(state().listens, isEmpty);
      expect(api.listenRequests, ['list', 'list', 'clear', 'list']);
      close();
    });
  });

  group('a new session', () {
    test('empties the list, keeps the filter and reads again for the new '
        'identity', () async {
      final close = await openWith([heard('guest')]);
      history.filter('gu');
      final read = Completer<List<Listen>>();
      api.listMyListensResults.add(read);

      await signIn();
      await pumpEventQueue();

      expect(state().listens, isNull);
      expect(state().query, 'gu');
      read.complete([heard('account'), heard('guest')]);
      await pumpEventQueue();
      expect(titles(), ['account', 'guest']);
      close();
    });

    test('drops a read sent before it', () async {
      final close = await openWith([heard('guest')]);
      final stale = Completer<List<Listen>>();
      api.listMyListensResults.add(stale);
      unawaited(history.load());
      await pumpEventQueue();
      api.listens = [heard('account')];

      await signIn();
      await pumpEventQueue();
      stale.complete([heard('guest')]);
      await pumpEventQueue();

      expect(titles(), ['account']);
      close();
    });

    test('a delete sent before it does not change the list of the new '
        'identity', () async {
      final close = await openWith([heard('a'), heard('b')]);
      final gate = api.removeMyListenGate = Completer<void>();
      final removing = history.remove(heard('a'));
      await pumpEventQueue();

      await signIn();
      await pumpEventQueue();
      expect(titles(), ['a', 'b']);
      gate.complete();

      expect(await removing, isA<MutationSucceeded<void>>());
      expect(titles(), ['a', 'b']);
      close();
    });

    test('while the page is closed only empties the list', () async {
      final close = await openWith([heard('guest')]);
      close();
      final reads = api.listMyListensCalls;

      await signIn();
      await pumpEventQueue();

      expect(state().listens, isNull);
      expect(api.listMyListensCalls, reads);
    });
  });

  test('a server change empties the list and drops a read from the old '
      'server, whose refusal replaces nobody on the new one', () async {
    final close = await openWith([heard('a')]);
    final stale = Completer<List<Listen>>();
    api.listMyListensResults.add(stale);
    unawaited(history.load());
    await pumpEventQueue();
    stores(serverB.id).memberToken = 'token-b';
    final reading = Completer<List<Listen>>();
    apiB.listMyListensResults.add(reading);

    await container
        .read(serverDirectoryProvider.notifier)
        .setCurrent(serverB.id);
    await pumpEventQueue();
    expect(state().listens, isNull);

    reading.complete([heard('b')]);
    await pumpEventQueue();
    expect(titles(), ['b']);

    stale.completeError(unauthorized);
    await pumpEventQueue();
    expect(titles(), ['b']);
    expect(stores(serverB.id).memberToken, 'token-b');
    expect(api.createMemberCalls + apiB.createMemberCalls, 0);
    close();
  });

  group('a delete and a server change', () {
    setUp(() {
      stores(serverB.id).memberToken = 'token-b';
    });

    Future<void> switchToB() async {
      await container
          .read(serverDirectoryProvider.notifier)
          .setCurrent(serverB.id);
      await pumpEventQueue();
    }

    test('a delete sent before the change does not change the list on the '
        'new server', () async {
      final close = await openWith([heard('a'), heard('b')]);
      final gate = api.removeMyListenGate = Completer<void>();
      final removing = history.remove(heard('a'));
      await pumpEventQueue();
      apiB.listens = [heard('a'), heard('c')];

      await switchToB();
      expect(titles(), ['a', 'c']);
      gate.complete();

      expect(await removing, isA<MutationSucceeded<void>>());
      await pumpEventQueue();
      expect(titles(), ['a', 'c']);
      expect(api.removedListens.map(trackKey), ['netease:a']);
      expect(apiB.removedListens, isEmpty);
      close();
    });

    test('a delete sent before the change with an unknown result reads '
        'nothing more', () async {
      final close = await openWith([heard('a')]);
      final gate = api.removeMyListenGate = Completer<void>();
      api.removeMyListenError = _lost;
      final removing = history.remove(heard('a'));
      await pumpEventQueue();
      apiB.listens = [heard('b')];

      await switchToB();
      expect(apiB.listMyListensCalls, 1);
      final readsOnA = api.listMyListensCalls;
      gate.complete();

      expect(await removing, isA<MutationUnknown<void>>());
      await pumpEventQueue();
      expect(apiB.listMyListensCalls, 1);
      expect(api.listMyListensCalls, readsOnA);
      expect(titles(), ['b']);
      close();
    });

    test('a delete sent while the change is still being applied belongs to '
        'the new server', () async {
      final close = await openWith([heard('a')]);
      apiB.listens = [heard('a'), heard('c')];
      final reading = Completer<List<Listen>>();
      apiB.listMyListensResults.add(reading);
      Future<MutationResult<void>>? removing;
      // 目录已经换了服务器，依赖它的 provider 还没有刷新。
      final directory = container.listen(serverDirectoryProvider, (_, _) {
        removing ??= history.remove(heard('a'));
      });
      addTearDown(directory.close);

      await switchToB();
      expect(await removing!, isA<MutationSucceeded<void>>());
      await pumpEventQueue();
      reading.complete([heard('a'), heard('c')]);
      await pumpEventQueue();

      expect(api.removedListens, isEmpty);
      expect(apiB.removedListens.map(trackKey), ['netease:a']);
      expect(titles(), ['c']);
      close();
    });
  });

  group('a refused member token', () {
    test('on a read, the guest is replaced and the list is that of the new '
        'guest', () async {
      final read = Completer<List<Listen>>();
      api.listMyListensResults.add(read);
      final close = history.open();
      await pumpEventQueue();

      read.completeError(unauthorized);
      await pumpEventQueue();

      expect(credentials.memberToken, 'new-member-token');
      expect(api.createMemberCalls, 1);
      expect(state().listens, isEmpty);
      expect(state().error, isNull);
      expect(
        container.read(identityControllerProvider).notice,
        identityRenewedNotice,
      );
      close();
    });

    for (final (account, notice) in [
      (null, identityRenewedNotice),
      (const Account(username: 'mao', github: false), signedOutNotice),
    ]) {
      test('on a delete by ${account == null ? 'a guest' : 'an account'}, '
          'says "$notice"', () async {
        api.account = account;
        await container.read(identityControllerProvider.notifier).restore();
        final close = await openWith([heard('a')]);
        api.removeMyListenError = unauthorized;

        final result = await history.remove(heard('a'));

        expect(
          result,
          isA<MutationFailed<void>>().having(
            (failed) => failed.message,
            'message',
            notice,
          ),
        );
        expect(credentials.memberToken, 'new-member-token');
        close();
      });
    }
  });

  test('the filter matches title, artist and album, ignoring case', () async {
    final close = await openWith([
      heard('Target Song', artist: 'someone', album: 'somewhere'),
      heard('other', artist: 'ARTIST', album: 'x'),
      heard('third', artist: 'y', album: 'The Album'),
    ]);
    List<String> filtered() =>
        state().filteredListens.map((listen) => listen.meta.title).toList();

    history.filter('TARGET SONG');
    expect(state().query, 'TARGET SONG');
    expect(filtered(), ['Target Song']);
    history.filter('artist');
    expect(filtered(), ['other']);
    history.filter('album');
    expect(filtered(), ['third']);
    history.filter('');
    expect(filtered(), hasLength(3));
    close();
  });

  test('the export holds the whole history, whatever the filter, at the '
      'current time in UTC', () async {
    final close = await openWith([heard('a'), heard('b')]);
    history.filter('a');

    await history.exportHistory();

    expect(exporter.listens.map((listen) => listen.meta.title), ['a', 'b']);
    expect(exporter.exportedAt!.isUtc, isTrue);
    expect(exporter.exportedAt!.millisecondsSinceEpoch, _now);
    close();
  });
}

NowPlaying _song(String id) {
  return NowPlaying(
    entry: QueueEntry(
      id: 'entry-$id',
      track: Track(source: TrackSource.netease, id: id),
      meta: testTrackMeta,
      requestedBy: testMember,
      auto: false,
      likes: 0,
      status: QueueEntryStatus.ready,
    ),
    mediaUrl: '/media/netease/$id',
    startedAtMs: 1000000,
    durationMs: 180000,
    gain: 1,
    lyric: '',
  );
}
