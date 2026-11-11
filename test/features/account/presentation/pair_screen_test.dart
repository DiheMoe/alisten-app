import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';

void main() {
  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory rooms;
  late ValueNotifier<PairPrefill?> prefill;
  late ValueNotifier<bool> shown;
  late int done;

  final defaultServerId = BuildEnvironment.fromEnvironment().defaultServerId;
  final codeField = find.descendant(
    of: find.widgetWithText(AlistenTextField, '配对码'),
    matching: find.byType(EditableText),
  );

  setUp(() {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
    rooms = FakeRoomTransportFactory();
    prefill = ValueNotifier(null);
    addTearDown(prefill.dispose);
    shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    done = 0;
  });

  Future<ProviderContainer> pumpPair(
    WidgetTester tester, {
    bool inRoom = false,
  }) async {
    if (inRoom) {
      api.rooms = [roomListing()];
      credentials.tickets['room-id'] = 'saved-ticket';
    }
    final other = FakeCredentialStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...alistenWiring(await loadPreferences(const {})),
          alistenApiProvider.overrideWithValue(api),
          credentialStoreFactoryProvider.overrideWithValue(
            (id) => id == serverB.id ? other : credentials,
          ),
          roomTransportFactoryProvider.overrideWithValue(rooms.call),
          connectivityStatusProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: ValueListenableBuilder(
            valueListenable: shown,
            builder: (context, visible, _) => !visible
                ? const SizedBox()
                : ValueListenableBuilder(
                    valueListenable: prefill,
                    builder: (context, value, _) =>
                        PairScreen(prefill: value, onDone: () => done++),
                  ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PairScreen)),
    );
    await container.read(identityControllerProvider.notifier).restore();
    if (inRoom) {
      await container.read(roomControllerProvider.notifier).openRoom('listen');
      rooms.last.emitHello();
    }
    await tester.pumpAndSettle();
    return container;
  }

  String typed(WidgetTester tester) =>
      tester.widget<EditableText>(codeField).controller.text;

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pumpAndSettle();
  }

  testWidgets('a code from a link is filled in, and nothing is sent until '
      'asked', (tester) async {
    prefill.value = (serverId: defaultServerId, fragment: 'abcd-2345');
    await pumpPair(tester);

    expect(find.text('用配对码登录'), findsOneWidget);
    expect(typed(tester), 'ABCD-2345');
    expect(tester.widget<EditableText>(codeField).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(api.redeemCalls, 0);

    await submit(tester);

    expect(api.redeemedCode, 'ABCD2345');
    expect(credentials.memberToken, 'paired-token');
    expect(done, 1);
  });

  testWidgets('a fragment that is no pairing code is not filled in', (
    tester,
  ) async {
    prefill.value = (serverId: defaultServerId, fragment: 'hello%20world');
    await pumpPair(tester);

    expect(typed(tester), '');
  });

  testWidgets('a code that belongs to another server is not filled in', (
    tester,
  ) async {
    prefill.value = (serverId: serverB.id, fragment: 'ABCD2345');
    await pumpPair(tester);

    expect(typed(tester), '');
  });

  testWidgets('a filled-in code is dropped once the server changes', (
    tester,
  ) async {
    prefill.value = (serverId: defaultServerId, fragment: 'ABCD2345');
    final container = await pumpPair(tester);
    expect(typed(tester), 'ABCD-2345');

    final servers = container.read(serverDirectoryProvider.notifier);
    await servers.add(serverB);
    await servers.setCurrent(serverB.id);
    await tester.pumpAndSettle();

    expect(typed(tester), '');
  });

  testWidgets('a new link replaces the code of an open page', (tester) async {
    prefill.value = (serverId: defaultServerId, fragment: 'ABCD2345');
    await pumpPair(tester);

    prefill.value = (serverId: defaultServerId, fragment: 'WXYZ6789');
    await tester.pumpAndSettle();

    expect(typed(tester), 'WXYZ-6789');
  });

  testWidgets('a code out of the rule is told under the form', (tester) async {
    await pumpPair(tester);

    await tester.enterText(codeField, 'abc');
    await submit(tester);

    expect(
      find.descendant(
        of: find.byType(InlineMessage),
        matching: find.text(invalidPairingCodeText),
      ),
      findsOneWidget,
    );
    expect(api.redeemCalls, 0);
    expect(done, 0);
  });

  testWidgets('a typed code becomes uppercase, and the field is neither '
      'corrected nor suggested', (tester) async {
    await pumpPair(tester);

    await tester.enterText(codeField, 'abcd');

    expect(typed(tester), 'ABCD');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.autofillHints, [AutofillHints.oneTimeCode]);
  });

  testWidgets('a signed-in device only says how to switch accounts', (
    tester,
  ) async {
    credentials.memberToken = 'account-token';
    api.account = const Account(username: 'mao', github: false);
    await pumpPair(tester);

    expect(find.text('这台设备已经登录了账号。要换成其他账号，先在设置里退出登录。'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('in a room the page says the room is entered again', (
    tester,
  ) async {
    await pumpPair(tester, inRoom: true);

    expect(find.text('登录后会重新进入当前房间；有密码的房间需要再输入一次房间密码。'), findsOneWidget);
  });

  testWidgets('submitting twice while busy sends one code', (tester) async {
    final gate = Completer<void>();
    api.redeemGate = gate;
    await pumpPair(tester);
    await tester.enterText(codeField, 'ABCD2345');

    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(api.redeemCalls, 1);
    expect(find.byType(BusyIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(api.redeemCalls, 1);
    expect(done, 1);
  });

  testWidgets('a page left while the code is out does not report a login', (
    tester,
  ) async {
    final gate = Completer<void>();
    api.redeemGate = gate;
    await pumpPair(tester);
    await tester.enterText(codeField, 'ABCD2345');
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pump();

    shown.value = false;
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(done, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new link while the code is out keeps the page busy', (
    tester,
  ) async {
    final gate = Completer<void>();
    api.redeemGate = gate;
    prefill.value = (serverId: defaultServerId, fragment: 'ABCD2345');
    await pumpPair(tester);
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pump();

    prefill.value = (serverId: defaultServerId, fragment: 'WXYZ6789');
    await tester.pump();

    expect(find.byType(BusyIndicator), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pump();
    expect(api.redeemCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failure that comes back after a new link is still told', (
    tester,
  ) async {
    final gate = Completer<void>();
    api.redeemGate = gate;
    prefill.value = (serverId: defaultServerId, fragment: 'ABCD2345');
    await pumpPair(tester);
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pump();

    prefill.value = (serverId: defaultServerId, fragment: 'WXYZ6789');
    await tester.pump();
    api.redeemError = const ApiException(
      code: 'INVALID_CREDENTIALS',
      message: '配对码不对或已经过期',
      status: 400,
    );
    gate.complete();
    await tester.pumpAndSettle();

    expect(typed(tester), 'WXYZ-6789');
    expect(
      find.descendant(
        of: find.byType(InlineMessage),
        matching: find.text('配对码不对或已经过期'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a new link clears what was told about the last code', (
    tester,
  ) async {
    api.redeemError = const ApiException(
      code: 'INVALID_CREDENTIALS',
      message: '配对码不对或已经过期',
      status: 400,
    );
    prefill.value = (serverId: defaultServerId, fragment: 'ABCD2345');
    await pumpPair(tester);
    await submit(tester);
    expect(find.byType(InlineMessage), findsOneWidget);

    prefill.value = (serverId: defaultServerId, fragment: 'WXYZ6789');
    await tester.pumpAndSettle();

    expect(typed(tester), 'WXYZ-6789');
    expect(find.byType(InlineMessage), findsNothing);
  });

  testWidgets('a refused code is told with the server message, and the '
      'button works again', (tester) async {
    api.redeemError = const ApiException(
      code: 'INVALID_CREDENTIALS',
      message: '配对码不对或已经过期',
      status: 400,
    );
    await pumpPair(tester);
    await tester.enterText(codeField, 'ABCD2345');
    await submit(tester);

    expect(
      find.descendant(
        of: find.byType(InlineMessage),
        matching: find.text('配对码不对或已经过期'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, '登录'))
          .onPressed,
      isNotNull,
    );
    expect(done, 0);
  });

  testWidgets('a lost answer says no result was confirmed', (tester) async {
    api.redeemError = const ApiException(
      code: LocalErrorCodes.network,
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );
    await pumpPair(tester);
    await tester.enterText(codeField, 'ABCD2345');
    await submit(tester);

    expect(find.text('没有确认结果，请稍后再试。'), findsOneWidget);
    expect(done, 0);
  });

  testWidgets('a device that turns out to be signed in ends on the note', (
    tester,
  ) async {
    api.redeemError = const ApiException(
      code: 'CONFLICT',
      message: '服务端',
      status: 409,
    );
    await pumpPair(tester);
    api.account = const Account(username: 'mao', github: false);
    await tester.enterText(codeField, 'ABCD2345');
    await submit(tester);

    expect(find.text('这台设备已经登录了账号。要换成其他账号，先在设置里退出登录。'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(done, 0);
  });
}
