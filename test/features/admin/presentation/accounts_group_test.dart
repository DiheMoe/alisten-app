import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/accounts_group.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _password = 'reset-secret-password';
const _once = '只显示这一次，请转告用户。这个账号在所有设备上都已退出登录。';

void main() {
  late FakeAdminApi api;
  late FakeSensitiveClipboard sensitive;
  late List<String> copied;
  late List<(ToastKind, String)> notices;

  setUp(() {
    api = FakeAdminApi()
      ..accounts['mao'] = const AdminAccountView(
        member: Member(id: 'm-1', name: '大猫', avatarHash: ''),
        username: 'mao',
      );
    sensitive = FakeSensitiveClipboard();
    copied = [];
    notices = [];
  });

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [
        adminApiProvider.overrideWithValue(api),
        sensitiveClipboardProvider.overrideWithValue(sensitive),
      ],
    );
    addTearDown(container.dispose);
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountsGroup(
                onNotice: (kind, text) => notices.add((kind, text)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> find_(WidgetTester tester, String username) async {
    await tester.enterText(find.byType(EditableText), username);
    await tester.tap(find.text('查找'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('an account found by its username can be reset', (tester) async {
    await open(tester);

    await find_(tester, 'mao');

    expect(find.text('@mao'), findsOneWidget);
    expect(find.text('大猫'), findsOneWidget);
    expect(find.text('重置密码'), findsOneWidget);
  });

  testWidgets('an unknown username says there is no such account', (
    tester,
  ) async {
    await open(tester);

    await find_(tester, 'nobody');

    expect(find.text('没有这个用户名的账号。'), findsOneWidget);
    expect(find.text('重置密码'), findsNothing);
  });

  testWidgets('the username is lowercased as it is typed', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(EditableText), 'MaO');

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'mao',
    );
  });

  testWidgets('the username is neither corrected nor suggested', (
    tester,
  ) async {
    await open(tester);

    final username = tester.widget<TextField>(find.byType(TextField));
    expect(username.autocorrect, isFalse);
    expect(username.enableSuggestions, isFalse);
  });

  testWidgets('the reset is confirmed first, the new password is shown once '
      'and copied only marked sensitive', (tester) async {
    await open(tester);
    await find_(tester, 'mao');

    await tap(tester, find.text('重置密码'));
    expect(find.text('重置 @mao 的密码？'), findsOneWidget);
    expect(find.text('会生成一个新密码，这个账号在所有设备上都会退出登录。'), findsOneWidget);
    expect(api.resetUsernames, isEmpty);

    await tap(tester, find.text('重置密码').last);
    expect(api.resetUsernames, ['mao']);
    expect(find.text(_password), findsOneWidget);
    expect(find.text(_once), findsOneWidget);

    await tap(tester, find.text('复制'));
    expect(sensitive.copied, [_password]);
    expect(copied, isEmpty);
    expect(notices, [(ToastKind.success, '新密码已复制')]);

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text(_password), findsNothing);
  });

  testWidgets('a copy that fails says so and never falls back to the normal '
      'clipboard', (tester) async {
    sensitive.error = StateError('clipboard unavailable');
    await open(tester);
    await find_(tester, 'mao');
    await tap(tester, find.text('重置密码'));
    await tap(tester, find.text('重置密码').last);

    await tap(tester, find.text('复制'));

    expect(notices, [(ToastKind.failure, '没能复制，请重试。')]);
    expect(sensitive.copied, isEmpty);
    expect(copied, isEmpty);
  });

  testWidgets('a reset the server refused says why', (tester) async {
    await open(tester);
    await find_(tester, 'mao');
    api.resetPasswordError = const ApiException(
      code: 'NOT_FOUND',
      message: '账号不存在',
      status: 404,
    );

    await tap(tester, find.text('重置密码'));
    await tap(tester, find.text('重置密码').last);

    expect(notices, [(ToastKind.failure, '账号不存在')]);
    expect(find.text(_password), findsNothing);
  });

  testWidgets('a reset without an answer asks to reset again', (tester) async {
    await open(tester);
    await find_(tester, 'mao');
    api.resetPasswordError = Exception('lost');

    await tap(tester, find.text('重置密码'));
    await tap(tester, find.text('重置密码').last);

    expect(notices, [(ToastKind.warning, '结果未知：密码可能已经重置，请再重置一次以拿到新密码。')]);
  });
}
