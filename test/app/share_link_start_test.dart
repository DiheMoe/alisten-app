import 'dart:async';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/features/room/data/preferences_last_room_store.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import '../features/playlists/playlists_test_doubles.dart';
import '../features/room/room_test_doubles.dart';
import '../features/server/server_test_doubles.dart' show FakeServerProbe;
import 'app_test_harness.dart';

const _shareId = 'AbCdEfGhIjKlMnOpQrStUv';

final _environment = BuildEnvironment.fromEnvironment();

// 插件送达启动链接与 getInitialLink 返回的先后不固定；这里先送达链接。
final class _LinkFirstSource implements AppLinkSource {
  _LinkFirstSource(this._link);

  final Uri _link;
  final _followed = Completer<void>();
  late final StreamController<Uri> _links = StreamController.broadcast(
    sync: true,
    onListen: () => scheduleMicrotask(() {
      _links.add(_link);
      _followed.complete();
    }),
  );

  @override
  Future<Uri?> getInitialLink() async {
    await _followed.future;
    return _link;
  }

  @override
  Stream<Uri> get uriLinkStream => _links.stream;
}

// 进入房间页后页面不会稳定，只能手动推进时间。
Future<FakeRoomTransportFactory> _launch(
  WidgetTester tester,
  Uri link, {
  AppLinkSource? links,
  FakeServerProbe? probe,
  FakePlaylistApi? playlists,
}) async {
  final rooms = FakeRoomTransportFactory();
  await tester.pumpWidget(
    ProviderScope(
      overrides: await alistenAppOverrides(
        api: FakeAlistenApi()
          ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
        credentials: FakeCredentialStore()
          ..tickets[testRoomId] = 'saved-ticket',
        rooms: rooms,
        links: links ?? FakeAppLinkSource(initial: link),
        probe: probe,
        playlists: playlists,
        preferences: {
          PreferencesLastRoomStore.keyFor(_environment.defaultServerId):
              'listen',
        },
      ),
      child: const AlistenApp(),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  return rooms;
}

void main() {
  final host = _environment.defaultLinkHost;

  testWidgets('a start from a shared playlist link shows it and still '
      'restores the last room behind it', (tester) async {
    final rooms = await _launch(tester, Uri.parse('https://$host/s/$_shareId'));

    expect(
      appContainer(tester).read(routerProvider).state.uri.path,
      '/s/$_shareId',
    );
    expect(rooms.roomIds, contains(testRoomId));
  });

  testWidgets('a shared playlist link followed before the start is known '
      'still leaves the last room to be restored', (tester) async {
    final link = Uri.parse('https://$host/s/$_shareId');

    final rooms = await _launch(tester, link, links: _LinkFirstSource(link));

    expect(rooms.roomIds, contains(testRoomId));
  });

  testWidgets('a start from a shared playlist link of another server '
      'restores the last room here and asks before switching', (tester) async {
    final probe = FakeServerProbe()
      ..siteResults['https://other.example'] = const ProbeSucceeded(
        origin: 'https://other.example',
        brandName: '别站',
      );
    final playlists = FakePlaylistApi();

    final rooms = await _launch(
      tester,
      Uri.parse('https://other.example/s/$_shareId'),
      probe: probe,
      playlists: playlists,
    );

    expect(find.text('添加 别站 并打开歌单？'), findsOneWidget);
    expect(rooms.roomIds, contains(testRoomId));
    expect(playlists.count('shared'), 0);
  });

  testWidgets('a start from a room link opens that room rather than the '
      'last one', (tester) async {
    final rooms = await _launch(tester, Uri.parse('https://$host/r/room-1'));

    expect(
      appContainer(tester).read(routerProvider).state.uri.path,
      '/r/room-1',
    );
    expect(rooms.roomIds.where((id) => id == testRoomId), isEmpty);
  });
}
