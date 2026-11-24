import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/ephemeral_rooms_group.dart';
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
  late DateTime now;
  late Duration elapsed;
  late ProviderContainer container;

  setUp(() {
    api = FakeAdminApi();
    notices = [];
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
          home: Builder(
            builder: (context) => AdminScreen(
              onExit: () {},
              onOpenSection: (section) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => adminSectionScreen(
                    section,
                    onNotice: (kind, text) => notices.add((kind, text)),
                    onOpenRoom: (_) {},
                    onEnded: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> openSection(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
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

  testWidgets('a save refused for an expired token leads back to the token '
      'page', (tester) async {
    await open(tester);
    await submit(tester);
    await openSection(tester, '站点');
    api.updateBrandError = _unauthorized;

    await tester.enterText(_field('品牌名'), '周末听歌会');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('进入后台'), findsOneWidget);
    expect(find.text(adminTokenExpiredText), findsOneWidget);
    expect(notices, isEmpty);
  });

  testWidgets('a media row that could not be read recovers once the media '
      'page reads the library', (tester) async {
    api.listMediaError = const ApiException(
      code: 'UNAVAILABLE',
      message: '服务暂时不可用',
      status: 503,
    );
    await open(tester);
    await submit(tester);
    expect(find.text('读取失败'), findsOneWidget);

    api
      ..listMediaError = null
      ..media = [storedTrack(1)];
    await openSection(tester, '媒体');
    expect(find.text('歌曲 1'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 首 · 占用 1.0 MiB'), findsOneWidget);
    expect(find.text('读取失败'), findsNothing);
  });

  testWidgets('the rooms section shows the capacity of new ephemeral rooms, '
      'and saves a new one', (tester) async {
    api.ephemeralRoomCapacity = 16;
    await open(tester);
    await submit(tester);
    await tester.tap(find.text('房间'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('临时房间'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final field = _field('最多人数');
    final save = find.descendant(
      of: find.byType(EphemeralRoomsGroup),
      matching: find.text('保存'),
    );

    expect(tester.widget<EditableText>(field).controller.text, '16');
    expect(find.text('只对之后新建的临时房间生效'), findsOneWidget);

    await tester.enterText(field, '200');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('最多人数要在 2 到 128 之间'), findsOneWidget);
    expect(api.savedEphemeralRoomCapacities, isEmpty);

    await tester.enterText(field, '24');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(api.savedEphemeralRoomCapacities, [24]);
    expect(notices, [(ToastKind.success, '临时房间最多人数已保存')]);
    expect(tester.widget<EditableText>(field).controller.text, '24');
  });
}
