import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/lobby/index.dart';
import 'package:alisten/features/lobby/presentation/join_room_sheet.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/section_header.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';
import '../../../core/avatar/avatar_test_doubles.dart';
import '../../../domain/room/room_fixtures.dart';
import '../../room/room_test_doubles.dart';
import '../lobby_test_doubles.dart';

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(AlistenTextField, label),
  matching: find.byType(EditableText),
);

// 大厅页本身只有筛选框这一个输入框。
Finder get _filter => find.descendant(
  of: find.byType(LobbyScreen),
  matching: find.byType(EditableText),
);

Finder get _filterButton => find.byWidgetPredicate(
  (widget) => widget is IconCircleButton && widget.semanticLabel == '筛选房间',
);

Finder get _focused => find.byWidgetPredicate(
  (widget) => widget is EditableText && widget.focusNode.hasFocus,
);

Finder get _joinSheet => find.byType(JoinRoomSheet);

Future<void> _openFilter(WidgetTester tester) async {
  await tester.tap(_filterButton);
  await tester.pump();
  await tester.pump(AlistenDurations.short);
}

// 容器跨挂载保留，用于验证重建后的状态。
final class _Lobby {
  _Lobby._(this.tester, this.container, this.api, this.rooms);

  final WidgetTester tester;
  final ProviderContainer container;
  final FakeAlistenApi api;
  final FakeRoomTransportFactory rooms;
  final opened = <String>[];
  final notices = <(ToastKind, String)>[];

  static Future<_Lobby> open(
    WidgetTester tester, {
    FakeAlistenApi? api,
    FakeCredentialStore? credentials,
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final server = api ?? FakeAlistenApi();
    final rooms = FakeRoomTransportFactory();
    final container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(server),
        credentialStoreProvider.overrideWithValue(
          credentials ?? FakeCredentialStore(),
        ),
        roomTransportFactoryProvider.overrideWithValue(rooms.call),
        ...roomDeviceOverrides(),
        clearLocalEmailProvider.overrideWithValue(() async {}),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    final lobby = _Lobby._(tester, container, server, rooms);
    await lobby.show();
    return lobby;
  }

  Future<void> show() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: LobbyScreen(
            onOpenRoom: opened.add,
            onOpenHistory: () {},
            onOpenSettings: () {},
            onNotice: (kind, text) => notices.add((kind, text)),
          ),
        ),
      ),
    );
    await settle();
  }

  Future<void> hide() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
  }

  // 加载指示器持续转动，pumpAndSettle 无法结束，只能按时间推进。
  Future<void> settle() async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> systemBack() {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.navigation.name,
          const JSONMessageCodec().encodeMessage(<String, Object?>{
            'method': 'popRoute',
          }),
          (_) {},
        );
  }
}

void main() {
  testWidgets('the filter shows what was typed when the lobby opens again', (
    tester,
  ) async {
    final lobby = await _Lobby.open(
      tester,
      api: FakeAlistenApi()
        ..rooms = [
          roomListing(name: 'abc 之夜'),
          roomListing(id: 'rock', slug: 'rock', name: '摇滚'),
        ],
    );
    await _openFilter(tester);
    await tester.enterText(_filter, 'abc');
    await tester.pump();
    expect(find.text('摇滚'), findsNothing);

    await lobby.hide();
    await lobby.show();

    final filter = tester.widget<EditableText>(_filter);
    expect(filter.controller.text, 'abc');
    expect(_focused, findsNothing, reason: 'shown, but no keyboard');
    expect(find.text('abc 之夜'), findsOneWidget);
    expect(find.text('摇滚'), findsNothing);
  });

  testWidgets('the lobby offers no way to type a room in: its top bar has '
      'history and settings only', (tester) async {
    final semantics = tester.ensureSemantics();
    await _Lobby.open(tester, api: FakeAlistenApi()..rooms = [roomListing()]);

    expect(find.bySemanticsLabel('加入房间'), findsNothing);
    expect(find.bySemanticsLabel('播放历史'), findsOneWidget);
    expect(find.bySemanticsLabel('设置'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a room that needs a password says so, and its sheet asks for '
      'the password alone, naming the room by its listing', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = FakeAlistenApi()
      ..rooms = [
        roomListing(
          id: '123e4567-e89b-42d3-a456-426614174000',
          name: '私人房间',
          slug: 'private',
          description: '',
          hasPassword: true,
          onlineCount: 2,
        ),
        roomListing(id: 'open', slug: 'open', name: '公开房间'),
      ];
    final lobby = await _Lobby.open(tester, api: api);

    expect(
      find.bySemanticsLabel(RegExp('私人房间.*需要密码', dotAll: true)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('公开房间.*需要密码', dotAll: true)),
      findsNothing,
    );

    await tester.tap(find.text('私人房间'));
    await tester.pumpAndSettle();
    expect(_joinSheet, findsOneWidget);
    Finder inSheet(Finder finder) =>
        find.descendant(of: _joinSheet, matching: finder);
    expect(inSheet(find.text('私人房间')), findsOneWidget);
    expect(inSheet(find.text('来这里，听见好音乐。')), findsOneWidget);
    expect(inSheet(find.text('2 人在线')), findsOneWidget);
    expect(inSheet(find.text('需要密码')), findsOneWidget);
    expect(inSheet(find.byType(EditableText)), findsOneWidget);
    expect(inSheet(_field('房间密码')), findsOneWidget);
    for (final hidden in ['UUID', '别名', 'private', '123e4567']) {
      expect(
        inSheet(find.textContaining(hidden)),
        findsNothing,
        reason: hidden,
      );
      expect(
        inSheet(find.bySemanticsLabel(RegExp(hidden))),
        findsNothing,
        reason: hidden,
      );
    }
    final enter = tester.widget<PillButton>(
      inSheet(find.widgetWithText(PillButton, '进入房间')),
    );
    expect(enter.onPressed, isNull, reason: 'no password typed yet');

    await tester.enterText(_field('房间密码'), 'secret');
    await tester.pump();
    await tester.tap(find.text('进入房间'));
    await lobby.settle();
    await tester.pumpAndSettle();
    expect(_joinSheet, findsNothing);
    expect(lobby.opened, ['private']);
    expect(api.lastGetRoomRef, '123e4567-e89b-42d3-a456-426614174000');
    semantics.dispose();
  });

  testWidgets('a password sheet leaves the keyboard down until its field is '
      'tapped', (tester) async {
    await _Lobby.open(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(hasPassword: true)],
    );

    await tester.tap(find.text('一起听'));
    await tester.pumpAndSettle();
    expect(_joinSheet, findsOneWidget);
    expect(_focused, findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(_field('房间密码'));
    await tester.pump();
    expect(_focused, findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('the room creation sheet leaves the keyboard down until a field '
      'is tapped', (tester) async {
    await _Lobby.open(tester);

    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    expect(_field('房间名称'), findsOneWidget);
    expect(_focused, findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(_field('房间名称'));
    await tester.pump();
    expect(_focused, findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('while a password room checks for its ticket, its card says it '
      'is entering and nothing else can be started', (tester) async {
    final semantics = tester.ensureSemantics();
    final credentials = FakeCredentialStore();
    final api = FakeAlistenApi()
      ..rooms = [
        roomListing(hasPassword: true),
        roomListing(id: 'other', slug: 'other', name: '另一间'),
      ];
    await _Lobby.open(tester, api: api, credentials: credentials);
    final storage = credentials.readTicketGate = Completer<void>();

    await tester.tap(find.text('一起听'));
    await tester.pump();
    expect(find.bySemanticsLabel('正在进入'), findsOneWidget);
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, '创建房间'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('另一间'), warnIfMissed: false);
    await tester.pump();

    storage.complete();
    await tester.pumpAndSettle();
    expect(_joinSheet, findsOneWidget);
    expect(
      find.descendant(of: _joinSheet, matching: find.text('一起听')),
      findsOneWidget,
    );
    expect(api.getRoomCalls, 0, reason: 'the other room was not entered');
    expect(
      find.descendant(
        of: find.byType(LobbyScreen),
        matching: find.byType(BusyIndicator),
      ),
      findsNothing,
      reason: 'the card stops turning once the sheet is up',
    );
    semantics.dispose();
  });

  testWidgets('a password room whose ticket is held opens its sheet without '
      'asking for the password', (tester) async {
    final api = FakeAlistenApi()..rooms = [roomListing(hasPassword: true)];
    final lobby = await _Lobby.open(
      tester,
      api: api,
      credentials: FakeCredentialStore()..tickets['room-id'] = 'held-ticket',
    );

    await tester.tap(find.text('一起听'));
    await tester.pumpAndSettle();
    expect(_joinSheet, findsOneWidget);
    expect(
      find.descendant(of: _joinSheet, matching: find.byType(EditableText)),
      findsNothing,
    );

    await tester.tap(find.text('进入房间'));
    await lobby.settle();
    await tester.pumpAndSettle();
    expect(lobby.opened, ['listen']);
    expect(api.createTicketCalls, 0, reason: 'the held ticket is used');
    expect(lobby.rooms.tickets, ['held-ticket']);
  });

  testWidgets('the room creation sheet stays while its room is created, '
      'whatever closes sheets otherwise', (tester) async {
    final api = FakeAlistenApi()..createMemberGate = Completer<void>();
    final lobby = await _Lobby.open(tester, api: api);

    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('房间名称'), '新房间');
    await tester.tap(find.text('创建并进入'));
    await lobby.settle();
    expect(api.createRoomCalls, 1);

    await tester.tapAt(const Offset(20, 40));
    await lobby.settle();
    await lobby.systemBack();
    await lobby.settle();
    expect(find.text('创建并进入'), findsOneWidget);

    api.createMemberGate!.complete();
    await lobby.settle();
    expect(find.text('创建并进入'), findsNothing);
    expect(lobby.opened, ['created-room-id']);
    expect(api.createRoomCalls, 1);
  });

  testWidgets('a sheet whose request breaks unexpectedly says the result is '
      'unknown, as a warning, and can be closed again', (tester) async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    final api = FakeAlistenApi()
      ..rooms = [roomListing(hasPassword: true)]
      ..createRoomError = const FormatException('新房间 secret');
    final lobby = await _Lobby.open(tester, api: api);

    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('房间名称'), '新房间');
    await tester.enterText(_field('密码（可选）'), 'secret');
    await tester.tap(find.text('创建并进入'));
    await lobby.settle();
    // 结果未知，不能提示为失败。
    expect(find.textContaining('房间可能已经创建'), findsOneWidget);
    expect(
      tester.widget<InlineMessage>(find.byType(InlineMessage)).tone,
      StatusTone.warning,
    );
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text('创建并进入'), findsNothing);

    final start = lobby.rooms.startGate = Completer<void>();
    await tester.tap(find.text('一起听'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('房间密码'), 'secret');
    await tester.pump();
    await tester.tap(find.text('进入房间'));
    await lobby.settle();
    start.completeError(StateError('ticket-for-room-id'));
    await lobby.settle();
    expect(find.textContaining('没能确认操作结果'), findsOneWidget);
    expect(
      tester.widget<InlineMessage>(find.byType(InlineMessage)).tone,
      StatusTone.warning,
    );
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(_joinSheet, findsNothing);

    final errors = [
      for (final record in records)
        if (record.$2 >= 1000) record,
    ];
    expect(errors.map((record) => record.$1), [
      'alisten.lobby',
      'alisten.lobby',
    ]);
    expect(
      errors.where(
        (record) =>
            record.$3.contains('secret') ||
            record.$3.contains('新房间') ||
            record.$3.contains('ticket'),
      ),
      isEmpty,
    );
  });

  testWidgets('a sheet shows the failure of its own request only, as a '
      'failure', (tester) async {
    final api = FakeAlistenApi()
      ..rooms = [roomListing(hasPassword: true)]
      ..ticketError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '房间密码错误',
        status: 401,
      );
    final lobby = await _Lobby.open(tester, api: api);

    await tester.tap(find.text('一起听'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('房间密码'), 'wrong');
    await tester.pump();
    await tester.tap(find.text('进入房间'));
    await lobby.settle();
    expect(find.text('房间密码错误'), findsOneWidget);
    expect(
      tester.widget<InlineMessage>(find.byType(InlineMessage)).tone,
      StatusTone.danger,
    );

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一起听'));
    await tester.pumpAndSettle();
    expect(find.text('房间密码错误'), findsNothing);

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    expect(find.text('房间密码错误'), findsNothing);
  });

  testWidgets('a room joined from its card opens, other cards waiting '
      'meanwhile', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = FakeAlistenApi()
      ..rooms = [
        roomListing(),
        roomListing(id: 'other', slug: 'other', name: '另一间'),
      ]
      ..createMemberGate = Completer<void>();
    final lobby = await _Lobby.open(tester, api: api);

    await tester.tap(find.text('一起听'));
    await lobby.settle();
    expect(find.bySemanticsLabel('正在进入'), findsOneWidget);
    await tester.tap(find.text('另一间'), warnIfMissed: false);
    api.createMemberGate!.complete();
    await lobby.settle();

    expect(lobby.opened, ['listen']);
    expect(api.createTicketCalls, 1);
    expect(find.bySemanticsLabel('正在进入'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a room that cannot be joined from its card says why', (
    tester,
  ) async {
    final api = FakeAlistenApi()
      ..rooms = [roomListing()]
      ..getRoomError = const ApiException(
        code: 'NOT_FOUND',
        message: '房间不存在或已经关闭。',
        status: 404,
      );
    final lobby = await _Lobby.open(tester, api: api);

    await tester.tap(find.text('一起听'));
    await lobby.settle();

    expect(lobby.opened, isEmpty);
    expect(lobby.notices, [(ToastKind.failure, '房间不存在或已经关闭。')]);
  });

  testWidgets('a refresh that fails while rooms are shown says so above '
      'them, and retrying replaces it', (tester) async {
    final api = FakeAlistenApi()..rooms = [roomListing()];
    final lobby = await _Lobby.open(tester, api: api);
    expect(api.listRoomsCalls, 1);

    api.listError = const FormatException('offline');
    await tester.tap(find.bySemanticsLabel('刷新房间列表'));
    await lobby.settle();
    expect(find.text('房间加载失败，请重试。'), findsOneWidget);
    expect(find.text('一起听'), findsOneWidget);

    api.listError = null;
    api.rooms = [roomListing(), roomListing(id: 'b', slug: 'b', name: '新的')];
    await tester.tap(find.text('重试'));
    await lobby.settle();
    expect(find.text('房间加载失败，请重试。'), findsNothing);
    expect(find.text('新的'), findsOneWidget);
  });

  for (final rooms in [1, 0]) {
    testWidgets('pulling the list down refreshes it, the pulled disc alone '
        'turning, with $rooms rooms', (tester) async {
      final semantics = tester.ensureSemantics();
      final api = FakeAlistenApi()
        ..rooms = [for (var index = 0; index < rooms; index++) roomListing()];
      final lobby = await _Lobby.open(tester, api: api);
      final answer = Completer<List<RoomListing>>();
      api.listRoomsHandler = () => answer.future;

      // 逐帧下拉：越过边界后，下拉越远阻力越大。
      final finger = await tester.startGesture(
        tester.getCenter(find.byType(SectionHeader)),
      );
      for (var step = 0; step < 15; step++) {
        await finger.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      await finger.up();
      await lobby.settle();

      expect(api.listRoomsCalls, 2);
      expect(find.bySemanticsLabel('正在刷新'), findsOneWidget);
      expect(find.bySemanticsLabel('正在刷新房间列表'), findsNothing);
      expect(find.bySemanticsLabel('正在加载房间'), findsNothing);

      answer.complete([
        roomListing(),
        roomListing(id: 'b', slug: 'b', name: '新的'),
      ]);
      await lobby.settle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('新的'), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('a refresh asked for by its button shows beside the heading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = FakeAlistenApi()..rooms = [roomListing()];
    final lobby = await _Lobby.open(tester, api: api);
    final answer = Completer<List<RoomListing>>();
    api.listRoomsHandler = () => answer.future;

    await tester.tap(find.bySemanticsLabel('刷新房间列表'));
    await lobby.settle();
    expect(find.bySemanticsLabel('正在刷新房间列表'), findsOneWidget);
    expect(find.bySemanticsLabel('正在刷新'), findsNothing);

    answer.complete([roomListing()]);
    await lobby.settle();
    semantics.dispose();
  });

  testWidgets('without rooms the lobby says so and can be refreshed', (
    tester,
  ) async {
    final api = FakeAlistenApi();
    final lobby = await _Lobby.open(tester, api: api);
    expect(find.text('还没有可加入的房间'), findsOneWidget);

    api.rooms = [roomListing()];
    await tester.tap(find.text('刷新'));
    await lobby.settle();
    expect(find.text('还没有可加入的房间'), findsNothing);
    expect(find.text('一起听'), findsOneWidget);
  });

  testWidgets('the active room is offered to continue with its playing song, '
      'its cover not taking the mini player\'s flight', (tester) async {
    final lobby = await _Lobby.open(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(slug: 'listen')],
      credentials: FakeCredentialStore()..tickets['room-id'] = 'ticket',
    );
    expect(find.text('继续收听'), findsNothing);

    unawaited(
      lobby.container.read(roomControllerProvider.notifier).openRoom('listen'),
    );
    await lobby.settle();
    lobby.rooms.last.emitHello(testRoomSnapshot());
    await lobby.settle();

    final card = find.ancestor(
      of: find.text('继续收听'),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('房间')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('歌曲 · 歌手')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(Hero)),
      findsNothing,
    );

    await tester.tap(find.text('继续收听'));
    expect(lobby.opened, ['room-id']);
  });

  testWidgets('the room filter stays folded behind its button until asked '
      'for, and folds again when left empty', (tester) async {
    final lobby = await _Lobby.open(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing()],
    );
    expect(_filterButton, findsOneWidget);
    expect(_filter, findsNothing);
    expect(_focused, findsNothing);

    await tester.tap(_filterButton);
    await lobby.settle();
    expect(_filter, findsOneWidget);
    expect(_focused, findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(_filterButton, findsNothing);

    // 点按输入框以外放下焦点；筛选为空，所以输入框收起。
    await tester.tapAt(tester.getCenter(find.text('房间').first));
    await lobby.settle();
    expect(_focused, findsNothing);
    expect(_filter, findsNothing);
    expect(_filterButton, findsOneWidget);
  });

  for (final still in [false, true]) {
    testWidgets(
      'the filter unfolds and folds '
      '${still ? 'at once when animations are removed' : 'over a short time'}',
      (tester) async {
        if (still) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        final lobby = await _Lobby.open(
          tester,
          api: FakeAlistenApi()..rooms = [roomListing()],
        );
        // 筛选框的高度按分区标题与第一张房间卡片的间距计算。
        final card = find.ancestor(
          of: find.text('一起听'),
          matching: find.byType(GlassPanel),
        );
        double slot() =>
            tester.getTopLeft(card).dy -
            tester.getBottomLeft(find.byType(SectionHeader)).dy;
        expect(slot(), moreOrLessEquals(0));

        await tester.tap(_filterButton);
        await tester.pump();
        final unfolded =
            tester
                .getSize(find.byType(AlistenTextField, skipOffstage: false))
                .height +
            AlistenSpacing.sm;
        expect(
          slot(),
          still ? moreOrLessEquals(unfolded) : lessThan(unfolded - 1),
        );
        await lobby.settle();
        expect(slot(), moreOrLessEquals(unfolded));

        await tester.tapAt(tester.getCenter(find.text('房间').first));
        await tester.pump();
        await tester.pump(AlistenDurations.short ~/ 2);
        final field = find.byType(AlistenTextField, skipOffstage: false);
        if (still) {
          expect(field, findsNothing);
          expect(slot(), moreOrLessEquals(0));
        } else {
          // 输入框随高度一同收起，而不是先变成空白再收缩。
          expect(field, findsOneWidget);
          expect(slot(), allOf(greaterThan(1), lessThan(unfolded - 1)));
        }
        await lobby.settle();
        expect(field, findsNothing);
        expect(slot(), moreOrLessEquals(0));
        expect(_filterButton, findsOneWidget);
      },
    );
  }

  testWidgets('a filter with words stays open when left, without the '
      'keyboard', (tester) async {
    final lobby = await _Lobby.open(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing()],
    );
    await _openFilter(tester);
    await tester.enterText(_filter, '一起');
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.text('房间').first));
    await lobby.settle();
    expect(_focused, findsNothing);
    expect(tester.widget<EditableText>(_filter).controller.text, '一起');
  });

  testWidgets('a sheet opened while filtering does not give the filter the '
      'keyboard back when it closes', (tester) async {
    final semantics = tester.ensureSemantics();
    final lobby = await _Lobby.open(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(hasPassword: true)],
    );
    await _openFilter(tester);
    await tester.enterText(_filter, '一起');
    await tester.pump();
    expect(_focused, findsOneWidget);

    // 读屏的点按不经过指针，点按外部不会先放下焦点。
    for (final open in ['创建房间', RegExp('一起听')]) {
      tester.semantics.tap(find.semantics.byLabel(open));
      await tester.pumpAndSettle();
      expect(find.byType(SheetPanel), findsOneWidget, reason: '$open');
      await lobby.systemBack();
      await tester.pumpAndSettle();
      expect(find.byType(SheetPanel), findsNothing, reason: '$open');
      expect(_focused, findsNothing, reason: '$open');
    }
    expect(tester.widget<EditableText>(_filter).controller.text, '一起');
    semantics.dispose();
  });

  testWidgets('back from a room entered while filtering, the filter keeps its '
      'words and leaves the keyboard down', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()
        ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[testRoomId] = 'saved-ticket',
    );
    final router = appContainer(tester).read(routerProvider);
    // 房间页的背景动画不会停止，只能逐步推进时间。
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    await _openFilter(tester);
    await tester.enterText(_filter, '一起');
    await tester.pump();
    expect(_focused, findsOneWidget);

    // 读屏的点按不经过指针，点按外部不会先放下焦点。
    tester.semantics.tap(find.semantics.byLabel(RegExp('^一起听')));
    await settle();
    expect(router.state.uri.path, '/r/listen');

    router.go('/');
    await settle();
    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(_focused, findsNothing);
    expect(tester.widget<EditableText>(_filter).controller.text, '一起');
    semantics.dispose();
  });

  testWidgets('a join sheet still checking for its ticket when the lobby is '
      'left is not opened over another page', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final credentials = FakeCredentialStore();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()
        ..rooms = [
          roomListing(id: testRoomId, slug: 'listen', hasPassword: true),
        ],
      credentials: credentials,
    );
    final router = appContainer(tester).read(routerProvider);
    final storage = credentials.readTicketGate = Completer<void>();

    await tester.tap(find.text('一起听'));
    await tester.pump();
    router.go('/settings');
    await tester.pumpAndSettle();
    storage.complete();
    await tester.pumpAndSettle();
    expect(find.byType(JoinRoomSheet), findsNothing);

    router.go('/');
    await tester.pumpAndSettle();
    expect(find.byType(JoinRoomSheet), findsNothing);
    await tester.tap(find.text('一起听'));
    await tester.pumpAndSettle();
    expect(find.byType(JoinRoomSheet), findsOneWidget);
  });

  testWidgets('a join sheet still checking for its ticket when a room page '
      'opens over the lobby is not opened over the room', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const otherId = '223e4567-e89b-42d3-a456-426614174000';
    final credentials = FakeCredentialStore()..tickets[otherId] = 'saved';
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()
        ..rooms = [
          roomListing(id: testRoomId, slug: 'listen', hasPassword: true),
          roomListing(id: otherId, slug: 'beta', name: '另一个房间'),
        ],
      credentials: credentials,
      rooms: rooms,
    );
    final router = appContainer(tester).read(routerProvider);
    // 房间页的背景动画不会停止，只能逐步推进时间。
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    final storage = credentials.readTicketGate = Completer<void>();
    await tester.tap(find.text('一起听'));
    await tester.pump();
    // 模拟点开邀请链接或通知；此时大厅仍是外壳中最上层的页面。
    router.go('/r/beta');
    await settle();
    storage.complete();
    await settle();

    expect(router.state.uri.path, '/r/beta');
    expect(find.byType(JoinRoomSheet), findsNothing);
    rooms.last.emitHello();
    await settle();
    expect(find.byType(JoinRoomSheet), findsNothing);
  });

  testWidgets('the filter gives up the keyboard when the app goes to the '
      'background, and does not take it back on return', (tester) async {
    final lobby = await _Lobby.open(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing()],
    );
    await _openFilter(tester);
    await tester.enterText(_filter, '一起');
    await tester.pump();
    expect(_focused, findsOneWidget);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await lobby.settle();
    }

    expect(_focused, findsNothing);
    expect(tester.widget<EditableText>(_filter).controller.text, '一起');
  });

  testWidgets('a card that cannot tell whether its room was entered says so '
      'as a warning', (tester) async {
    final api = FakeAlistenApi()..rooms = [roomListing()];
    final lobby = await _Lobby.open(tester, api: api);
    final start = lobby.rooms.startGate = Completer<void>();

    await tester.tap(find.text('一起听'));
    await lobby.settle();
    start.completeError(StateError('broken'));
    await lobby.settle();

    expect(lobby.opened, isEmpty);
    expect(lobby.notices.map((notice) => notice.$1), [ToastKind.warning]);
  });

  group('the settings button', () {
    const listener = Member(id: 'member-id', name: '听众', avatarHash: 'abc123');
    final avatarUrl = listener.avatarUrl(AlistenSizes.avatar)!;

    setUp(() {
      imageCache
        ..clear()
        ..clearLiveImages();
    });

    Finder inSettings(Finder finder) =>
        find.descendant(of: _settingsButton, matching: finder);

    Finder gear() => inSettings(find.byIcon(Icons.settings_rounded));

    Future<void> openAs(
      WidgetTester tester,
      Member? member, {
      FakeAvatarCache? avatars,
    }) async {
      tester.view
        ..physicalSize = const Size(360, 780) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final api = FakeAlistenApi()..rooms = [roomListing()];
      if (member != null) {
        api.getMeResult = Completer<Member>()..complete(member);
      }
      await pumpAlistenApp(
        tester,
        api: api,
        credentials: member == null
            ? null
            : (FakeCredentialStore()..memberToken = 'member-token'),
        avatarCache: avatars,
      );
    }

    testWidgets('without a member shows the gear', (tester) async {
      await openAs(tester, null);
      await _finishLoading(tester);

      expect(gear(), findsOneWidget);
      expect(inSettings(find.byType(RawImage)), findsNothing);
    });

    testWidgets('for a member without an avatar address shows the gear', (
      tester,
    ) async {
      await openAs(
        tester,
        const Member(id: 'member-id', name: '听众', avatarHash: ''),
      );
      await _finishLoading(tester);

      expect(gear(), findsOneWidget);
      expect(inSettings(find.byType(RawImage)), findsNothing);
    });

    testWidgets('turns into the avatar once the member gives an avatar '
        'email', (tester) async {
      final png = (await tester.runAsync(_png))!;
      const withAvatar = Member(id: 'member-id', name: '听众', avatarHash: 'x');
      final api = FakeAlistenApi()..rooms = [roomListing()];
      api
        ..getMeResult = (Completer<Member>()
          ..complete(const Member(id: 'member-id', name: '听众', avatarHash: '')))
        ..updateMeHandler = (_, _) => withAvatar;
      tester.view
        ..physicalSize = const Size(360, 780) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpAlistenApp(
        tester,
        api: api,
        credentials: FakeCredentialStore()..memberToken = 'member-token',
        avatarCache: FakeAvatarCache(
          avatars: {withAvatar.avatarUrl(AlistenSizes.avatar)!: png},
        ),
      );
      await _finishLoading(tester);
      expect(gear(), findsOneWidget);

      final saved = await appContainer(tester)
          .read(identityControllerProvider.notifier)
          .saveProfile(email: 'a@b.c');
      expect(saved, isA<MutationSucceeded<Member>>());
      expect(
        appContainer(tester).read(identityControllerProvider).member,
        withAvatar,
      );
      await tester.pump();
      await _finishLoading(tester);
      await tester.pumpAndSettle();

      expect(gear(), findsNothing);
      expect(inSettings(find.byType(RawImage)), findsOneWidget);
    });

    testWidgets('shows the avatar once it is loaded, still reads as the '
        'settings, and opens them', (tester) async {
      final semantics = tester.ensureSemantics();
      final png = (await tester.runAsync(_png))!;
      await openAs(
        tester,
        listener,
        avatars: FakeAvatarCache(avatars: {avatarUrl: png}),
      );
      await _finishLoading(tester);
      await tester.pumpAndSettle();

      expect(gear(), findsNothing);
      expect(
        tester.widget<RawImage>(inSettings(find.byType(RawImage))).image,
        isNotNull,
      );
      final node = tester.getSemantics(find.bySemanticsLabel('设置'));
      expect(node.label, '设置');
      expect(node.childrenCount, 0);

      await tester.tap(_settingsButton);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shows the gear when the member has no avatar', (tester) async {
      await openAs(tester, listener, avatars: FakeAvatarCache());
      await _finishLoading(tester);
      await tester.pumpAndSettle();

      expect(gear(), findsOneWidget);
      expect(inSettings(find.byType(RawImage)), findsNothing);
    });

    testWidgets('shows the gear when the avatar cannot be loaded', (
      tester,
    ) async {
      await openAs(
        tester,
        listener,
        avatars: FakeAvatarCache()..unreachable = true,
      );
      await _finishLoading(tester);
      await tester.pumpAndSettle();

      expect(gear(), findsOneWidget);
      expect(inSettings(find.byType(RawImage)), findsNothing);
    });

    testWidgets('keeps its size while the gear turns into the avatar', (
      tester,
    ) async {
      final png = (await tester.runAsync(_png))!;
      final loading = Completer<void>();
      await openAs(
        tester,
        listener,
        avatars: FakeAvatarCache(avatars: {avatarUrl: png})..loading = loading,
      );
      expect(gear(), findsOneWidget);
      final shown = tester.getRect(_settingsButton);

      loading.complete();
      await _finishLoading(tester);
      expect(inSettings(find.byType(RawImage)), findsOneWidget);
      expect(tester.getRect(_settingsButton), shown);

      await tester.pumpAndSettle();
      expect(gear(), findsNothing);
      expect(tester.getRect(_settingsButton), shown);
      expect(
        tester.getSize(inSettings(find.byType(RawImage))),
        const Size.square(AlistenSizes.avatar),
      );
      expect(tester.getCenter(inSettings(find.byType(RawImage))), shown.center);
    });
  });
}

Finder get _settingsButton => find.byWidgetPredicate(
  (widget) => widget is IconCircleButton && widget.semanticLabel == '设置',
);

// 解码在引擎中真实异步进行：让出真实时间，直到没有加载中的图片，最多等 5 秒。
Future<void> _finishLoading(WidgetTester tester) async {
  final waited = Stopwatch()..start();
  while (imageCache.pendingImageCount > 0 &&
      waited.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pump();
}

Future<Uint8List> _png() async {
  final image = await createTestImage(width: 8, height: 8, cache: false);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
