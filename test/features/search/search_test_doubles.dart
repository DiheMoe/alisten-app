import 'dart:async';

import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/search_controller.dart';
import 'package:alisten/features/search/application/search_history_store.dart';
import 'package:alisten/features/search/application/search_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_test_harness.dart';
import '../../domain/room/room_fixtures.dart';
import '../lobby/lobby_test_doubles.dart';
import '../room/room_test_doubles.dart';
import '../server/server_test_doubles.dart' show FakeServerProbe;
import '../settings/settings_test_doubles.dart';
import 'share_test_doubles.dart';

/// 添加规则与真实存储相同。
final class FakeSearchHistoryStore implements SearchHistoryStore {
  FakeSearchHistoryStore([List<SearchRecord> records = const []])
    : records = [...records];

  List<SearchRecord> records;
  int adds = 0;
  int clears = 0;
  Exception? addError;

  @override
  Future<List<SearchRecord>> read() async => records;

  @override
  Future<void> add(SearchRecord record, {required int limit}) async {
    adds++;
    final error = addError;
    if (error != null) throw error;
    records = recordSearch(records, record, limit);
  }

  @override
  Future<void> truncate(int limit) async {
    records = records.take(limit).toList();
  }

  @override
  Future<void> clear() async {
    clears++;
    records = [];
  }
}

final class SearchHarness {
  SearchHarness._(this.container, this.factory, this.history);

  final ProviderContainer container;
  final FakeRoomTransportFactory factory;
  final FakeSearchHistoryStore history;

  FakeRoomTransport get transport => factory.last;
  SearchController get search =>
      container.read(searchControllerProvider.notifier);
  SearchState get state => container.read(searchControllerProvider);

  List<Map<String, Object?>> get requests => transport.requests;

  static Future<SearchHarness> open({
    int Function()? now,
    Map<String, Object> preferences = const {},
    FakeSearchHistoryStore? history,
  }) async {
    final api = FakeAlistenApi()
      ..rooms = [
        roomListing(id: 'room-id', slug: 'listen'),
        roomListing(id: 'room-two', slug: 'two'),
      ];
    final credentials = FakeCredentialStore()
      ..tickets['room-id'] = 'ticket-one'
      ..tickets['room-two'] = 'ticket-two';
    final factory = FakeRoomTransportFactory();
    final store = history ?? FakeSearchHistoryStore();
    final container = ProviderContainer(
      overrides: [
        await preferencesOverride(preferences),
        alistenApiProvider.overrideWithValue(api),
        credentialStoreProvider.overrideWithValue(credentials),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(),
        searchHistoryStoreProvider.overrideWith((ref) => store),
        ...settingsOverrides(trimSearchHistory: store.truncate),
        searchControllerProvider.overrideWith(() => SearchController(now: now)),
      ],
    );
    final harness = SearchHarness._(container, factory, store);
    await container.read(roomControllerProvider.notifier).openRoom('listen');
    harness.enter();
    container.read(searchControllerProvider);
    await pumpEventQueue();
    return harness;
  }

  void enter() {
    transport
      ..emitHello()
      ..responses.addAll(defaultSearchAnswers());
  }

  Future<void> openRoom(String ref) async {
    await container.read(roomControllerProvider.notifier).openRoom(ref);
    enter();
    await pumpEventQueue();
  }

  void dispose() => container.dispose();
}

const _roomId = '123e4567-e89b-42d3-a456-426614174000';

final class SearchPage {
  SearchPage._(this.tester, this.rooms, this.router);

  final WidgetTester tester;
  final FakeRoomTransportFactory rooms;
  final GoRouter router;
  Completer<Map<String, Object?>>? _heldAdd;

  FakeRoomTransport get transport => rooms.last;

  int get adds => [
    for (final request in transport.requests)
      if (request['type'] == 'queue.add') request,
  ].length;

  static Future<SearchPage> open(
    WidgetTester tester, {
    RoomKind kind = RoomKind.ephemeral,
    FakeClipboardSource? clipboard,
    FakeServerProbe? probe,
    MediaQueryData system = const MediaQueryData(),
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
      rooms: rooms,
      clipboard: clipboard,
      probe: probe,
      system: system,
    );
    final router = appContainer(tester).read(routerProvider);
    final page = SearchPage._(tester, rooms, router);
    router.go('/r/listen/search');
    await page.settle();
    rooms.last
      ..responses.addAll(defaultSearchAnswers())
      ..emitHello(
        testRoomSnapshot().copyWith(
          term: 1,
          seq: 1,
          room: RoomInfo(id: _roomId, name: '一起听', description: '', kind: kind),
        ),
      );
    await page.settle();
    return page;
  }

  /// 加载动画持续转动，界面不会静止，只能按固定步长推进时间。
  Future<void> settle() async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> search(String keyword) async {
    await tester.enterText(find.byType(EditableText), keyword);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle();
  }

  void holdAdds() {
    transport.requestHandler = (type, data) {
      if (type != 'queue.add') {
        return Future.value(transport.responses[type] ?? const {});
      }
      return (_heldAdd = Completer()).future;
    };
  }

  void answerAdd(String title) {
    _heldAdd!.complete({'entry': entryJson(title)});
  }

  void loseAdd() {
    _heldAdd!.completeError(
      const RoomRequestException(
        message: '连接已断开，结果未知。',
        outcome: RoomRequestOutcome.unknown,
      ),
    );
  }
}

Map<String, Object?> entryJson(String title) {
  return {
    'id': 'entry-$title',
    'track': {'source': 'netease', 'id': title},
    'meta': {
      'title': title,
      'artist': 'artist',
      'album': 'album',
      'coverUrl': '',
      'pageUrl': '',
      'durationMs': 1000,
    },
    'by': null,
    'auto': false,
    'likes': 0,
    'status': 'ready',
  };
}

Map<String, Map<String, Object?>> defaultSearchAnswers() {
  return {
    'search.tracks': {
      'items': List.generate(6, (index) => trackJson('track-$index')),
      'total': 42,
    },
    'search.playlists': {
      'items': List.generate(7, (index) => playlistJson('playlist-$index')),
      'total': 7,
    },
    'recommend.list': {
      'items': [trackJson('recommended')],
    },
    'playlist.tracks': {
      'items': List.generate(21, (index) => trackJson('song-$index')),
      'total': 21,
    },
  };
}

Map<String, Object?> tracksAnswer(List<String> ids, {int? total}) {
  return {
    'items': [for (final id in ids) trackJson(id)],
    'total': total ?? ids.length,
  };
}

Map<String, Object?> trackJson(String id) {
  return {
    'track': {'source': 'netease', 'id': id},
    'meta': {
      'title': id,
      'artist': 'artist',
      'album': 'album',
      'coverUrl': '',
      'pageUrl': 'https://example.com/$id',
      'durationMs': 1000,
    },
  };
}

Map<String, Object?> playlistJson(String id, {String? name}) {
  return {
    'source': 'netease',
    'id': id,
    'name': name ?? id,
    'coverUrl': '',
    'creator': 'creator',
    'description': '',
    'trackCount': 20,
    'playCount': 0,
  };
}
