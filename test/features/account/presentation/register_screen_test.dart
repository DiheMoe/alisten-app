import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/inline_message.dart';
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

  Future<ProviderContainer> pumpRegister(WidgetTester tester) async {
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
              return RegisterScreen(onDone: () => done++);
            },
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RegisterScreen)),
    );
    await container.read(identityControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
    return container;
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AlistenTextField, label),
    matching: find.byType(EditableText),
  );

  Future<void> submit(WidgetTester tester, {String again = 'password1'}) async {
    await tester.enterText(field('用户名'), 'mao');
    await tester.enterText(field('密码'), 'password1');
    await tester.enterText(field('再次输入密码'), again);
    await tester.tap(find.widgetWithText(PillButton, '注册'));
    await tester.pumpAndSettle();
  }

  testWidgets('both rules are shown, without a description, as on the web', (
    tester,
  ) async {
    await pumpRegister(tester);
    expect(find.text('注册后可以在其他设备上登录，昵称和头像会保留。'), findsNothing);
    expect(find.text('用户名要 3–32 位小写字母、数字、_ 或 -'), findsOneWidget);
    expect(find.text('密码要 8 到 128 位'), findsOneWidget);
  });

  testWidgets('a password typed differently the second time is not sent', (
    tester,
  ) async {
    await pumpRegister(tester);
    await submit(tester, again: 'password2');

    expect(
      find.descendant(
        of: find.byType(InlineMessage),
        matching: find.text('两次输入的密码不一样。'),
      ),
      findsOneWidget,
    );
    expect(api.registerCalls, 0);
    expect(done, 0);
  });

  testWidgets('the toggle shows both passwords', (tester) async {
    await pumpRegister(tester);
    bool obscured(String label) =>
        tester.widget<EditableText>(field(label)).obscureText;

    expect(obscured('密码'), isTrue);
    expect(obscured('再次输入密码'), isTrue);
    await tester.tap(find.byType(AlistenToggle));
    await tester.pumpAndSettle();
    expect(obscured('密码'), isFalse);
    expect(obscured('再次输入密码'), isFalse);
  });

  testWidgets('a successful register finishes the page as that account', (
    tester,
  ) async {
    final container = await pumpRegister(tester);
    await submit(tester);

    expect(api.registerCalls, 1);
    expect(done, 1);
    expect(container.read(identityControllerProvider).account?.username, 'mao');
  });

  testWidgets('a refused register is explained and does not finish', (
    tester,
  ) async {
    api.registerError = const ApiException(
      code: 'FORBIDDEN',
      message: '服务端',
      status: 403,
    );
    await pumpRegister(tester);
    await submit(tester);

    expect(
      find.descendant(
        of: find.byType(InlineMessage),
        matching: find.text(registrationClosedText),
      ),
      findsOneWidget,
    );
    expect(done, 0);
  });
}
