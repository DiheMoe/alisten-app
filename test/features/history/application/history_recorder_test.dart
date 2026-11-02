import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:alisten/features/history/application/history_recorder.dart';
import 'package:alisten/features/history/data/local_history_store.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/application/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';
import '../../settings/settings_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRoomTransportFactory factory;
  late ProviderContainer container;
  var seq = 1;

  Future<void> start({
    List<RoomListing>? rooms,
    Map<String, String> tickets = const {'room-id': 'ticket'},
    bool recorderFirst = true,
    ServerProfile? server,
  }) async {
    factory = FakeRoomTransportFactory();
    seq = 1;
    final api = FakeAlistenApi()
      ..rooms = rooms ?? [roomListing(id: 'room-id', slug: 'listen')];
    final credentials = FakeCredentialStore()..tickets.addAll(tickets);
    container = ProviderContainer(
      overrides: [
        await preferencesOverride(),
        alistenApiProvider.overrideWithValue(api),
        credentialStoreProvider.overrideWithValue(credentials),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(),
        buildEnvironmentProvider.overrideWithValue(testEnvironment),
        serverStoreProvider.overrideWithValue(
          FakeServerStore(profiles: [?server], currentId: server?.id),
        ),
        playHistoryStoreProvider.overrideWith(
          (ref) => LocalHistoryStore(
            ref.watch(sharedPreferencesProvider),
            legacyServerOrigin: testEnvironment.defaultOrigin,
          ),
        ),
        ...settingsOverrides(),
        historyNowProvider.overrideWithValue(() => 2000000),
      ],
    );
    addTearDown(container.dispose);
    // 应用根部也这样保持记录器存活；这些测试都不读取播放历史页的 provider。
    if (recorderFirst) container.listen(historyRecorderProvider, (_, _) {});
    await container.read(roomControllerProvider.notifier).openRoom('listen');
  }

  void hello(NowPlaying? nowPlaying, {String roomId = 'room-id'}) {
    seq = 1;
    final snapshot = testRoomSnapshot().copyWith(
      term: 1,
      seq: 1,
      room: RoomInfo(
        id: roomId,
        name: '房间',
        description: '描述',
        kind: RoomKind.ephemeral,
      ),
      nowPlaying: nowPlaying,
    );
    factory.last.emitHello(snapshot);
  }

  void play(NowPlaying? nowPlaying) {
    factory.last.emit(
      RoomEventReceived(
        PlaybackUpdatedEvent(term: 1, seq: ++seq, nowPlaying: nowPlaying),
      ),
    );
  }

  List<String> recorded() {
    return container
        .read(playHistoryStoreProvider)
        .loadPlays()
        .map((record) => record.track.id)
        .toList();
  }

  test(
    'songs are recorded although the history page was never opened',
    () async {
      await start();
      hello(song('a'));
      await pumpEventQueue();
      play(song('b'));
      await pumpEventQueue();
      play(song('c'));
      await pumpEventQueue();

      expect(recorded(), ['c', 'b', 'a']);
    },
  );

  test(
    'a song already playing when the recorder starts is recorded once',
    () async {
      await start(recorderFirst: false);
      hello(song('a'));
      await pumpEventQueue();
      expect(recorded(), isEmpty);

      container.listen(historyRecorderProvider, (_, _) {});
      await pumpEventQueue();
      expect(recorded(), ['a']);

      hello(song('a'));
      await pumpEventQueue();
      expect(recorded(), ['a']);
    },
  );

  test(
    'a playback is recorded once, and each room keeps its own record',
    () async {
      await start(
        rooms: [
          roomListing(id: 'room-id', slug: 'listen'),
          roomListing(id: 'room-two', slug: 'two'),
        ],
        tickets: {'room-id': 'ticket-one', 'room-two': 'ticket-two'},
      );
      final room = container.read(roomControllerProvider.notifier);
      hello(song('a'));
      hello(song('a'));
      await pumpEventQueue();
      expect(recorded(), ['a']);

      await room.openRoom('two');
      hello(song('a'), roomId: 'room-two');
      await pumpEventQueue();

      final records = container.read(playHistoryStoreProvider).loadPlays();
      expect(records.map((record) => record.roomId).toSet(), {
        'room-id',
        'room-two',
      });
      expect(records.first.playedAtMs, 2000000);
    },
  );

  test('a song is recorded with the name its room had then', () async {
    await start();
    hello(song('a'));
    await pumpEventQueue();

    final record = container.read(playHistoryStoreProvider).loadPlays().single;
    expect(record.roomId, 'room-id');
    expect(record.roomName, '房间');
    expect(record.serverOrigin, 'https://livehouse.dihe.moe');
  });

  test('a song is recorded with the server that is current', () async {
    await start(server: serverB);
    hello(song('a'));
    await pumpEventQueue();

    final record = container.read(playHistoryStoreProvider).loadPlays().single;
    expect(record.serverOrigin, 'https://example.com:8443');
  });

  test('a song that started while recording was off is not recorded '
      'when it is turned on again', () async {
    await start();
    final settings = container.read(settingsControllerProvider.notifier);
    hello(song('a'));
    await pumpEventQueue();

    await settings.setRecordHistory(false);
    play(song('b'));
    await pumpEventQueue();
    await settings.setRecordHistory(true);
    // 重连后收到的仍是正在播放的那首歌。
    hello(song('b'));
    await pumpEventQueue();
    expect(recorded(), ['a']);

    play(song('c'));
    await pumpEventQueue();
    expect(recorded(), ['c', 'a']);
  });
}

NowPlaying song(String id) {
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
