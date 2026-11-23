import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/registration_group.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

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

  AlistenToggle toggle(WidgetTester tester) =>
      tester.widget<AlistenToggle>(find.byType(AlistenToggle));

  testWidgets('open registration shows the switch on, and the switch closes '
      'it', (tester) async {
    await open(tester);

    expect(toggle(tester).value, isTrue);

    await tester.tap(find.bySemanticsLabel('开放注册'));
    await tester.pumpAndSettle();

    expect(api.registrationCalls, [false]);
    expect(toggle(tester).value, isFalse);
    expect(notices, isEmpty);
  });

  testWidgets('closed registration shows the switch off, and the switch opens '
      'it', (tester) async {
    api.registrationOpen = false;
    await open(tester);

    expect(toggle(tester).value, isFalse);

    await tester.tap(find.bySemanticsLabel('开放注册'));
    await tester.pumpAndSettle();

    expect(api.registrationCalls, [true]);
    expect(toggle(tester).value, isTrue);
    expect(notices, isEmpty);
  });

  testWidgets('the switch sends the change at once and cannot be flipped '
      'again until the server answers', (tester) async {
    api.registrationOpen = true;
    final gate = api.setRegistrationGate = Completer<void>();
    await open(tester);
    await tester.tap(find.bySemanticsLabel('开放注册'));
    await tester.pump();
    expect(api.registrationCalls, [false]);
    expect(toggle(tester).value, isFalse);
    expect(toggle(tester).onChanged, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(toggle(tester).onChanged, isNotNull);
  });

  testWidgets('a refused change flips back and says why', (tester) async {
    api
      ..registrationOpen = true
      ..setRegistrationError = const ApiException(
        code: 'INTERNAL_X',
        message: '服务端拒绝了',
        status: 400,
      );
    await open(tester);
    await tester.tap(find.bySemanticsLabel('开放注册'));
    await tester.pumpAndSettle();
    expect(toggle(tester).value, isTrue);
    expect(find.text('服务端拒绝了'), findsOneWidget);
  });

  testWidgets('a state that cannot be read offers a retry', (tester) async {
    api.getRegistrationError = Exception('down');
    await open(tester);

    expect(find.text('暂时无法获取注册状态。'), findsOneWidget);
    expect(find.byType(AlistenToggle), findsNothing);

    api.getRegistrationError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(toggle(tester).value, isTrue);
  });

  testWidgets('a switch without an answer says the result is unknown', (
    tester,
  ) async {
    await open(tester);
    api.setRegistrationError = Exception('lost');

    await tester.tap(find.bySemanticsLabel('开放注册'));
    await tester.pumpAndSettle();

    expect(notices, [(ToastKind.warning, '没能确认是否修改，已重新读取')]);
  });
}
