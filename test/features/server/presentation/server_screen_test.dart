import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../settings/settings_test_doubles.dart' show settingsOverrides;
import '../server_test_doubles.dart';

const _defaultId = 'fcd7a878032db68b';

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(AlistenTextField, label),
  matching: find.byType(EditableText),
);

Finder _deleteButton(String label) => find.byWidgetPredicate(
  (widget) => widget is IconCircleButton && widget.semanticLabel == label,
);

PillButton _button(WidgetTester tester, String label) =>
    tester.widget<PillButton>(find.widgetWithText(PillButton, label));

Finder _row(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Row)).first;

Finder _rowText(String name, String text) =>
    find.descendant(of: _row(name), matching: find.text(text));

Pressable _pressable(WidgetTester tester, String name) => tester.widget(
  find.ancestor(of: find.text(name), matching: find.byType(Pressable)).first,
);

// `find.text` 也会匹配输入框中的文字，这里只匹配显示的文字。
Finder _shown(String text) =>
    find.byWidgetPredicate((widget) => widget is Text && widget.data == text);

void main() {
  late FakeServerStore store;
  late FakeCredentialStores credentials;
  late FakeAlistenApi api;
  late FakeServerProbe probe;
  late List<String> forgotten;
  late List<(ToastKind, String)> notices;
  late int switched;
  late ProviderContainer container;

  setUp(() {
    store = FakeServerStore(profiles: [serverB, serverC]);
    credentials = FakeCredentialStores();
    api = FakeAlistenApi();
    probe = FakeServerProbe();
    forgotten = [];
    notices = [];
    switched = 0;
  });

  Future<void> open(
    WidgetTester tester, {
    Map<String, Object> preferences = const {},
    bool disableAnimations = false,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        ...await switchingOverrides(
          store: store,
          credentials: credentials,
          api: api,
          forgotten: forgotten,
          preferences: preferences,
        ),
        serverProbeProvider.overrideWithValue(probe),
        ...settingsOverrides(),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: ServerScreen(
            onSwitched: () => switched++,
            onNotice: (kind, text) => notices.add((kind, text)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  String currentId() => container.read(currentServerProvider).id;

  testWidgets('the servers are listed with their authority, the current and '
      'the built-in one marked, and only the others can be deleted', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    store.profiles = [serverB];
    await open(tester);

    expect(find.text('服务器'), findsOneWidget);
    for (final text in [
      'Alisten',
      'livehouse.dihe.moe',
      '内置',
      '当前',
      '周末听歌会',
      'example.com:8443',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.bySemanticsLabel('删除 周末听歌会'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('删除 Alisten')), findsNothing);
    expect(find.byType(IconCircleButton), findsNWidgets(2), reason: '返回、删除');
    for (final text in ['房主', '管理员']) {
      expect(find.textContaining(text), findsNothing);
    }
    semantics.dispose();
  });

  testWidgets('a server whose brand name shows nothing is listed by its '
      'authority', (tester) async {
    store.profiles = [serverB.withBrandName('​')];
    await open(tester);

    expect(find.text('example.com:8443'), findsNWidgets(2));
    expect(_deleteButton('删除 example.com:8443'), findsOneWidget);
  });

  testWidgets('the brand name of every server is asked for once on '
      'entering', (tester) async {
    probe.brands[serverB.origin] = '新名字';
    await open(tester);

    expect(probe.brandRequests, [
      'https://livehouse.dihe.moe',
      serverB.origin,
      serverC.origin,
    ]);
    expect(find.text('新名字'), findsOneWidget);
    expect(find.text('周末听歌会'), findsNothing);
  });

  testWidgets('a server this device has joined is switched to at once', (
    tester,
  ) async {
    credentials(serverB.id).memberToken = 'b';
    await open(tester);

    await tester.tap(find.text('周末听歌会'));
    await tester.pumpAndSettle();

    expect(find.text('加入 周末听歌会'), findsNothing);
    expect(switched, 1);
    expect(notices, [(ToastKind.success, '已切换到 周末听歌会')]);
    expect(currentId(), serverB.id);
  });

  testWidgets('a server not joined yet asks to join with the nickname and '
      'email in use, and is not switched to when cancelled', (tester) async {
    credentials(_defaultId).memberToken = 'm';
    await open(tester, preferences: {'alisten.email': 'a@b.c'});
    await container.read(identityControllerProvider.notifier).restore();
    await tester.pumpAndSettle();

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();

    expect(find.text('加入 另一个站'), findsOneWidget);
    expect(
      find.text('将以下面的昵称和邮箱加入，之后可以在设置里修改。邮箱只用来显示 Gravatar 头像。'),
      findsOneWidget,
    );
    expect(tester.widget<EditableText>(_field('昵称')).controller.text, '听众');
    expect(tester.widget<EditableText>(_field('邮箱')).controller.text, 'a@b.c');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('加入 另一个站'), findsNothing);
    expect(currentId(), _defaultId);
    expect(switched, 0);
    expect(notices, isEmpty);

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(api.createMemberCalls, 1);
    expect(api.updatedName, '听众');
    expect(api.updatedEmail, 'a@b.c');
    expect(await credentials(serverC.id).readMemberToken(), 'new-member-token');
    expect(switched, 1);
    expect(notices, [(ToastKind.success, '已切换到 另一个站')]);
  });

  testWidgets('joining with the email alone sends it to the new server', (
    tester,
  ) async {
    await open(tester, preferences: {'alisten.email': 'a@b.c'});

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(_field('昵称')).controller.text, '');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(api.createMemberCalls, 1);
    expect(api.updatedEmail, 'a@b.c');
    expect(notices, [(ToastKind.success, '已切换到 另一个站')]);
  });

  testWidgets('joining with neither a nickname nor an email sends nothing', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(api.createMemberCalls + api.updateMeCalls, 0);
    expect(notices, [(ToastKind.success, '已切换到 另一个站')]);
  });

  testWidgets('an email cleared when joining without a nickname is cleared on '
      'this device too', (tester) async {
    await open(tester, preferences: {'alisten.email': 'a@b.c'});

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(_field('邮箱')).controller.text, 'a@b.c');
    await tester.enterText(_field('邮箱'), '');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(container.read(settingsControllerProvider).value.email, '');
    expect(api.updatedEmail, '');
    expect(notices, [(ToastKind.success, '已切换到 另一个站')]);
  });

  testWidgets('a server renamed while its join sheet is open keeps the new '
      'name', (tester) async {
    await open(tester);

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    await container
        .read(serverDirectoryProvider.notifier)
        .updateBrandName(serverC.id, '新名字');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(
      store.profiles.singleWhere((p) => p.id == serverC.id).brandName,
      '新名字',
    );
    expect(notices, [(ToastKind.success, '已切换到 新名字')]);
  });

  testWidgets('a switch under way is shown on its row once the join sheet is '
      'closed, and the other servers wait for it', (tester) async {
    final writing = Completer<void>();
    store.onSaveCurrent = (_) => writing.future;
    await open(tester);

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    expect(find.text('切换中'), findsNothing, reason: 'covered by the sheet');

    await tester.tap(find.text('加入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_rowText('另一个站', '切换中'), findsOneWidget);
    expect(_pressable(tester, '周末听歌会').onPressed, isNull);
    expect(
      tester.widget<IconCircleButton>(_deleteButton('删除 周末听歌会')).onPressed,
      isNull,
    );
    expect(_button(tester, '添加服务器').onPressed, isNull);

    writing.complete();
    await tester.pumpAndSettle();

    expect(find.text('切换中'), findsNothing);
    expect(currentId(), serverC.id);
  });

  testWidgets('with animations removed the switch under way is shown '
      'still', (tester) async {
    final writing = Completer<void>();
    store.onSaveCurrent = (_) => writing.future;
    credentials(serverB.id).memberToken = 'b';
    await open(tester, disableAnimations: true);

    await tester.tap(find.text('周末听歌会'));
    await tester.pump();
    await tester.pump();

    expect(_rowText('周末听歌会', '切换中'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    writing.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a deletion under way is shown on its row', (tester) async {
    final writing = Completer<void>();
    await open(tester);
    store.onSaveProfiles = (_) => writing.future;

    await tester.tap(_deleteButton('删除 周末听歌会'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_rowText('周末听歌会', '删除中'), findsOneWidget);
    expect(_pressable(tester, '另一个站').onPressed, isNull);

    writing.complete();
    await tester.pumpAndSettle();

    expect(find.text('周末听歌会'), findsNothing);
    expect(find.text('删除中'), findsNothing);
  });

  testWidgets('a nickname changed when joining is the one saved', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('昵称'), '新来的');
    await tester.enterText(_field('邮箱'), 'me@example.com');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(api.updatedName, '新来的');
    expect(api.updatedEmail, 'me@example.com');
    expect(notices, [(ToastKind.success, '已切换到 另一个站')]);
  });

  testWidgets('a profile the new server refuses is a warning after the '
      'switch', (tester) async {
    api.updateMeError = const ApiException(
      code: 'INVALID_ARGUMENT',
      message: '昵称太长',
      status: 400,
    );
    await open(tester);

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('昵称'), '新来的');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(switched, 1);
    expect(notices, [(ToastKind.warning, '已切换到 另一个站，但昵称和邮箱没能保存，可以在设置里修改。')]);
  });

  testWidgets('a profile that could not be sent to the new server is a '
      'warning after the switch', (tester) async {
    api.createMemberError = const ApiException(
      code: LocalErrorCodes.network,
      message: '网络不可用',
      status: null,
    );
    await open(tester);

    await tester.tap(find.text('另一个站'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('昵称'), '新来的');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(currentId(), serverC.id);
    expect(notices, [(ToastKind.warning, '已切换到 另一个站，但昵称和邮箱没能保存，可以在设置里修改。')]);
  });

  testWidgets('a switch that fails says so and stays on the page', (
    tester,
  ) async {
    credentials(serverB.id).memberToken = 'b';
    store.failCurrentWrites = true;
    await open(tester);

    await tester.tap(find.text('周末听歌会'));
    await tester.pumpAndSettle();

    expect(currentId(), _defaultId);
    expect(switched, 0);
    expect(notices, [(ToastKind.failure, switchFailedText)]);
  });

  testWidgets('a server is deleted after it is confirmed', (tester) async {
    await open(tester);

    await tester.tap(_deleteButton('删除 周末听歌会'));
    await tester.pumpAndSettle();
    expect(find.text('删除 周末听歌会？'), findsOneWidget);
    expect(find.text('会删除这台设备在这个服务器上的身份和房间票据。'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('周末听歌会'), findsNothing);
    expect(forgotten, [serverB.id]);
    expect(
      store.profiles.map((profile) => profile.id),
      isNot(contains(serverB.id)),
    );
  });

  testWidgets('a deletion that is not confirmed deletes nothing', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(_deleteButton('删除 周末听歌会'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('周末听歌会'), findsOneWidget);
    expect(forgotten, isEmpty);
  });

  testWidgets('a server that cannot be deleted says so', (tester) async {
    await open(tester);
    store.failProfileWrites = true;

    await tester.tap(_deleteButton('删除 周末听歌会'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('周末听歌会'), findsOneWidget);
    expect(notices, [(ToastKind.failure, '没能删除 周末听歌会，请重试。')]);
  });

  testWidgets('a server added is checked, then joined and switched to', (
    tester,
  ) async {
    probe
      ..results['https://example.org'] = const ProbeSucceeded(
        origin: 'https://example.org',
        brandName: '新站',
      )
      ..gate = Completer<void>();
    await open(tester);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    expect(_button(tester, '检测').onPressed, isNull, reason: 'nothing typed');
    await tester.enterText(_field('服务器地址'), 'example.org');
    await tester.pump();
    await tester.tap(find.text('检测'));
    await tester.pump();

    expect(_button(tester, '检测').busy, isTrue);
    expect(find.text('添加并切换'), findsNothing);

    probe.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('新站'), findsOneWidget);
    expect(_shown('example.org'), findsOneWidget);
    expect(store.profiles.map((profile) => profile.origin), [
      serverB.origin,
      serverC.origin,
    ], reason: 'not saved before it is switched to');

    await tester.tap(find.text('添加并切换'));
    await tester.pumpAndSettle();
    expect(find.text('加入 新站'), findsOneWidget);
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    final added = store.profiles.singleWhere(
      (profile) => profile.origin == 'https://example.org',
    );
    expect(added.brandName, '新站');
    expect(store.currentId, added.id);
    expect(currentId(), added.id);
    expect(switched, 1);
    expect(notices, [(ToastKind.success, '已切换到 新站')]);
  });

  testWidgets('the address field waits to be tapped before the keyboard '
      'comes up', (tester) async {
    await open(tester);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();

    final field = _field('服务器地址');
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(field);
    await tester.pump();

    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('a server that cannot be reached is not offered for '
      'adding', (tester) async {
    await open(tester);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('服务器地址'), 'example.org');
    await tester.pump();
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();

    expect(find.text('连不上这个服务器'), findsOneWidget);
    expect(find.text('添加并切换'), findsNothing);

    await tester.enterText(_field('服务器地址'), 'example.net');
    await tester.pump();
    expect(find.text('连不上这个服务器'), findsNothing, reason: 'edited');
  });

  testWidgets('a server added and then not joined is not saved', (
    tester,
  ) async {
    probe.results['https://example.org'] = const ProbeSucceeded(
      origin: 'https://example.org',
      brandName: '新站',
    );
    await open(tester);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('服务器地址'), 'example.org');
    await tester.pump();
    await tester.tap(find.text('检测'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加并切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(
      store.profiles.where(
        (profile) => profile.origin == 'https://example.org',
      ),
      isEmpty,
    );
    expect(currentId(), _defaultId);
    expect(switched, 0);
  });

  testWidgets('the current server cannot be switched to again', (tester) async {
    await open(tester);

    await tester.tap(find.text('Alisten'));
    await tester.pumpAndSettle();

    expect(switched, 0);
    expect(notices, isEmpty);
    expect(store.currentIdWrites, isEmpty);
  });
}
