import 'dart:async';
import 'dart:io';

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/lobby/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/cache/cover_cache_test_doubles.dart' show FakeCoverCache;
import '../../lobby/lobby_test_doubles.dart';
import '../../playback/playback_test_doubles.dart'
    show FakeAudioEngine, FakeTrackStartReminder;
import '../../room/room_test_doubles.dart';
import '../../settings/settings_test_doubles.dart' show settingsOverrides;
import '../server_test_doubles.dart';

const _defaultId = 'fcd7a878032db68b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServerStore store;
  late FakeCredentialStores credentials;
  late FakeAlistenApi apiA;
  late FakeAlistenApi apiB;
  late FakeAlistenApi apiC;
  late FakeRoomTransportFactory rooms;
  late FakeAudioEngine engine;
  late List<String> steps;
  late ProviderContainer container;

  ServerSwitcher switcher() => container.read(serverSwitcherProvider);
  RoomController room() => container.read(roomControllerProvider.notifier);
  IdentityController identity() =>
      container.read(identityControllerProvider.notifier);
  LobbyController lobby() => container.read(lobbyControllerProvider.notifier);

  setUp(() async {
    store = FakeServerStore(profiles: [serverB]);
    credentials = FakeCredentialStores();
    apiA = FakeAlistenApi()..rooms = [roomListing(id: 'room-a', slug: null)];
    apiB = FakeAlistenApi()..rooms = [roomListing(id: 'room-b', slug: null)];
    apiC = FakeAlistenApi();
    rooms = FakeRoomTransportFactory();
    engine = FakeAudioEngine();
    steps = [];
    container = await switchingContainer(
      store: store,
      credentials: credentials,
      apis: {_defaultId: apiA, serverB.id: apiB, serverC.id: apiC},
      rooms: rooms,
      preferences: {'alisten.last-room@f475765b53c3272e': 'room-b'},
      onEndAdminSession: () => steps.add('admin-ended'),
      extra: [
        audioEngineProvider.overrideWithValue(engine),
        trackStartReminderProvider.overrideWithValue(FakeTrackStartReminder()),
        coverCacheProvider.overrideWithValue(FakeCoverCache()),
        ...settingsOverrides(),
      ],
    );
    container.listen(playbackControllerProvider, (_, _) {});
  });

  test('the room is left and playback stopped before the new server is '
      'written, and everything then follows the new server', () async {
    expect(await room().openRoom('room-a'), isA<RoomJoined>());
    rooms.last.emitHello();
    await pumpEventQueue();
    expect(container.read(nowPlayingProvider), isNotNull);
    expect(engine.requests, isNotEmpty);
    final atWrite = <(String?, bool, int, int, LocalPlaybackStatus)>[];
    store.onSaveCurrent = (_) {
      atWrite.add((
        container.read(roomControllerProvider).activeRoomId,
        container.read(nowPlayingProvider) == null,
        rooms.transports.single.stopCalls,
        engine.releaseCalls,
        container.read(playbackControllerProvider).status,
      ));
    };

    final outcome = await switcher().switchTo(serverB);
    await pumpEventQueue();

    expect(atWrite, [(null, true, 1, 1, LocalPlaybackStatus.idle)]);
    expect(engine.requests.map((request) => request.uri.host).toSet(), {
      'livehouse.dihe.moe',
    });
    expect(rooms.transports.single.stopCalls, 1);
    expect(rooms.servers, [_defaultId]);
    final preferences = container.read(sharedPreferencesProvider);
    expect(preferences.containsKey('alisten.last-room@$_defaultId'), isFalse);
    expect(container.read(lastRoomStoreProvider).read(), 'room-b');
    expect(
      outcome,
      isA<SwitchSucceeded>().having((o) => o.server.id, 'id', serverB.id),
    );
    expect(
      container.read(appConfigProvider).baseUrl,
      'https://example.com:8443',
    );
    expect(
      container.read(credentialStoreProvider),
      same(credentials('f475765b53c3272e')),
    );
  });

  test('the site admin session ends after the room is left and before the '
      'new server is written', () async {
    expect(await room().openRoom('room-a'), isA<RoomJoined>());
    rooms.last.emitHello();
    await pumpEventQueue();
    container.listen(
      roomControllerProvider.select((state) => state.activeRoomId),
      (_, id) {
        if (id == null) steps.add('left');
      },
    );
    store.onSaveCurrent = (_) => steps.add('saved');

    expect(await switcher().switchTo(serverB), isA<SwitchSucceeded>());

    expect(steps, ['left', 'admin-ended', 'saved']);
  });

  test(
    'switching to the current server keeps the site admin session',
    () async {
      final outcome = await switcher().switchTo(
        container.read(currentServerProvider),
      );

      expect(outcome, isA<SwitchSucceeded>());
      expect(steps, isEmpty);
    },
  );

  test('a server that cannot be written as current is not switched to, and '
      'the failure is logged by its type alone', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    store.failCurrentWrites = true;

    final outcome = await switcher().switchTo(serverB);
    await pumpEventQueue();

    expect(
      outcome,
      isA<SwitchFailed>().having((o) => o.message, 'message', switchFailedText),
    );
    expect(container.read(currentServerProvider).id, _defaultId);
    expect(
      container.read(appConfigProvider).baseUrl,
      'https://livehouse.dihe.moe',
    );
    expect(apiB.listRoomsCalls + apiB.getMeCalls, 0);
    expect(records, contains(contains('switch not saved')));
    expect(records.where((record) => record.contains('example.com')), isEmpty);
  });

  test('a server not saved yet is saved and becomes current', () async {
    final outcome = await switcher().switchTo(serverC);

    expect(
      outcome,
      isA<SwitchSucceeded>().having((o) => o.server, 'server', serverC),
    );
    expect(store.profiles.map((profile) => profile.id), contains(serverC.id));
    expect(store.currentId, serverC.id);
    expect(container.read(currentServerProvider).id, serverC.id);
  });

  test('a saved server is switched to under the name it is saved with, not '
      'the one its caller held', () async {
    await container
        .read(serverDirectoryProvider.notifier)
        .updateBrandName(serverB.id, '新名字');

    final outcome = await switcher().switchTo(serverB);

    expect(
      outcome,
      isA<SwitchSucceeded>().having(
        (o) => o.server.brandName,
        'brandName',
        '新名字',
      ),
    );
    expect(
      store.profiles.singleWhere((p) => p.id == serverB.id).brandName,
      '新名字',
    );
    expect(container.read(currentServerProvider).brandName, '新名字');
  });

  test('a server not saved yet stays saved when it cannot become '
      'current', () async {
    store.failCurrentWrites = true;

    final outcome = await switcher().switchTo(serverC);

    expect(
      outcome,
      isA<SwitchFailed>().having((o) => o.message, 'message', switchFailedText),
    );
    expect(store.profiles.map((profile) => profile.id), contains(serverC.id));
    expect(container.read(currentServerProvider).id, _defaultId);
  });

  test('a server this build does not accept is not switched to', () async {
    final cleartext = ServerProfile(
      origin: 'http://10.0.2.2:9876',
      brandName: '本机',
      addedAtMs: 3,
    );

    final outcome = await switcher().switchTo(cleartext);

    expect(
      outcome,
      isA<SwitchFailed>().having((o) => o.message, 'message', switchFailedText),
    );
    expect(store.profiles.map((profile) => profile.id), [serverB.id]);
    expect(store.currentIdWrites, isEmpty);
    expect(container.read(currentServerProvider).id, _defaultId);
  });

  test('switching to the current server changes nothing', () async {
    await room().openRoom('room-a');

    final outcome = await switcher().switchTo(
      container.read(currentServerProvider),
    );

    expect(
      outcome,
      isA<SwitchSucceeded>().having((o) => o.server.id, 'id', _defaultId),
    );
    expect(container.read(roomControllerProvider).activeRoomId, 'room-a');
    expect(rooms.transports.single.stopCalls, 0);
    expect(store.currentIdWrites, isEmpty);
  });

  test('switching to one server twice at once switches once', () async {
    final first = switcher().switchTo(serverB);
    final second = switcher().switchTo(serverB);

    expect(await first, isA<SwitchSucceeded>());
    expect(await second, isA<SwitchSucceeded>());
    expect(store.currentIdWrites, [serverB.id]);
  });

  test('switching to another server while a switch runs is refused, and '
      'allowed again once it ends', () async {
    final writing = Completer<void>();
    store.onSaveCurrent = (_) => writing.future;
    final toB = switcher().switchTo(serverB);
    await pumpEventQueue();

    expect(
      await switcher().switchTo(serverC),
      isA<SwitchFailed>().having((o) => o.message, 'message', switchBusyText),
    );
    writing.complete();
    expect(await toB, isA<SwitchSucceeded>());
    expect(store.currentIdWrites, [serverB.id]);
    expect(store.profiles.map((profile) => profile.id), [serverB.id]);

    store.onSaveCurrent = null;
    expect(await switcher().switchTo(serverC), isA<SwitchSucceeded>());
    expect(store.currentIdWrites, [serverB.id, serverC.id]);
  });

  test('no room is entered while the server is being switched, and rooms '
      'are entered on the new server once it is', () async {
    final writing = Completer<void>();
    late Future<RoomJoin> opening;
    late Future<void> joining;
    store.onSaveCurrent = (_) {
      opening = room().openRoom('room-a');
      joining = expectLater(
        lobby().join('room-a'),
        throwsA(isA<LobbyActionException>()),
      );
      return writing.future;
    };

    final switching = switcher().switchTo(serverB);
    await pumpEventQueue();

    expect(await opening, isA<RoomJoinFailed>());
    await joining;
    expect(
      apiA.getRoomCalls + apiA.createTicketCalls + apiA.createMemberCalls,
      0,
    );
    expect(rooms.transports, isEmpty);

    writing.complete();
    expect(await switching, isA<SwitchSucceeded>());
    expect(container.read(roomControllerProvider).activeRoomId, isNull);
    expect(await room().openRoom('room-b'), isA<RoomJoined>());
    expect(rooms.servers, [serverB.id]);
  });

  test('rooms are entered again after a switch that failed', () async {
    store.failCurrentWrites = true;
    expect(await switcher().switchTo(serverB), isA<SwitchFailed>());

    expect(await room().openRoom('room-a'), isA<RoomJoined>());
    expect(rooms.servers, [_defaultId]);
  });

  // 房间、播放和身份都假定当前服务器就是房间所在的服务器，只有先离开房间的
  // 切换才能改写它。
  test('only the switcher writes the current server', () {
    final writers = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            entity.readAsStringSync().contains('.setCurrent('))
          entity.path.replaceAll(r'\', '/'),
    ];

    expect(writers, ['lib/features/server/application/server_switcher.dart']);
  });

  test('joining has to be confirmed where this device has no member '
      'token', () async {
    credentials(serverB.id).memberToken = 'b';

    expect(await switcher().needsJoinConfirmation(serverB), isFalse);
    expect(await switcher().needsJoinConfirmation(serverC), isTrue);
    await container.read(serverDirectoryProvider.notifier).add(serverC);
    expect(await switcher().needsJoinConfirmation(serverC), isTrue);
    credentials(serverB.id).readMemberTokenError = Exception('locked');
    expect(await switcher().needsJoinConfirmation(serverB), isTrue);
  });

  test('the lobby and the identity are reloaded from the new server, and '
      'the filter is kept', () async {
    credentials(serverB.id).memberToken = 'b';
    await lobby().load();
    lobby().filter('一起');
    expect(apiA.listRoomsCalls, 1);

    await switcher().switchTo(serverB);
    await pumpEventQueue();

    expect(apiA.listRoomsCalls, 1);
    expect(apiB.listRoomsCalls, 1);
    final state = container.read(lobbyControllerProvider);
    expect(state.rooms.map((listed) => listed.id), ['room-b']);
    expect(state.query, '一起');
    expect(apiA.getMeCalls, 0);
    expect(apiB.getMeCalls, 1);
    expect(container.read(identityControllerProvider).member?.id, 'member-id');
  });

  group('requests sent before the switch', () {
    test('a member still being created keeps its token on the old server and '
        'is not the member on the new one', () async {
      final creating = apiA.createMemberGate = Completer<void>();
      final pending = identity().ensureMember();
      await pumpEventQueue();

      await switcher().switchTo(serverB);
      creating.complete();
      await pending;
      await pumpEventQueue();

      expect(credentials(_defaultId).memberToken, 'new-member-token');
      expect(credentials(serverB.id).memberToken, isNull);
      expect(container.read(identityControllerProvider).member, isNull);
      expect(apiB.createMemberCalls, 0);
    });

    test('a member needed on the new server neither waits for nor shares the '
        'one still being created on the old server', () async {
      final creating = apiA.createMemberGate = Completer<void>();
      apiB.createdMember = const Member(
        id: 'member-b',
        name: 'B 的听众',
        avatarHash: '',
      );
      final onA = identity().ensureMember();
      await pumpEventQueue();

      await switcher().switchTo(serverB);
      final onB = identity().ensureMember();
      await pumpEventQueue();

      expect(apiB.createMemberCalls, 1);
      expect((await onB).id, 'member-b');
      expect(credentials(serverB.id).memberToken, 'new-member-token');
      creating.complete();
      expect((await onA).id, 'member-id');
      await pumpEventQueue();
      expect(container.read(identityControllerProvider).member?.id, 'member-b');
    });

    test('rooms listed by the old server are not shown', () async {
      final answer = Completer<List<RoomListing>>();
      apiA.listRoomsHandler = () => answer.future;
      final loading = lobby().load();

      await switcher().switchTo(serverB);
      await pumpEventQueue();
      answer.complete([roomListing(id: 'old')]);
      await loading;

      final state = container.read(lobbyControllerProvider);
      expect(state.rooms.map((listed) => listed.id), ['room-b']);
      expect(state.loading, isFalse);
    });

    test('a room still being opened is not entered and gets no '
        'ticket', () async {
      final lookup = apiA.getRoomGate = Completer<void>();
      final opening = room().openRoom('room-a');
      await pumpEventQueue();

      await switcher().switchTo(serverB);
      lookup.complete();

      expect(await opening, isA<RoomJoinFailed>());
      expect(rooms.transports, isEmpty);
      expect(credentials(_defaultId).writtenTickets, isEmpty);
      expect(credentials(serverB.id).writtenTickets, isEmpty);
      expect(apiB.getRoomCalls + apiB.createTicketCalls, 0);
      expect(container.read(roomControllerProvider).activeRoomId, isNull);
    });
  });
}
