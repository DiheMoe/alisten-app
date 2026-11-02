import 'dart:convert';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/server/data/preferences_server_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/server/server_test_doubles.dart' show serverB;
import 'app_test_harness.dart';

const _otherServerText = '这首歌在另一个服务器上';

final _defaultId = BuildEnvironment.fromEnvironment().defaultServerId;

Future<({FakeNotificationGateway gateway, String Function() location})> _open(
  WidgetTester tester, {
  ServerProfile? current,
}) async {
  final gateway = FakeNotificationGateway();
  await pumpAlistenApp(
    tester,
    notifications: gateway,
    preferences: {
      if (current != null) ...{
        PreferencesServerStore.profilesKey: jsonEncode([current.toJson()]),
        PreferencesServerStore.currentKey: current.id,
      },
    },
  );
  final router = appContainer(tester).read(routerProvider);
  router.go('/history');
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(router.state.uri.path, '/history');
  return (gateway: gateway, location: () => router.state.uri.path);
}

Future<void> _tap(
  WidgetTester tester,
  FakeNotificationGateway gateway,
  String payload,
) async {
  gateway.tap(payload);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _notifyFrom(WidgetTester tester) async {
  await appContainer(tester)
      .read(reminderNotifierProvider)
      .notify(
        appVisible: false,
        enabled: true,
        systemEnabled: true,
        permissionGranted: true,
        roomId: 'room-1',
        entryId: 'entry-1',
        title: '歌曲',
      );
}

void main() {
  testWidgets('a reminder of the current server opens its room', (
    tester,
  ) async {
    final (:gateway, :location) = await _open(tester);

    await _tap(tester, gateway, '$_defaultId:room-1:entry-1');

    expect(location(), '/r/room-1');
    expect(find.text(_otherServerText), findsNothing);
  });

  testWidgets('a reminder of another server goes back to the lobby and says '
      'the song is elsewhere', (tester) async {
    final (:gateway, :location) = await _open(tester);

    await _tap(tester, gateway, '${serverB.id}:room-1:entry-1');

    expect(location(), '/');
    expect(find.text(_otherServerText), findsOneWidget);
  });

  testWidgets('a reminder sent before servers were kept belongs to the '
      'default server', (tester) async {
    final (:gateway, :location) = await _open(tester);

    await _tap(tester, gateway, '$testRoomId:entry-1');

    expect(location(), '/r/$testRoomId');
    expect(find.text(_otherServerText), findsNothing);
  });

  testWidgets('with another server current, its reminder opens the room and '
      'the default server\'s does not', (tester) async {
    final (:gateway, :location) = await _open(tester, current: serverB);

    await _tap(tester, gateway, '${serverB.id}:room-1:entry-1');
    expect(location(), '/r/room-1');
    expect(find.text(_otherServerText), findsNothing);

    appContainer(tester).read(routerProvider).go('/history');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, gateway, '$_defaultId:room-1:entry-1');
    expect(location(), '/');
    expect(find.text(_otherServerText), findsOneWidget);
  });

  testWidgets('with another server current, an old reminder is the default '
      'server\'s', (tester) async {
    final (:gateway, :location) = await _open(tester, current: serverB);

    await _tap(tester, gateway, '$testRoomId:entry-1');

    expect(location(), '/');
    expect(find.text(_otherServerText), findsOneWidget);
  });

  testWidgets('the reminder the app sends names the server that is current', (
    tester,
  ) async {
    final gateway = FakeNotificationGateway();
    await pumpAlistenApp(tester, notifications: gateway);

    await _notifyFrom(tester);

    expect(gateway.shown, ['$_defaultId:room-1:entry-1']);
  });

  testWidgets('the reminder the app sends after a switch names the server it '
      'switched to', (tester) async {
    final gateway = FakeNotificationGateway();
    await pumpAlistenApp(
      tester,
      notifications: gateway,
      preferences: {
        PreferencesServerStore.profilesKey: jsonEncode([serverB.toJson()]),
        PreferencesServerStore.currentKey: serverB.id,
      },
    );

    await _notifyFrom(tester);

    expect(gateway.shown, ['${serverB.id}:room-1:entry-1']);
  });
}
