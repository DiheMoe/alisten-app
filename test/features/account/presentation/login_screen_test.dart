import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';

void main() {
  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory rooms;
  late int done;

  setUp(() {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
    rooms = FakeRoomTransportFactory();
    done = 0;
  });

  Future<void> pumpLogin(WidgetTester tester, {bool inRoom = false}) async {
    if (inRoom) {
      api.rooms = [roomListing()];
      credentials.tickets['room-id'] = 'saved-ticket';
    }
    final overrides = [
      ...alistenWiring(await loadPreferences(const {})),
      alistenApiProvider.overrideWithValue(api),
      credentialStoreFactoryProvider.overrideWithValue((_) => credentials),
      roomTransportFactoryProvider.overrideWithValue(rooms.call),
      connectivityStatusProvider.overrideWith((ref) => const Stream.empty()),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(identityControllerProvider);
              return LoginScreen(onDone: () => done++, onOpenRegister: () {});
            },
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginScreen)),
    );
    await container.read(identityControllerProvider.notifier).restore();
    if (inRoom) {
      await container.read(roomControllerProvider.notifier).openRoom('listen');
      rooms.last.emitHello();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong password is shown under the form and read out', (
    tester,
  ) async {
    api.loginError = const ApiException(
      code: 'INVALID_CREDENTIALS',
      message: '服务端',
      status: 401,
    );
    await pumpLogin(tester);

    await tester.enterText(find.byType(TextField).at(0), 'mao');
    await tester.enterText(find.byType(TextField).at(1), 'password1');
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text(wrongCredentialsText), findsOneWidget);
    expect(done, 0);
  });

  testWidgets('uppercase letters typed into the username become lowercase', (
    tester,
  ) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).at(0), 'MaO');
    expect(find.text('mao'), findsOneWidget);
  });

  testWidgets('the username is neither corrected nor suggested, and login '
      'asks for the password once', (tester) async {
    await pumpLogin(tester);
    final username = tester.widget<TextField>(find.byType(TextField).at(0));

    expect(username.autocorrect, isFalse);
    expect(username.enableSuggestions, isFalse);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('a successful login finishes the page', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).at(0), 'mao');
    await tester.enterText(find.byType(TextField).at(1), 'password1');
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pumpAndSettle();

    expect(done, 1);
    expect(credentials.memberToken, 'account-token');
  });

  testWidgets('the room note appears only in a room', (tester) async {
    await pumpLogin(tester);
    expect(find.textContaining('重新进入当前房间'), findsNothing);
  });

  testWidgets('in a room the page says the room is entered again', (
    tester,
  ) async {
    await pumpLogin(tester, inRoom: true);
    expect(find.text('登录后会重新进入当前房间；有密码的房间需要再输入一次房间密码。'), findsOneWidget);
  });

  group('the register entry', () {
    testWidgets('is shown while registration is open', (tester) async {
      api.site = const SiteCapabilities(
        registrationOpen: true,
        githubLogin: false,
      );
      await pumpLogin(tester);
      expect(find.text('注册账号'), findsOneWidget);
    });

    testWidgets('is hidden once registration is closed', (tester) async {
      api.site = const SiteCapabilities(
        registrationOpen: false,
        githubLogin: false,
      );
      await pumpLogin(tester);
      expect(find.text('注册账号'), findsNothing);
    });

    testWidgets('is shown when the site cannot be read', (tester) async {
      api.getSiteError = const ApiException(
        code: 'INTERNAL',
        message: '服务端',
        status: 500,
      );
      await pumpLogin(tester);
      expect(find.text('注册账号'), findsOneWidget);
    });
  });

  testWidgets('submitting twice while busy sends one login', (tester) async {
    final gate = Completer<void>();
    api.loginGate = gate;
    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).at(0), 'mao');
    await tester.enterText(find.byType(TextField).at(1), 'password1');

    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pump();
    await tester.tap(find.byType(PillButton).first, warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(api.loginCalls, 1);
    expect(find.byType(BusyIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(api.loginCalls, 1);
    expect(done, 1);
  });
}
