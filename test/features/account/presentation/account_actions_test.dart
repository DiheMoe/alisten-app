import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/account/presentation/change_password_sheet.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';

void main() {
  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory rooms;
  late List<(ToastKind, String)> notices;

  setUp(() {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
    rooms = FakeRoomTransportFactory();
    notices = [];
  });

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
                return AccountActions(
                  onOpenLogin: () {},
                  onOpenRegister: () {},
                  onNotice: (kind, text) => notices.add((kind, text)),
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
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('a GitHub-only account can only log out', (tester) async {
    await signedIn(const Account(github: true));
    await pumpActions(tester);
    expect(find.text('修改密码'), findsNothing);
    expect(find.text('退出登录'), findsOneWidget);
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

  group('change password', () {
    Future<void> openSheet(WidgetTester tester) async {
      await signedIn(const Account(username: 'mao', github: false));
      await pumpActions(tester);
      await tester.tap(find.text('修改密码'));
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.descendant(
      of: find.widgetWithText(AlistenTextField, label),
      matching: find.byType(EditableText),
    );

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
  });
}
