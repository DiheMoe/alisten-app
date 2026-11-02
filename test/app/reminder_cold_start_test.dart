import 'package:alisten/app/app.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/features/room/data/preferences_last_room_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import '../features/room/room_test_doubles.dart';
import '../features/server/server_test_doubles.dart' show serverB;
import 'app_test_harness.dart';

const _otherServerText = '这首歌在另一个服务器上';

final _defaultId = BuildEnvironment.fromEnvironment().defaultServerId;

// `pumpAlistenApp` 会等待页面稳定，进入房间页后等不到，所以这里手动推进时间。
Future<FakeRoomTransportFactory> _launch(
  WidgetTester tester,
  String payload,
) async {
  final rooms = FakeRoomTransportFactory();
  await tester.pumpWidget(
    ProviderScope(
      overrides: await alistenAppOverrides(
        api: FakeAlistenApi()
          ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
        credentials: FakeCredentialStore()
          ..tickets[testRoomId] = 'saved-ticket',
        rooms: rooms,
        notifications: FakeNotificationGateway(launchPayload: payload),
        preferences: {PreferencesLastRoomStore.keyFor(_defaultId): 'listen'},
      ),
      child: const AlistenApp(),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return rooms;
}

void main() {
  testWidgets('a start from a reminder of another server stays in the lobby '
      'and does not enter the last room', (tester) async {
    final rooms = await _launch(tester, '${serverB.id}:room-1:entry-1');

    expect(appContainer(tester).read(routerProvider).state.uri.path, '/');
    expect(find.text(_otherServerText), findsOneWidget);
    expect(rooms.roomIds, isEmpty);
  });

  testWidgets('a start from a reminder of the current server opens its room '
      'rather than the last room', (tester) async {
    final rooms = await _launch(tester, '$_defaultId:room-1:entry-1');

    expect(
      appContainer(tester).read(routerProvider).state.uri.path,
      '/r/room-1',
    );
    expect(find.text(_otherServerText), findsNothing);
    expect(rooms.roomIds.where((id) => id == testRoomId), isEmpty);
  });
}
