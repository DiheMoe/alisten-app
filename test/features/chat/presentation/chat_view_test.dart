import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../../shared/ui/edge_fade_probe.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';

// 本机成员：假房间的每次握手都返回这个成员。
const _me = testMember;
const _xiaoming = Member(id: 'xiaoming', name: '小明', avatarHash: '');

final class _Room {
  _Room(this.tester);

  final WidgetTester tester;
  final rooms = FakeRoomTransportFactory();
  late final ProviderContainer container;
  var _seq = 1;

  FakeRoomTransport get transport => rooms.last;

  Future<void> open({List<Member> members = const [_me, _xiaoming]}) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(
          FakeAlistenApi()..rooms = [roomListing()],
        ),
        credentialStoreProvider.overrideWithValue(
          FakeCredentialStore()..tickets['room-id'] = 'saved-ticket',
        ),
        roomTransportFactoryProvider.overrideWithValue(rooms.call),
        ...roomDeviceOverrides(),
      ],
    );
    addTearDown(container.dispose);
    await container.read(roomControllerProvider.notifier).openRoom('listen');
    transport.emitHello(
      testRoomSnapshot().copyWith(
        term: 1,
        seq: 1,
        members: members,
        onlineCount: members.length,
      ),
    );
    await tester.pump();
  }

  // 房间事件在微任务中到达，视图在下一帧显示它们。
  Future<void> deliver() async {
    await tester.pump();
    await tester.pump();
  }

  void emit(RoomEvent Function(int seq) event) {
    transport.emit(RoomEventReceived(event(++_seq)));
  }

  void say(Member who, String text) {
    emit(
      (seq) => ChatMessageEvent(
        term: 1,
        seq: seq,
        member: who,
        content: text,
        sentAtMs: 1000,
      ),
    );
  }

  Widget _app(Widget body) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: Scaffold(body: body),
      ),
    );
  }

  Future<void> showChat() async {
    await tester.pumpWidget(_app(const ChatView()));
    await tester.pump();
  }

  Future<void> showOtherMode() async {
    await tester.pumpWidget(_app(const SizedBox.expand()));
  }
}

Finder get _timeline => find.byType(CustomScrollView);

Finder get _timelineScrollable =>
    find.descendant(of: _timeline, matching: find.byType(Scrollable)).first;

// 向上滚动到 [text] 出现，返回它顶边的纵坐标。
Future<double> _readBackTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    300,
    scrollable: _timelineScrollable,
  );
  await tester.pumpAndSettle();
  return tester.getTopLeft(find.text(text)).dy;
}

Finder _avatarInTimeline(String name) => find.descendant(
  of: _timeline,
  matching: find.byWidgetPredicate(
    (widget) => widget is MemberAvatar && widget.name == name,
  ),
);

String _fieldText(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).controller!.text;
}

void main() {
  testWidgets('the keyboard send action sends the draft once and keeps the '
      'keyboard up for the next one', (tester) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();

    await tester.enterText(find.byType(TextField), '晚上好');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(room.transport.requests, hasLength(1));
    expect(room.transport.requests.single['data'], {'content': '晚上好'});
    expect(_fieldText(tester), isEmpty);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
  });

  testWidgets('own messages sit on the right beside the own avatar, and '
      "others' on the left beside theirs", (tester) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();

    room
      ..say(_xiaoming, '欢迎')
      ..say(_me, '谢谢');
    await room.deliver();

    final half = tester.getSize(find.byType(ChatView)).width / 2;
    final mine = tester.getRect(find.text('谢谢'));
    final theirs = tester.getRect(find.text('欢迎'));
    expect(mine.left, greaterThan(half));
    expect(theirs.right, lessThan(half));
    expect(
      tester.getRect(_avatarInTimeline(_me.name)).left,
      greaterThanOrEqualTo(mine.right),
    );
    expect(
      tester.getRect(_avatarInTimeline(_xiaoming.name)).right,
      lessThanOrEqualTo(theirs.left),
    );
  });

  testWidgets('a long press selects within one message, which copies whole '
      'after select all', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final room = _Room(tester);
    await room.open();
    await room.showChat();
    room
      ..say(_xiaoming, 'listen to this one')
      ..say(_me, 'next please');
    await room.deliver();

    await tester.longPress(find.text('listen to this one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, 'listen to this one');
  });

  testWidgets('a selection in an own message is drawn in the ink of the '
      'brand fill, not the brand colour it sits on', (tester) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();
    room
      ..say(_xiaoming, 'listen to this one')
      ..say(_me, 'next please');
    await room.deliver();

    final colors = AlistenColors.of(tester.element(find.byType(ChatView)));
    Color? selectionIn(String text) =>
        DefaultSelectionStyle.of(tester.element(find.text(text)))
            .selectionColor;
    expect(selectionIn('next please'), colors.onBrand.withValues(alpha: 0.35));
    expect(
      selectionIn('listen to this one'),
      isNot(selectionIn('next please')),
    );
  });

  testWidgets('查看更早的消息 sits above the oldest message shown', (tester) async {
    final room = _Room(tester);
    await room.open();
    for (var index = 0; index < 85; index++) {
      room.say(index.isEven ? _xiaoming : _me, '消息 $index');
    }
    await room.deliver();
    await room.showChat();

    await tester.scrollUntilVisible(
      find.text('查看更早的消息'),
      400,
      scrollable: _timelineScrollable,
    );
    await tester.pump();

    expect(find.text('消息 4'), findsNothing);
    expect(
      tester.getTopLeft(find.text('查看更早的消息')).dy,
      lessThan(tester.getTopLeft(find.text('消息 5')).dy),
    );
  });

  testWidgets('the send button stays quiet until there is something to send', (
    tester,
  ) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();
    final colors = AlistenColors.of(tester.element(find.byType(ChatView)));
    Color? disc() {
      final button = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.byIcon(AlistenIcons.arrowUpBold),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (button.decoration! as BoxDecoration).color;
    }

    expect(disc(), colors.glassFill);
    await tester.enterText(find.byType(TextField), '在吗');
    await tester.pump();
    expect(disc(), colors.brand);
    unawaited(room.transport.stop());
  });

  testWidgets('sending waits for the room to be connected', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = _Room(tester);
    await room.open();
    await room.showChat();

    room.transport.disconnect();
    await room.deliver();
    await tester.enterText(find.byType(TextField), '在吗');
    await tester.pump();

    expect(find.text('连接后可发送'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('发送')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(room.transport.requests, isEmpty);
    expect(_fieldText(tester), '在吗');

    semantics.dispose();
    unawaited(room.transport.stop());
  });

  testWidgets('a draft outlives switching to another mode and back', (
    tester,
  ) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();

    await tester.enterText(find.byType(TextField), '还没写完');
    await room.showOtherMode();
    expect(find.byType(TextField), findsNothing);
    await room.showChat();

    expect(_fieldText(tester), '还没写完');
  });

  testWidgets('the members of a room of 30 open in a sheet that scrolls '
      'without overflowing, someone on two devices listed once', (
    tester,
  ) async {
    final room = _Room(tester);
    // 同一用户从两台设备进入，每台设备一个会话。
    await room.open(
      members: [
        _me,
        _me,
        for (var index = 1; index < 30; index++)
          Member(id: 'm$index', name: '成员$index', avatarHash: ''),
      ],
    );
    await room.showChat();

    await tester.tap(find.text('31 人在线'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('房间成员'), findsOneWidget);
    final sheet = find.byType(SheetPanel);
    expect(
      find.descendant(of: sheet, matching: find.text('31 人在线')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('${_me.name}（我）')),
      findsOneWidget,
    );
    expect(find.text('2 台设备'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('成员29'),
      200,
      scrollable: find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('成员29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an activity reads as who did what, in the middle', (
    tester,
  ) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();

    room.emit(
      (seq) => RoomActivityEvent(
        term: 1,
        seq: seq,
        kind: RoomActivityKind.added,
        message: '点了《晴天》',
        member: _xiaoming,
      ),
    );
    await room.deliver();

    final activity = find.text('小明 点了《晴天》');
    expect(activity, findsOneWidget);
    final half = tester.getSize(find.byType(ChatView)).width / 2;
    // 文字在动态图标旁边，略微偏离正中。
    expect(
      (tester.getRect(activity).center.dx - half).abs(),
      lessThan(AlistenSizes.icon),
    );
  });

  testWidgets('a word still being composed is sent whole and once, by the '
      'button and by the send key', (tester) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();
    await tester.showKeyboard(find.byType(TextField));
    // Gboard 输入英文单词时，按空格之前一直处于组词状态。
    void type(String word) => tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: word,
        selection: TextSelection.collapsed(offset: word.length),
        composing: TextRange(start: 0, end: word.length),
      ),
    );

    type('hello');
    await tester.pump();
    await tester.tap(find.byIcon(AlistenIcons.arrowUpBold));
    await tester.pump();

    expect(room.transport.requests, hasLength(1));
    expect(room.transport.requests.single['data'], {'content': 'hello'});
    expect(_fieldText(tester), isEmpty);

    type('world');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(room.transport.requests, hasLength(2));
    expect(room.transport.requests.last['data'], {'content': 'world'});
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
  });

  testWidgets('the timeline fades row by row into its top edge only', (
    tester,
  ) async {
    final room = _Room(tester);
    await room.open();
    for (var index = 0; index < 40; index++) {
      room.say(index.isEven ? _xiaoming : _me, '消息 $index');
    }
    await room.deliver();
    await room.showChat();
    await tester.pumpAndSettle();
    expectFadedByRow(tester, find.byType(ChatView), top: true, bottom: false);

    await _readBackTo(tester, '消息 20');
    expectFadedByRow(tester, find.byType(ChatView), top: true, bottom: false);
  });

  testWidgets('lines arriving while history is read leave it in place and '
      'are counted', (tester) async {
    final room = _Room(tester);
    await room.open();
    for (var index = 0; index < 40; index++) {
      room.say(index.isEven ? _xiaoming : _me, '消息 $index');
    }
    await room.deliver();
    await room.showChat();
    final reading = await _readBackTo(tester, '消息 20');

    room
      ..say(_xiaoming, '新来的 1')
      ..say(_xiaoming, '新来的 2');
    await room.deliver();

    expect(tester.getTopLeft(find.text('消息 20')).dy, reading);
    expect(room.container.read(chatControllerProvider).unread, 2);
    expect(find.text('新消息 2 条'), findsOneWidget);
  });

  testWidgets('a hundred lines arriving while history is read do not pull '
      'the reader to the bottom', (tester) async {
    final room = _Room(tester);
    await room.open();
    for (var index = 0; index < 40; index++) {
      room.say(index.isEven ? _xiaoming : _me, '消息 $index');
    }
    await room.deliver();
    await room.showChat();
    final reading = await _readBackTo(tester, '消息 20');

    for (var index = 0; index < 100; index++) {
      room.say(_xiaoming, '新来的 $index');
    }
    await room.deliver();

    expect(tester.getTopLeft(find.text('消息 20')).dy, reading);
    expect(find.text('新来的 99'), findsNothing);
    expect(room.container.read(chatControllerProvider).unread, 100);
  });

  testWidgets('the composer counts down the last 50 characters', (
    tester,
  ) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();

    // 按字符计数而不是 UTF-16 码元：每个 emoji 占两个码元。
    await tester.enterText(find.byType(TextField), '😀' * 450);
    await tester.pump();
    expect(find.textContaining('还能输入'), findsNothing);

    await tester.enterText(find.byType(TextField), '😀' * 460);
    await tester.pump();
    expect(find.text('还能输入 40 字'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '😀' * 505);
    await tester.pump();
    expect(find.text('超出 5 字'), findsOneWidget);
  });

  testWidgets(
    '新消息 n 条 moves the timeline straight to the latest line, '
    'without overshooting it',
    // iOS 允许滚动越过终点再回弹。
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
    (tester) async {
      final room = _Room(tester);
      await room.open();
      for (var index = 0; index < 40; index++) {
        room.say(index.isEven ? _xiaoming : _me, '消息 $index');
      }
      await room.deliver();
      await room.showChat();
      await _readBackTo(tester, '消息 20');
      room
        ..say(_xiaoming, '新来的 1')
        ..say(_xiaoming, '新来的 2');
      await room.deliver();

      await tester.tap(find.text('新消息 2 条'));
      final ends = <double>[];
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final latest = find.text('新来的 2', skipOffstage: false);
        if (latest.evaluate().isNotEmpty) {
          ends.add(tester.getBottomLeft(latest).dy);
        }
      }

      final end = tester.getBottomLeft(find.text('新来的 2')).dy;
      expect(end, lessThanOrEqualTo(tester.getBottomLeft(_timeline).dy));
      expect(ends, isNotEmpty);
      for (var index = 1; index < ends.length; index++) {
        expect(ends[index], lessThanOrEqualTo(ends[index - 1] + 0.5));
      }
      expect(ends.every((dy) => dy >= end - 0.5), isTrue);
      expect(room.container.read(chatControllerProvider).unread, 0);
      expect(find.text('新消息 2 条'), findsNothing);
    },
  );

  testWidgets('dragging past the end of lines laid out below the fixed '
      'point tells the controller only between frames', (tester) async {
    final room = _Room(tester);
    await room.open();
    for (var index = 0; index < 40; index++) {
      room.say(index.isEven ? _xiaoming : _me, '消息 $index');
    }
    await room.deliver();
    await room.showChat();
    await _readBackTo(tester, '消息 5');
    // 各行高度差别很大，尚未布局的行的高度会估算错误。
    for (var index = 0; index < 100; index++) {
      room.say(_xiaoming, index < 3 ? '长消息 $index ${'啊' * 200}' : '短 $index');
    }
    await room.deliver();
    final midFrame = <bool>[];
    room.container.listen(
      chatControllerProvider.select((chat) => chat.atBottom),
      (_, atBottom) {
        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          midFrame.add(atBottom);
        }
      },
    );

    final drag = await tester.startGesture(tester.getCenter(_timeline));
    for (var step = 0; step < 60; step++) {
      await drag.moveBy(const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(midFrame, isEmpty);
    expect(room.container.read(chatControllerProvider).atBottom, isTrue);
    expect(find.text('短 99'), findsOneWidget);
  });

  for (final late in [false, true]) {
    testWidgets('a finger put down while the timeline moves to the latest '
        'line stops it there until lifted (${late ? 'near' : 'far from'} '
        'the end)', (tester) async {
      final room = _Room(tester);
      await room.open();
      for (var index = 0; index < 40; index++) {
        room.say(index.isEven ? _xiaoming : _me, '消息 $index');
      }
      await room.deliver();
      await room.showChat();
      await _readBackTo(tester, '消息 20');
      room
        ..say(_xiaoming, '新来的 1')
        ..say(_xiaoming, '新来的 2');
      await room.deliver();
      await tester.tap(find.text('新消息 2 条'));
      final position = tester
          .state<ScrollableState>(_timelineScrollable)
          .position;
      // 接近终点：最新一行已在算作底部的距离之内，但还没有完全进入视野。
      await tester.pump(const Duration(milliseconds: 100));
      while (late && position.extentBefore >= 60) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(position.extentBefore, greaterThan(0));

      final stopped = position.pixels;
      final finger = await tester.startGesture(tester.getCenter(_timeline));
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(position.pixels, stopped);
      }
      await finger.up();
      await tester.pumpAndSettle();

      // 接近终点时松手，剩余部分滚入视野；离终点很远时，时间线停在读者停下的
      // 位置。
      expect(find.text('新来的 2'), late ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
