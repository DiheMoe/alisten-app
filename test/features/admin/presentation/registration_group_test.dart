import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/registration_group.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _openText = '现在任何人都可以注册账号。关闭后不能再注册新账号，已有账号照常登录，游客照常使用。';
const _closedText = '现在不能注册新账号。已有账号照常登录，游客照常使用。';

void main() {
  late FakeAdminApi api;
  late List<(ToastKind, String)> notices;

  setUp(() {
    api = FakeAdminApi();
    notices = [];
  });

  Future<void> open(WidgetTester tester) async {
    final container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: RegistrationGroup(
              onNotice: (kind, text) => notices.add((kind, text)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('open registration is explained and can be closed', (
    tester,
  ) async {
    await open(tester);

    expect(find.text(_openText), findsOneWidget);
    expect(find.text('开放注册'), findsNothing);

    await tester.tap(find.text('关闭注册'));
    await tester.pumpAndSettle();

    expect(api.registrationCalls, [false]);
    expect(find.text(_closedText), findsOneWidget);
    expect(find.text('开放注册'), findsOneWidget);
    expect(notices, [(ToastKind.success, '已关闭注册')]);
  });

  testWidgets('closed registration is explained and can be opened', (
    tester,
  ) async {
    api.registrationOpen = false;
    await open(tester);

    expect(find.text(_closedText), findsOneWidget);

    await tester.tap(find.text('开放注册'));
    await tester.pumpAndSettle();

    expect(api.registrationCalls, [true]);
    expect(find.text(_openText), findsOneWidget);
    expect(notices, [(ToastKind.success, '已开放注册')]);
  });

  testWidgets('a state that cannot be read offers a retry', (tester) async {
    api.getRegistrationError = Exception('down');
    await open(tester);

    expect(find.text('暂时无法获取注册状态。'), findsOneWidget);
    expect(find.text('关闭注册'), findsNothing);

    api.getRegistrationError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text(_openText), findsOneWidget);
  });

  testWidgets('a switch without an answer says the result is unknown', (
    tester,
  ) async {
    await open(tester);
    api.setRegistrationError = Exception('lost');

    await tester.tap(find.text('关闭注册'));
    await tester.pumpAndSettle();

    expect(notices, [(ToastKind.warning, '结果未知，请确认注册状态后再决定是否重试。')]);
  });
}
