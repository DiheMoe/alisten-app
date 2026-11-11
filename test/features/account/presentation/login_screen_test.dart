import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/application/github_controller.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../account_test_doubles.dart';

void main() {
  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory rooms;
  late FakeGithubAuthorizer authorizer;
  late List<(ToastKind, String)> notices;
  late ValueNotifier<bool> present;
  late int done;
  late int pairing;

  setUp(() {
    pairing = 0;
    api = FakeAlistenApi();
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
    rooms = FakeRoomTransportFactory();
    authorizer = FakeGithubAuthorizer();
    notices = [];
    present = ValueNotifier(true);
    done = 0;
  });

  tearDown(() => present.dispose());

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
      githubAuthorizerProvider.overrideWithValue(authorizer),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(identityControllerProvider);
              return ValueListenableBuilder(
                valueListenable: present,
                builder: (context, shown, _) => shown
                    ? LoginScreen(
                        onDone: () => done++,
                        onOpenRegister: () {},
                        onOpenPairing: () => pairing++,
                        onNotice: (kind, text) => notices.add((kind, text)),
                      )
                    : const SizedBox.shrink(),
              );
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

  void withGithub() {
    api.site = const SiteCapabilities(
      registrationOpen: true,
      githubLogin: true,
    );
  }

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'mao');
    await tester.enterText(find.byType(TextField).at(1), 'password1');
  }

  Finder button(String label) => find.widgetWithText(PillButton, label);

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<PillButton>(button(label)).onPressed != null;

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

  testWidgets('a successful login says so and finishes the page', (
    tester,
  ) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).at(0), 'mao');
    await tester.enterText(find.byType(TextField).at(1), 'password1');
    await tester.tap(find.widgetWithText(PillButton, '登录'));
    await tester.pumpAndSettle();

    expect(done, 1);
    expect(notices, [(ToastKind.success, '已登录')]);
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

  group('other ways to sign in', () {
    testWidgets('sit under a divider below the password login, GitHub first', (
      tester,
    ) async {
      withGithub();
      await pumpLogin(tester);

      final tops = [
        tester.getTopLeft(button('登录')).dy,
        tester.getTopLeft(find.text('其他登录方式')).dy,
        tester.getTopLeft(button('用 GitHub 登录')).dy,
        tester.getTopLeft(button('输入配对码')).dy,
      ];
      expect(tops, [...tops]..sort());
      expect(button('输入配对码'), findsOneWidget);
      expect(
        tester.widget<PillButton>(button('用 GitHub 登录')).style,
        PillButtonStyle.secondary,
      );
      expect(
        tester.widget<PillButton>(button('输入配对码')).style,
        PillButtonStyle.secondary,
      );
    });

    testWidgets('fit a narrow screen with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(280, 760) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      withGithub();
      await pumpLogin(tester);

      await tester.scrollUntilVisible(
        find.text('其他登录方式'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('offer GitHub only while the site has it', (tester) async {
      await pumpLogin(tester);

      expect(find.text('其他登录方式'), findsOneWidget);
      expect(find.text('用 GitHub 登录'), findsNothing);
      expect(button('输入配对码'), findsOneWidget);
    });

    testWidgets('the pairing entry opens the pairing page', (tester) async {
      await pumpLogin(tester);

      await tester.tap(button('输入配对码'));

      expect(pairing, 1);
    });

    testWidgets('signing in with GitHub keeps its button busy, then says how '
        'it ended and finishes the page', (tester) async {
      withGithub();
      authorizer.gate = Completer<void>();
      await pumpLogin(tester);

      await tester.tap(button('用 GitHub 登录'));
      await tester.pump();
      expect(
        find.descendant(
          of: button('用 GitHub 登录'),
          matching: find.byType(BusyIndicator),
        ),
        findsOneWidget,
      );
      expect(done, 0);

      authorizer.gate!.complete();
      await tester.pumpAndSettle();
      expect(notices, [(ToastKind.success, '已用 GitHub 注册')]);
      expect(done, 1);
    });

    testWidgets('a GitHub bound to an account signs in to it and finishes the '
        'page', (tester) async {
      withGithub();
      api.githubExchange = const GithubExchange(
        signedIn: SignedIn(
          memberToken: 'github-account-token',
          member: accountMember,
          account: Account(username: 'mao', github: true),
        ),
        member: accountMember,
        account: Account(username: 'mao', github: true),
      );
      await pumpLogin(tester);

      await tester.tap(button('用 GitHub 登录'));
      await tester.pumpAndSettle();

      expect(notices, [(ToastKind.success, '已登录')]);
      expect(done, 1);
      expect(credentials.memberToken, 'github-account-token');
    });

    testWidgets('a GitHub sign-in that brings back no result stays on the '
        'page and says so as a failure', (tester) async {
      withGithub();
      authorizer.callback = null;
      await pumpLogin(tester);

      await tester.tap(button('用 GitHub 登录'));
      await tester.pumpAndSettle();

      expect(notices, [(ToastKind.failure, githubNoResultText)]);
      expect(done, 0);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(enabled(tester, '用 GitHub 登录'), isTrue);
    });

    testWidgets('a GitHub authorization cancelled on GitHub says so and stays '
        'on the page', (tester) async {
      withGithub();
      authorizer.callback = Uri.parse(
        'moe.dihe.alisten:/auth/github#error=denied',
      );
      await pumpLogin(tester);

      await tester.tap(button('用 GitHub 登录'));
      await tester.pumpAndSettle();

      expect(notices, [(ToastKind.failure, '你在 GitHub 上取消了授权。')]);
      expect(done, 0);
    });

    testWidgets('a GitHub sign-in that ends after the page is gone is still '
        'reported, and finishes nothing', (tester) async {
      withGithub();
      authorizer.gate = Completer<void>();
      await pumpLogin(tester);
      await tester.tap(button('用 GitHub 登录'));
      await tester.pump();

      present.value = false;
      await tester.pump();
      expect(find.byType(LoginScreen), findsNothing);
      authorizer.gate!.complete();
      await tester.pumpAndSettle();

      expect(notices, [(ToastKind.success, '已用 GitHub 注册')]);
      expect(done, 0);
    });

    testWidgets('while GitHub runs the password login cannot be sent', (
      tester,
    ) async {
      withGithub();
      authorizer.gate = Completer<void>();
      authorizer.callback = null;
      await pumpLogin(tester);
      await fillIn(tester);

      await tester.tap(button('用 GitHub 登录'));
      await tester.pump();
      expect(enabled(tester, '登录'), isFalse);
      await tester.tap(button('登录'), warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(api.loginCalls, 0);

      authorizer.gate!.complete();
      await tester.pumpAndSettle();
      expect(enabled(tester, '登录'), isTrue);
      expect(api.loginCalls, 0);
    });

    testWidgets('a GitHub sign-in started elsewhere shows busy here too', (
      tester,
    ) async {
      withGithub();
      authorizer.gate = Completer<void>();
      authorizer.callback = null;
      await pumpLogin(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LoginScreen)),
      );

      final signingIn = container
          .read(githubControllerProvider.notifier)
          .signIn();
      await tester.pump();
      expect(
        find.descendant(
          of: button('用 GitHub 登录'),
          matching: find.byType(BusyIndicator),
        ),
        findsOneWidget,
      );
      expect(enabled(tester, '登录'), isFalse);

      authorizer.gate!.complete();
      await signingIn;
      await tester.pumpAndSettle();
      expect(enabled(tester, '用 GitHub 登录'), isTrue);
      expect(enabled(tester, '登录'), isTrue);
    });

    testWidgets('while a password login is in flight GitHub cannot start', (
      tester,
    ) async {
      withGithub();
      final gate = Completer<void>();
      api.loginGate = gate;
      await pumpLogin(tester);
      await fillIn(tester);

      await tester.tap(button('登录'));
      await tester.pump();
      expect(enabled(tester, '用 GitHub 登录'), isFalse);
      await tester.tap(button('用 GitHub 登录'), warnIfMissed: false);
      await tester.pump();
      expect(api.githubStarts, isEmpty);
      expect(authorizer.opened, isEmpty);

      gate.complete();
      await tester.pumpAndSettle();
      expect(done, 1);
      expect(api.githubStarts, isEmpty);
    });

    testWidgets('a failed password login gives GitHub back', (tester) async {
      withGithub();
      api.loginError = const ApiException(
        code: 'INVALID_CREDENTIALS',
        message: '服务端',
        status: 401,
      );
      await pumpLogin(tester);
      await fillIn(tester);

      await tester.tap(button('登录'));
      await tester.pumpAndSettle();

      expect(find.text(wrongCredentialsText), findsOneWidget);
      expect(enabled(tester, '用 GitHub 登录'), isTrue);
    });
  });
}
