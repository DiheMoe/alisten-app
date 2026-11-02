import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/idle_frames.dart';
import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _unauthorized = ApiException(
  code: 'UNAUTHORIZED',
  message: 'token invalid',
  status: 401,
);

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(AlistenTextField, label),
  matching: find.byType(EditableText),
);

PillButton _button(WidgetTester tester, String label) =>
    tester.widget<PillButton>(find.widgetWithText(PillButton, label));

void main() {
  late FakeAdminApi api;
  late List<(ToastKind, String)> notices;
  late int exits;
  late DateTime now;
  late Duration elapsed;
  late ProviderContainer container;

  setUp(() {
    api = FakeAdminApi();
    notices = [];
    exits = 0;
    now = DateTime.utc(2026, 11, 2, 20);
    elapsed = Duration.zero;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        ...await switchingOverrides(
          store: FakeServerStore(profiles: [serverB]),
          credentials: FakeCredentialStores(),
        ),
        adminApiProvider.overrideWithValue(api),
        adminNowProvider.overrideWithValue(() => now),
        adminElapsedProvider.overrideWithValue(() => elapsed),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: AdminScreen(
            onNotice: (kind, text) => notices.add((kind, text)),
            onExit: () => exits++,
            onOpenRoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> submit(WidgetTester tester, [String token = 't-1']) async {
    await tester.enterText(_field('管理 token'), token);
    await tester.tap(find.text('进入后台'));
    await tester.pumpAndSettle();
  }

  Future<void> awayFor(WidgetTester tester, Duration duration) async {
    final session = container.read(adminSessionProvider.notifier)
      ..handleLifecycle(AppLifecycleState.paused);
    now = now.add(duration);
    elapsed += duration;
    session.handleLifecycle(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('a token typed and left for 5 minutes is gone when the app '
      'comes back, its undo history with it', (tester) async {
    await open(tester);
    await tester.enterText(_field('管理 token'), 't-secret');
    final typed = tester.widget<EditableText>(_field('管理 token')).controller;

    await awayFor(tester, const Duration(minutes: 4, seconds: 59));
    expect(
      tester.widget<EditableText>(_field('管理 token')).controller,
      same(typed),
    );
    expect(typed.text, 't-secret');

    await awayFor(tester, const Duration(minutes: 5));
    final field = tester.widget<EditableText>(_field('管理 token'));
    expect(field.controller, isNot(same(typed)));
    expect(field.controller.text, isEmpty);
    expect(field.focusNode.hasFocus, isFalse);
  });

  testWidgets('a token being verified when the app goes away for more than '
      '5 minutes is let go on return', (tester) async {
    await open(tester);
    api.listRoomsGate = Completer();
    await tester.enterText(_field('管理 token'), 't-secret');
    await tester.tap(find.text('进入后台'));
    await tester.pump();
    expect(_button(tester, '进入后台').busy, isTrue);

    await awayFor(tester, const Duration(minutes: 6));
    api.listRoomsGate!.complete();
    await tester.pumpAndSettle();

    expect(container.read(adminSessionProvider).active, isFalse);
    expect(find.text('退出后台'), findsNothing);
    expect(_button(tester, '进入后台').busy, isFalse);
    expect(
      tester.widget<EditableText>(_field('管理 token')).controller.text,
      isEmpty,
    );
  });

  testWidgets('the token page names the server and keeps the token hidden, '
      'out of autofill, out of what the keyboard learns and '
      'unfocused', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(find.text('站点管理'), findsOneWidget);
    expect(find.text('livehouse.dihe.moe'), findsOneWidget);
    expect(find.text('管理 token 只保存在内存中，退出后台后需要重新输入。'), findsOneWidget);
    final field = tester.widget<EditableText>(_field('管理 token'));
    expect(field.obscureText, isTrue);
    expect(field.autofillHints, isNull);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.focusNode.hasFocus, isFalse);
    expect(find.bySemanticsLabel('管理 token'), findsOneWidget);
    expect(_button(tester, '进入后台').onPressed, isNotNull);
    for (final text in ['房主', '管理员']) {
      expect(find.textContaining(text), findsNothing);
    }
    semantics.dispose();
  });

  testWidgets('a token taken opens the site admin', (tester) async {
    await open(tester);

    await submit(tester);

    expect(find.text('退出后台'), findsOneWidget);
    expect(find.text('站点'), findsOneWidget);
    expect(find.text('进入后台'), findsNothing);
    expect(api.tokens.first, 't-1');
  });

  testWidgets('neither page draws anything while left alone', (tester) async {
    await open(tester);
    expect(await idleFrames(tester), 0, reason: 'token page');

    await submit(tester);
    expect(await idleFrames(tester), 0, reason: 'site admin');
  });

  testWidgets('a token refused says why and stays on the token page', (
    tester,
  ) async {
    await open(tester);

    api.listRoomsError = _unauthorized;
    await submit(tester);
    expect(find.text('管理 token 无效'), findsOneWidget);
    expect(find.text('进入后台'), findsOneWidget);

    api.listRoomsError = const ApiException(
      code: 'FORBIDDEN',
      message: '后台未启用',
      status: 403,
    );
    await submit(tester);
    expect(find.text('这个服务器没有启用后台'), findsOneWidget);
    expect(find.text('管理 token 无效'), findsNothing);
  });

  testWidgets('three tokens refused in a row make the button wait, counting '
      'down', (tester) async {
    await open(tester);
    api.listRoomsError = _unauthorized;

    for (var attempt = 0; attempt < 3; attempt++) {
      await submit(tester);
    }

    expect(find.text('请等待 30 秒'), findsOneWidget);
    expect(_button(tester, '请等待 30 秒').onPressed, isNull);
    expect(find.text('管理 token 无效'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('请等待 29 秒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(find.text('进入后台'), findsOneWidget);
    expect(_button(tester, '进入后台').onPressed, isNotNull);
    expect(api.listRoomsCalls, 3);
  });

  testWidgets('leaving the site admin is left to the caller', (tester) async {
    await open(tester);
    await submit(tester);

    await tester.tap(find.text('退出后台'));
    await tester.pump();

    expect(exits, 1);
  });

  testWidgets('a sheet open when the session ends closes, and the token page '
      'says why', (tester) async {
    await open(tester);
    await submit(tester);
    var closed = false;
    unawaited(
      showSheetPanel<void>(
        tester.element(find.text('站点')),
        builder: (context) => const Text('面板内容'),
      ).then((_) => closed = true),
    );
    await tester.pumpAndSettle();
    expect(find.text('面板内容'), findsOneWidget);

    container
        .read(adminSessionProvider.notifier)
        .end(notice: adminTokenExpiredText);
    await tester.pumpAndSettle();

    expect(find.text('面板内容'), findsNothing);
    expect(closed, isTrue);
    expect(find.text('进入后台'), findsOneWidget);
    expect(find.text(adminTokenExpiredText), findsOneWidget);

    api.listRoomsError = _unauthorized;
    await submit(tester);
    expect(find.text(adminTokenExpiredText), findsNothing);
    expect(find.text('管理 token 无效'), findsOneWidget);
  });

  testWidgets('a sheet under another closes with the one above it when the '
      'session ends', (tester) async {
    await open(tester);
    await submit(tester);
    final context = tester.element(find.text('站点'));
    unawaited(
      showSheetPanel<void>(context, builder: (_) => const Text('下面的面板')),
    );
    await tester.pumpAndSettle();
    unawaited(
      showSheetPanel<void>(context, builder: (_) => const Text('上面的面板')),
    );
    await tester.pumpAndSettle();

    container.read(adminSessionProvider.notifier).end();
    await tester.pumpAndSettle();

    expect(find.text('下面的面板'), findsNothing);
    expect(find.text('上面的面板'), findsNothing);
    expect(find.text('进入后台'), findsOneWidget);
  });

  testWidgets('a sheet that cannot be dismissed closes too when the session '
      'ends', (tester) async {
    await open(tester);
    await submit(tester);
    final context = tester.element(find.text('站点'));
    unawaited(
      showSheetPanel<void>(context, builder: (_) => const Text('后台面板')),
    );
    await tester.pumpAndSettle();
    var closed = false;
    unawaited(
      showSheetPanel<void>(
        context,
        dismissible: false,
        builder: (_) => const Text('普通面板'),
      ).then((_) => closed = true),
    );
    await tester.pumpAndSettle();

    container
        .read(adminSessionProvider.notifier)
        .end(notice: adminTokenExpiredText);
    await tester.pumpAndSettle();

    expect(find.text('普通面板'), findsNothing);
    expect(find.text('后台面板'), findsNothing);
    expect(closed, isTrue);
    expect(find.text('进入后台'), findsOneWidget);
    expect(find.text(adminTokenExpiredText), findsOneWidget);
  });

  testWidgets('the brand name is shown, and a new one saved here and in the '
      'server list', (tester) async {
    await open(tester);
    await submit(tester);

    expect(
      tester.widget<EditableText>(_field('品牌名')).controller.text,
      'Alisten',
    );

    await tester.enterText(_field('品牌名'), ' 周末听歌会 ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.updatedBrandName, '周末听歌会');
    expect(notices, [(ToastKind.success, '品牌名已保存')]);
    expect(container.read(currentServerProvider).brandName, '周末听歌会');
    expect(tester.widget<EditableText>(_field('品牌名')).controller.text, '周末听歌会');
  });

  testWidgets('a brand name against the rule is explained and not sent', (
    tester,
  ) async {
    await open(tester);
    await submit(tester);

    await tester.enterText(_field('品牌名'), '一二三四五六七八九十一二三四五六七八九十一');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text(brandNameRuleText), findsOneWidget);
    expect(api.updatedBrandName, isNull);
    expect(notices, isEmpty);
  });

  testWidgets('a save refused for an expired token leads back to the token '
      'page', (tester) async {
    await open(tester);
    await submit(tester);
    api.updateBrandError = _unauthorized;

    await tester.enterText(_field('品牌名'), '周末听歌会');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('进入后台'), findsOneWidget);
    expect(find.text(adminTokenExpiredText), findsOneWidget);
    expect(notices, isEmpty);
  });

  testWidgets('a save that fails unexpectedly is reported as unknown and the '
      'button is free again', (tester) async {
    await open(tester);
    await submit(tester);
    api.updateBrandError = StateError('boom');

    await tester.enterText(_field('品牌名'), '周末听歌会');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(notices, [(ToastKind.warning, '结果未知，请确认品牌名后再决定是否重试。')]);
    expect(_button(tester, '保存').busy, isFalse);
    expect(_button(tester, '保存').onPressed, isNotNull);
  });
}
