import 'package:alisten/app/app.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/room/data/preferences_last_room_store.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import '../features/room/room_test_doubles.dart';
import 'app_test_harness.dart';

void main() {
  testWidgets('a pairing link of this server opens the pairing page with the '
      'code and its server in the extra, never in the location', (
    tester,
  ) async {
    final links = FakeAppLinkSource();
    final api = FakeAlistenApi();
    await pumpAlistenApp(tester, links: links, api: api);
    final container = appContainer(tester);
    final host = container.read(appConfigProvider).linkHost;

    links.open(Uri.parse('https://$host/pair#abcd-2345'));
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    expect(router.state.uri.toString(), '/settings/account/pair');
    expect(router.state.extra, (
      serverId: container.read(currentServerProvider).id,
      fragment: 'abcd-2345',
    ));
    expect(find.byType(PairScreen), findsOneWidget);
    final field = find.descendant(
      of: find.widgetWithText(AlistenTextField, '配对码'),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).controller.text, 'ABCD-2345');
    expect(api.redeemCalls, 0);
  });

  testWidgets('a pairing link of another server says to switch first and '
      'opens nothing', (tester) async {
    final links = FakeAppLinkSource();
    await pumpAlistenApp(tester, links: links);

    links.open(Uri.parse('https://other.example/pair#ABCD2345'));
    await tester.pumpAndSettle();

    expect(find.text('这个配对码属于 other.example，先切换到这个服务器再输入。'), findsOneWidget);
    expect(find.byType(PairScreen), findsNothing);
  });

  testWidgets('a pairing link that starts the app opens the page with the '
      'code, restores the last room behind it and sends nothing', (
    tester,
  ) async {
    final env = BuildEnvironment.fromEnvironment();
    final rooms = FakeRoomTransportFactory();
    final api = FakeAlistenApi()
      ..rooms = [roomListing(id: testRoomId, slug: 'listen')];
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(
          api: api,
          credentials: FakeCredentialStore()
            ..tickets[testRoomId] = 'saved-ticket',
          rooms: rooms,
          links: FakeAppLinkSource(
            initial: Uri.parse('https://${env.defaultLinkHost}/pair#ABCD2345'),
          ),
          preferences: {
            PreferencesLastRoomStore.keyFor(env.defaultServerId): 'listen',
          },
        ),
        child: const AlistenApp(),
      ),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      appContainer(tester).read(routerProvider).state.uri.toString(),
      '/settings/account/pair',
    );
    final field = find.descendant(
      of: find.widgetWithText(AlistenTextField, '配对码'),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).controller.text, 'ABCD-2345');
    expect(rooms.roomIds, contains(testRoomId));
    expect(api.redeemCalls, 0);
  });
}
