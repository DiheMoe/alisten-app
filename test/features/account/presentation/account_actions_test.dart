import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/application/github_controller.dart';
import 'package:alisten/features/account/application/pairing_code_controller.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/account/presentation/change_password_sheet.dart';
import 'package:alisten/features/account/presentation/github_notice.dart';
import 'package:alisten/features/account/presentation/github_password_sheet.dart';
import 'package:alisten/features/account/presentation/set_credentials_sheet.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
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

  setUp(() {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
    rooms = FakeRoomTransportFactory();
    authorizer = FakeGithubAuthorizer();
    notices = [];
    present = ValueNotifier(true);
  });

  tearDown(() => present.dispose());

  Future<void> pumpActions(WidgetTester tester, {bool inRoom = false}) async {
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
      pairingNowProvider.overrideWithValue(() => 1700000000000),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(identityControllerProvider);
                return ValueListenableBuilder(
                  valueListenable: present,
                  builder: (context, shown, _) => shown
                      ? AccountActions(
                          onOpenLogin: () {},
                          onOpenRegister: () {},
                          onNotice: (kind, text) => notices.add((kind, text)),
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AccountActions)),
    );
    await container.read(identityControllerProvider.notifier).restore();
    if (inRoom) {
      await container.read(roomControllerProvider.notifier).openRoom('listen');
      rooms.last.emitHello();
    }
    await tester.pumpAndSettle();
  }

  Future<void> signedIn(Account account) async {
    credentials.memberToken = 'account-token';
    api.account = account;
  }

  void withGithub() {
    api.site = const SiteCapabilities(
      registrationOpen: true,
      githubLogin: true,
    );
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AlistenTextField, label),
    matching: find.byType(EditableText),
  );

  Finder rowOf(String title) => find
      .ancestor(of: find.text(title), matching: find.byType(Pressable))
      .first;

  // 忙碌指示一直在动，不能 pumpAndSettle；多推进几帧，让真被关掉的面板播完
  // 收起动画并移出树。
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // 邀请确认之类的页面推到根导航器上，盖住打开着的面板。
  Future<NavigatorState> coverWithPage(WidgetTester tester, Type sheet) async {
    final navigator = Navigator.of(tester.element(find.byType(sheet)));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('邀请确认')),
      ),
    );
    await pumpFrames(tester);
    return navigator;
  }

  testWidgets('a guest sees login and register', (tester) async {
    await pumpActions(tester);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('注册账号'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
  });

  testWidgets('a closed registration hides the register row', (tester) async {
    api.site = const SiteCapabilities(
      registrationOpen: false,
      githubLogin: false,
    );
    await pumpActions(tester);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('注册账号'), findsNothing);
  });

  testWidgets('an account sees change password and logout', (tester) async {
    await signedIn(const Account(username: 'mao', github: false));
    await pumpActions(tester);
    expect(find.text('在新设备上登录'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('绑定 GitHub'), findsNothing);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('a GitHub-only account sets a username and password instead '
      'of changing one, and cannot unbind yet', (tester) async {
    final semantics = tester.ensureSemantics();
    withGithub();
    await signedIn(const Account(github: true));
    await pumpActions(tester);

    expect(find.text('在新设备上登录'), findsOneWidget);
    expect(find.text('设置用户名和密码'), findsOneWidget);
    expect(find.text('修改密码'), findsNothing);
    expect(find.text('解绑 GitHub'), findsOneWidget);
    expect(find.text('已绑定。先设置用户名和密码，才能解绑。'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('解绑 GitHub')),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
    expect(find.text('退出登录'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('logging out asks first and says what happens outside a room', (
    tester,
  ) async {
    await signedIn(const Account(username: 'mao', github: false));
    await pumpActions(tester);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(find.text('退出登录？'), findsOneWidget);
    expect(find.text('退出后这台设备会变成新的游客。'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ConfirmSheet),
        matching: find.text('退出登录'),
      ),
      findsOneWidget,
    );
    expect(api.logoutCalls, 0);
  });

  testWidgets('the guest rows are titles only, as on the web', (tester) async {
    await pumpActions(tester);
    expect(find.text('已有账号的话，登录即可。'), findsNothing);
    expect(find.text('注册后可以在其他设备上登录，昵称和头像会保留。'), findsNothing);
  });

  testWidgets('in a room the logout confirmation warns about the room', (
    tester,
  ) async {
    await signedIn(const Account(username: 'mao', github: false));
    await pumpActions(tester, inRoom: true);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(find.text('退出后会重新进入当前房间，正在播放的歌会中断。'), findsOneWidget);
    expect(find.text('退出后这台设备会变成新的游客。'), findsNothing);
  });

  testWidgets('confirming logs out once and says so', (tester) async {
    await signedIn(const Account(username: 'mao', github: false));
    await pumpActions(tester);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ConfirmSheet),
        matching: find.text('退出登录'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.logoutCalls, 1);
    expect(notices, [(ToastKind.success, '已退出登录')]);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    await signedIn(const Account(username: 'mao', github: false));
    await pumpActions(tester);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(api.logoutCalls, 0);
    expect(notices, isEmpty);
    expect(find.text('退出登录？'), findsNothing);
  });

  group('GitHub and pairing', () {
    Future<void> tryToDismiss(WidgetTester tester) async {
      await tester.tapAt(const Offset(8, 8));
      await pumpFrames(tester);
    }

    testWidgets('a guest of a site with GitHub still sees only login and '
        'register: the other ways to sign in are on the login page', (
      tester,
    ) async {
      withGithub();
      await pumpActions(tester);

      expect(
        find.descendant(
          of: find.byType(AccountActions),
          matching: find.byType(Pressable),
        ),
        findsNWidgets(2),
      );
      expect(
        tester.getTopLeft(find.text('登录')).dy,
        lessThan(tester.getTopLeft(find.text('注册账号')).dy),
      );
      expect(find.text('用 GitHub 登录'), findsNothing);
      expect(find.text('输入配对码'), findsNothing);
    });

    testWidgets('an account with a username binds GitHub, or unbinds it once '
        'bound', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: false));
      await pumpActions(tester);

      final tops = [
        for (final title in ['在新设备上登录', '修改密码', '绑定 GitHub', '退出登录'])
          tester.getTopLeft(find.text(title)).dy,
      ];
      expect(tops, [...tops]..sort());
      expect(find.text('绑定之后，可以用 GitHub 登录这个账号。'), findsOneWidget);
    });

    testWidgets('a bound account with a username can unbind', (tester) async {
      final semantics = tester.ensureSemantics();
      withGithub();
      await signedIn(const Account(username: 'mao', github: true));
      await pumpActions(tester);

      expect(find.text('已绑定，可以用 GitHub 登录这个账号。'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('解绑 GitHub')),
        isSemantics(hasEnabledState: true, isEnabled: true),
      );
      semantics.dispose();
    });

    testWidgets('while GitHub runs the other GitHub entries are disabled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      withGithub();
      authorizer.gate = Completer<void>();
      await signedIn(const Account(username: 'mao', github: false));
      api.githubExchange = const GithubExchange(
        member: FakeAlistenApi.member,
        account: Account(username: 'mao', github: false),
      );
      await pumpActions(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountActions)),
      );

      final verifying = container
          .read(githubControllerProvider.notifier)
          .verify();
      await tester.pump();
      expect(
        tester.getSemantics(find.text('绑定 GitHub')),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );

      authorizer.gate!.complete();
      await verifying;
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('绑定 GitHub')),
        isSemantics(hasEnabledState: true, isEnabled: true),
      );
      semantics.dispose();
    });

    testWidgets('while GitHub runs a bound account cannot unbind', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      withGithub();
      authorizer.gate = Completer<void>();
      await signedIn(const Account(username: 'mao', github: true));
      api.githubExchange = const GithubExchange(
        member: FakeAlistenApi.member,
        account: Account(username: 'mao', github: true),
      );
      await pumpActions(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountActions)),
      );

      final verifying = container
          .read(githubControllerProvider.notifier)
          .verify();
      await tester.pump();
      expect(
        tester.getSemantics(find.text('解绑 GitHub')),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );

      authorizer.gate!.complete();
      await verifying;
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('解绑 GitHub')),
        isSemantics(hasEnabledState: true, isEnabled: true),
      );
      semantics.dispose();
    });

    testWidgets('setting a username and password confirms with GitHub first, '
        'then asks for them', (tester) async {
      await signedIn(const Account(github: true));
      api.registeredAccount = const Account(username: 'mao', github: true);
      await pumpActions(tester);

      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();

      expect(api.githubStarts.single.intent, GithubIntent.verify);
      expect(find.byType(SetCredentialsSheet), findsOneWidget);
      expect(find.byType(SheetPanel), findsOneWidget);
      expect(find.text('设置之后，其他设备需要重新登录。'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountActions)),
      );
      final session = container.read(identityControllerProvider).session;
      await tester.enterText(field('用户名'), 'mao');
      await tester.enterText(field('密码'), 'password1');
      await tester.enterText(field('再次输入密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(notices, [(ToastKind.success, '已设置用户名和密码，其他设备已退出登录')]);
      expect(container.read(identityControllerProvider).session, session);
      expect(find.text('修改密码'), findsOneWidget);
    });

    testWidgets('a GitHub check that ends after the page is gone opens no '
        'sheet', (tester) async {
      await signedIn(const Account(github: true));
      authorizer.gate = Completer<void>();
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pump();

      present.value = false;
      await tester.pump();
      authorizer.gate!.complete();
      await tester.pumpAndSettle();

      expect(api.githubFinishes, hasLength(1));
      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(notices, isEmpty);
    });

    testWidgets('credentials set after their sheet was dismissed are still '
        'reported', (tester) async {
      await signedIn(const Account(github: true));
      api.registeredAccount = const Account(username: 'mao', github: true);
      api.registerGate = Completer<void>();
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();
      await tester.enterText(field('用户名'), 'mao');
      await tester.enterText(field('密码'), 'password1');
      await tester.enterText(field('再次输入密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '保存'));
      await tester.pump();

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(SetCredentialsSheet), findsNothing);
      api.registerGate!.complete();
      await tester.pumpAndSettle();

      expect(api.registerCalls, 1);
      expect(notices, [(ToastKind.success, '已设置用户名和密码，其他设备已退出登录')]);
    });

    testWidgets('a refusal that comes back after the sheet is gone is still '
        'told', (tester) async {
      await signedIn(const Account(github: true));
      api
        ..registerGate = Completer<void>()
        ..registerError = const ApiException(
          code: 'CONFLICT',
          message: '用户名已被占用',
          status: 409,
        );
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();
      await tester.enterText(field('用户名'), 'mao');
      await tester.enterText(field('密码'), 'password1');
      await tester.enterText(field('再次输入密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '保存'));
      await tester.pump();

      await tryToDismiss(tester);
      expect(find.byType(SetCredentialsSheet), findsNothing);
      api.registerGate!.complete();
      await tester.pumpAndSettle();

      expect(api.registerCalls, 1);
      expect(notices, contains((ToastKind.warning, '用户名已被占用')));
    });

    testWidgets('a refusal that arrives while the sheet is closing is still '
        'told', (tester) async {
      await signedIn(const Account(github: true));
      api
        ..registerGate = Completer<void>()
        ..registerError = const ApiException(
          code: 'CONFLICT',
          message: '用户名已被占用',
          status: 409,
        );
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();
      await tester.enterText(field('用户名'), 'mao');
      await tester.enterText(field('密码'), 'password1');
      await tester.enterText(field('再次输入密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '保存'));
      await tester.pump();

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      expect(find.byType(SetCredentialsSheet), findsOneWidget);
      api.registerGate!.complete();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(notices, contains((ToastKind.warning, '用户名已被占用')));
    });

    testWidgets('confirming with GitHub keeps its row busy', (tester) async {
      await signedIn(const Account(github: true));
      authorizer.gate = Completer<void>();
      await pumpActions(tester);

      await tester.tap(find.text('设置用户名和密码'));
      await tester.pump();
      expect(
        find.descendant(
          of: rowOf('设置用户名和密码'),
          matching: find.byType(BusyIndicator),
        ),
        findsOneWidget,
      );

      authorizer.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SetCredentialsSheet), findsOneWidget);
    });

    testWidgets('a GitHub check the server turns down says why and opens no '
        'sheet', (tester) async {
      await signedIn(const Account(github: true));
      api.startGithubError = const ApiException(
        code: 'NOT_FOUND',
        message: '站点没有开启 GitHub 登录',
        status: 404,
      );
      await pumpActions(tester);

      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();

      expect(authorizer.opened, isEmpty);
      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(notices, [(ToastKind.failure, '站点没有开启 GitHub 登录')]);
    });

    testWidgets('a new session closes the set-credentials sheet before it can '
        'register anyone', (tester) async {
      await signedIn(const Account(github: true));
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();
      expect(find.byType(SetCredentialsSheet), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountActions)),
      );

      await container.read(accountControllerProvider).logout();
      await tester.pumpAndSettle();

      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(api.registerCalls, 0);
    });

    testWidgets('a server switch closes the set-credentials sheet even under '
        'another page', (tester) async {
      await signedIn(const Account(github: true));
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountActions)),
      );
      final navigator = Navigator.of(
        tester.element(find.byType(SetCredentialsSheet)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('邀请确认')),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(identityControllerProvider.notifier)
          .resetForServerChange();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('邀请确认'), findsNothing);
      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(api.registerCalls, 0);
    });

    testWidgets('credentials set under another page close their sheet', (
      tester,
    ) async {
      await signedIn(const Account(github: true));
      api.registeredAccount = const Account(username: 'mao', github: true);
      api.registerGate = Completer<void>();
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();
      await tester.enterText(field('用户名'), 'mao');
      await tester.enterText(field('密码'), 'password1');
      await tester.enterText(field('再次输入密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '保存'));
      await tester.pump();
      final navigator = await coverWithPage(tester, SetCredentialsSheet);

      api.registerGate!.complete();
      await pumpFrames(tester);
      navigator.pop();
      await pumpFrames(tester);

      expect(find.text('邀请确认'), findsNothing);
      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(notices, [(ToastKind.success, '已设置用户名和密码，其他设备已退出登录')]);
    });

    testWidgets('a GitHub check older than 10 minutes closes the sheet and '
        'asks to start again', (tester) async {
      await signedIn(const Account(github: true));
      api.registerError = const ApiException(
        code: 'FORBIDDEN',
        message: '服务端',
        status: 403,
      );
      await pumpActions(tester);
      await tester.tap(find.text('设置用户名和密码'));
      await tester.pumpAndSettle();

      await tester.enterText(field('用户名'), 'mao');
      await tester.enterText(field('密码'), 'password1');
      await tester.enterText(field('再次输入密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.byType(SetCredentialsSheet), findsNothing);
      expect(notices, [(ToastKind.warning, githubVerifyExpiredText)]);
    });

    testWidgets('a wrong current password stays in the bind sheet', (
      tester,
    ) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: false));
      api.startGithubError = const ApiException(
        code: 'INVALID_CREDENTIALS',
        message: '服务端',
        status: 401,
      );
      await pumpActions(tester);
      await tester.tap(find.text('绑定 GitHub'));
      await tester.pumpAndSettle();

      expect(find.byType(SheetPanel), findsOneWidget);
      await tester.enterText(field('当前密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '去 GitHub 授权'));
      await tester.pumpAndSettle();

      expect(find.byType(GithubPasswordSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InlineMessage),
          matching: find.text('当前密码不对'),
        ),
        findsOneWidget,
      );
      expect(authorizer.opened, isEmpty);
      expect(notices, isEmpty);
    });

    testWidgets('a bind GitHub refuses at the exchange closes the sheet and '
        'tells', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: false));
      api.finishGithubError = const ApiException(
        code: 'INVALID_CREDENTIALS',
        message: '服务端',
        status: 401,
      );
      await pumpActions(tester);
      await tester.tap(find.text('绑定 GitHub'));
      await tester.pumpAndSettle();

      await tester.enterText(field('当前密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '去 GitHub 授权'));
      await tester.pumpAndSettle();

      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(notices, [(ToastKind.failure, '服务端')]);
    });

    testWidgets('the bind sheet cannot be closed while GitHub authorizes, '
        'then closes and tells', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: false));
      api.githubExchange = const GithubExchange(
        member: FakeAlistenApi.member,
        account: Account(username: 'mao', github: true),
      );
      authorizer.gate = Completer<void>();
      await pumpActions(tester);
      await tester.tap(find.text('绑定 GitHub'));
      await tester.pumpAndSettle();
      await tester.enterText(field('当前密码'), 'password1');

      await tester.tap(find.widgetWithText(PillButton, '去 GitHub 授权'));
      await tester.pump();
      await tryToDismiss(tester);
      expect(find.byType(GithubPasswordSheet), findsOneWidget);

      authorizer.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(notices, [(ToastKind.success, '已绑定 GitHub')]);
    });

    testWidgets('unbinding asks for the current password and says it is '
        'done', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: true));
      await pumpActions(tester);
      await tester.tap(find.text('解绑 GitHub'));
      await tester.pumpAndSettle();

      await tester.enterText(field('当前密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '解绑'));
      await tester.pumpAndSettle();

      expect(api.unbindPassword, 'password1');
      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(notices, [(ToastKind.success, '已解绑 GitHub')]);
      expect(find.text('绑定 GitHub'), findsOneWidget);
    });

    testWidgets('the unbind sheet stays busy and cannot be closed until the '
        'server answers', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: true));
      api.unbindGate = Completer<void>();
      await pumpActions(tester);
      await tester.tap(find.text('解绑 GitHub'));
      await tester.pumpAndSettle();
      await tester.enterText(field('当前密码'), 'password1');

      await tester.tap(find.widgetWithText(PillButton, '解绑'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tryToDismiss(tester);
      expect(find.byType(GithubPasswordSheet), findsOneWidget);
      expect(api.unbindCalls, 1);

      api.unbindGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(api.unbindCalls, 1);
      expect(notices, [(ToastKind.success, '已解绑 GitHub')]);
    });

    testWidgets('a bind that ends under another page still closes its sheet', (
      tester,
    ) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: false));
      api.githubExchange = const GithubExchange(
        member: FakeAlistenApi.member,
        account: Account(username: 'mao', github: true),
      );
      authorizer.gate = Completer<void>();
      await pumpActions(tester);
      await tester.tap(find.text('绑定 GitHub'));
      await tester.pumpAndSettle();
      await tester.enterText(field('当前密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '去 GitHub 授权'));
      await tester.pump();
      final navigator = await coverWithPage(tester, GithubPasswordSheet);

      authorizer.gate!.complete();
      await pumpFrames(tester);
      navigator.pop();
      await pumpFrames(tester);

      expect(find.text('邀请确认'), findsNothing);
      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(notices, [(ToastKind.success, '已绑定 GitHub')]);
    });

    testWidgets('an unbind that ends under another page still closes its '
        'sheet', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: true));
      api.unbindGate = Completer<void>();
      await pumpActions(tester);
      await tester.tap(find.text('解绑 GitHub'));
      await tester.pumpAndSettle();
      await tester.enterText(field('当前密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '解绑'));
      await tester.pump();
      final navigator = await coverWithPage(tester, GithubPasswordSheet);

      api.unbindGate!.complete();
      await pumpFrames(tester);
      navigator.pop();
      await pumpFrames(tester);

      expect(find.text('邀请确认'), findsNothing);
      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(notices, [(ToastKind.success, '已解绑 GitHub')]);
    });

    testWidgets('a server switch closes the GitHub password sheet even under '
        'another page', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: true));
      await pumpActions(tester);
      await tester.tap(find.text('解绑 GitHub'));
      await tester.pumpAndSettle();
      await tester.enterText(field('当前密码'), 'password1');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountActions)),
      );
      final navigator = await coverWithPage(tester, GithubPasswordSheet);

      await container
          .read(identityControllerProvider.notifier)
          .resetForServerChange();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('邀请确认'), findsNothing);
      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(api.unbindCalls, 0);
    });

    testWidgets('an unbind the server turns down stays in the sheet', (
      tester,
    ) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: true));
      api.unbindError = const ApiException(
        code: 'INVALID_CREDENTIALS',
        message: '服务端',
        status: 401,
      );
      await pumpActions(tester);
      await tester.tap(find.text('解绑 GitHub'));
      await tester.pumpAndSettle();

      await tester.enterText(field('当前密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '解绑'));
      await tester.pumpAndSettle();

      expect(find.byType(GithubPasswordSheet), findsOneWidget);
      expect(find.text('当前密码不对'), findsOneWidget);
    });

    testWidgets('an unbind with no answer closes the sheet and says it was '
        'resynced', (tester) async {
      withGithub();
      await signedIn(const Account(username: 'mao', github: true));
      api.unbindError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络',
        status: null,
      );
      await pumpActions(tester);
      await tester.tap(find.text('解绑 GitHub'));
      await tester.pumpAndSettle();

      await tester.enterText(field('当前密码'), 'password1');
      await tester.tap(find.widgetWithText(PillButton, '解绑'));
      await tester.pumpAndSettle();

      expect(find.byType(GithubPasswordSheet), findsNothing);
      expect(notices, [(ToastKind.warning, githubUnknownText)]);
    });

    testWidgets('the pairing panel opens from its row', (tester) async {
      await signedIn(const Account(username: 'mao', github: false));
      await pumpActions(tester);

      await tester.tap(find.text('在新设备上登录'));
      await tester.pumpAndSettle();

      expect(find.text('ABCD-2345'), findsOneWidget);
      expect(api.createPairingCodeCalls, 1);
    });
  });

  group('noticeGithubResult', () {
    List<(ToastKind, String)> told(MutationResult<GithubOutcome> result) {
      final told = <(ToastKind, String)>[];
      noticeGithubResult((kind, text) => told.add((kind, text)), result);
      return told;
    }

    test('says how a finished flow ended, except a check', () {
      expect(told(const MutationSucceeded(GithubOutcome.signedIn)), [
        (ToastKind.success, '已登录'),
      ]);
      expect(told(const MutationSucceeded(GithubOutcome.registered)), [
        (ToastKind.success, '已用 GitHub 注册'),
      ]);
      expect(told(const MutationSucceeded(GithubOutcome.bound)), [
        (ToastKind.success, '已绑定 GitHub'),
      ]);
      expect(told(const MutationSucceeded(GithubOutcome.verified)), isEmpty);
    });

    test('a flow ended by a server switch or a refusal is a failure', () {
      expect(told(const MutationNotSent(serverChangedNotice)), [
        (ToastKind.failure, serverChangedNotice),
      ]);
      expect(told(const MutationNotSent(doneOnOldServerText)), [
        (ToastKind.failure, doneOnOldServerText),
      ]);
      expect(told(const MutationFailed('CONFLICT', '服务端')), [
        (ToastKind.failure, '服务端'),
      ]);
    });

    test('an unknown result says it was resynced', () {
      expect(told(const MutationUnknown()), [
        (ToastKind.warning, githubUnknownText),
      ]);
    });
  });

  group('change password', () {
    Future<void> openSheet(WidgetTester tester) async {
      await signedIn(const Account(username: 'mao', github: false));
      await pumpActions(tester);
      await tester.tap(find.text('修改密码'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(
      WidgetTester tester, {
      String again = 'new-password',
    }) async {
      await tester.enterText(field('当前密码'), 'old-password');
      await tester.enterText(field('新密码'), 'new-password');
      await tester.enterText(field('再次输入新密码'), again);
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(PillButton, '修改密码'));
      await tester.pumpAndSettle();
    }

    testWidgets('the sheet is a single panel', (tester) async {
      await openSheet(tester);
      expect(find.byType(SheetPanel), findsOneWidget);
    });

    testWidgets('success reports and closes the sheet', (tester) async {
      await openSheet(tester);
      await fill(tester);
      await submit(tester);

      expect(api.changePasswordCalls, 1);
      expect(notices, [(ToastKind.success, '已修改密码，其他设备已退出登录')]);
      expect(find.byType(ChangePasswordSheet), findsNothing);
    });

    testWidgets('a wrong current password stays in the sheet', (tester) async {
      api.changePasswordError = const ApiException(
        code: 'INVALID_CREDENTIALS',
        message: '服务端',
        status: 401,
      );
      await openSheet(tester);
      await fill(tester);
      await submit(tester);

      expect(
        find.descendant(
          of: find.byType(InlineMessage),
          matching: find.text('当前密码不对'),
        ),
        findsOneWidget,
      );
      expect(find.byType(ChangePasswordSheet), findsOneWidget);
      expect(notices, isEmpty);
    });

    testWidgets('the toggle shows every password', (tester) async {
      await openSheet(tester);
      bool obscured(String label) =>
          tester.widget<EditableText>(field(label)).obscureText;
      const labels = ['当前密码', '新密码', '再次输入新密码'];

      expect(labels.map(obscured), everyElement(isTrue));
      await tester.tap(find.byType(AlistenToggle));
      await tester.pumpAndSettle();
      expect(labels.map(obscured), everyElement(isFalse));
    });

    testWidgets('a new password typed differently the second time is not '
        'sent', (tester) async {
      await openSheet(tester);
      await fill(tester, again: 'new-passw0rd');
      await submit(tester);

      expect(
        find.descendant(
          of: find.byType(InlineMessage),
          matching: find.text('两次输入的密码不一样。'),
        ),
        findsOneWidget,
      );
      expect(api.changePasswordCalls, 0);
      expect(find.byType(ChangePasswordSheet), findsOneWidget);
    });

    testWidgets('submitting twice while busy sends one change', (tester) async {
      final gate = Completer<void>();
      api.changePasswordGate = gate;
      await openSheet(tester);
      await fill(tester);

      await tester.tap(find.widgetWithText(PillButton, '修改密码'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(api.changePasswordCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();
      expect(api.changePasswordCalls, 1);
      expect(notices, [(ToastKind.success, '已修改密码，其他设备已退出登录')]);
    });

    testWidgets('a change that completes after the sheet was dismissed is '
        'still reported', (tester) async {
      final gate = Completer<void>();
      api.changePasswordGate = gate;
      await openSheet(tester);
      await fill(tester);
      await tester.tap(find.widgetWithText(PillButton, '修改密码'));
      await tester.pump();

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordSheet), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(api.changePasswordCalls, 1);
      expect(notices, [(ToastKind.success, '已修改密码，其他设备已退出登录')]);
    });

    testWidgets('a change that succeeds under another page closes the sheet, '
        'not the page', (tester) async {
      final gate = Completer<void>();
      api.changePasswordGate = gate;
      await openSheet(tester);
      await fill(tester);
      await tester.tap(find.widgetWithText(PillButton, '修改密码'));
      await tester.pump();
      await coverWithPage(tester, ChangePasswordSheet);

      gate.complete();
      await pumpFrames(tester);

      expect(find.text('邀请确认'), findsOneWidget);
      expect(
        find.byType(ChangePasswordSheet, skipOffstage: false),
        findsNothing,
      );
      expect(notices, [(ToastKind.success, '已修改密码，其他设备已退出登录')]);
    });

    testWidgets('a server switch closes the sheet even under another page', (
      tester,
    ) async {
      await openSheet(tester);
      await fill(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AccountActions)),
      );
      final navigator = await coverWithPage(tester, ChangePasswordSheet);

      await container
          .read(identityControllerProvider.notifier)
          .resetForServerChange();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('邀请确认'), findsNothing);
      expect(find.byType(ChangePasswordSheet), findsNothing);
      expect(api.changePasswordCalls, 0);
    });
  });
}
