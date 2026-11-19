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
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/glyph_cascade.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Future<void> open({
    List<Member> members = const [_me, _xiaoming],
    int capacity = 16,
  }) async {
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
        room: RoomInfo(
          id: 'room-id',
          name: '房间',
          description: '描述',
          kind: RoomKind.ephemeral,
          capacity: capacity,
        ),
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

  testWidgets('the members of a room of 30 unfold over the strip in a panel '
      'that scrolls without overflowing, someone on two devices listed once, '
      'and a push up folds it back', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = _Room(tester);
    // 同一用户从两台设备进入，每台设备一个会话。
    await room.open(
      members: [
        _me,
        _me,
        for (var index = 1; index < 30; index++)
          Member(id: 'm$index', name: '成员$index', avatarHash: ''),
      ],
      capacity: 64,
    );
    await room.showChat();
    final strip = tester.getRect(find.bySemanticsLabel(RegExp('查看房间成员')));

    await tester.tap(find.text('31 / 64 人在线'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_memberPanel).top, closeTo(strip.top, 0.5));
    expect(_shownCount(find.text('31 / 64 人在线')), 1);
    expect(
      find.descendant(of: _memberPanel, matching: find.text('31 / 64 人在线')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _memberPanel, matching: find.text('${_me.name}（我）')),
      findsOneWidget,
    );
    expect(find.text('2 台设备'), findsOneWidget);
    // 最多露出 5 行，下面还有人，下边缘渐隐。
    final list = find
        .descendant(of: _memberPanel, matching: find.byType(Scrollable))
        .first;
    final row = MemberList.rowExtent(tester.element(list));
    expect(tester.getSize(list).height, closeTo(5 * row, 0.5));
    EdgeFade fade() => tester.widget<EdgeFade>(
      find.descendant(of: _memberPanel, matching: find.byType(EdgeFade)),
    );
    expect(fade().top, 0);
    expect(fade().bottom, greaterThan(0));
    await tester.drag(list, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(fade().top, greaterThan(0));
    await tester.scrollUntilVisible(find.text('成员29'), 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(fade().bottom, 0);
    expect(find.text('成员29'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.bySemanticsLabel('收起成员'), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(_memberPanel, findsNothing);
    expect(_shownCount(find.text('31 / 64 人在线')), 1);
    semantics.dispose();
  });

  testWidgets('a room of two has a member list just two rows tall, with no '
      'fading edges', (tester) async {
    final room = _Room(tester);
    await room.open();
    await room.showChat();
    await tester.tap(find.text('2 / 16 人在线'));
    await tester.pumpAndSettle();

    final list = find
        .descendant(of: _memberPanel, matching: find.byType(Scrollable))
        .first;
    final row = MemberList.rowExtent(tester.element(list));
    expect(tester.getSize(list).height, closeTo(2 * row, 0.5));
    final fade = tester.widget<EdgeFade>(
      find.descendant(of: _memberPanel, matching: find.byType(EdgeFade)),
    );
    expect((fade.top, fade.bottom), (0.0, 0.0));
  });

  testWidgets('with the keyboard up the member panel stays above it', (
    tester,
  ) async {
    final room = _Room(tester);
    await room.open(
      members: [
        for (var index = 0; index < 30; index++)
          Member(id: 'm$index', name: '成员$index', avatarHash: ''),
      ],
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 420 * 3);
    addTearDown(tester.view.resetViewInsets);
    await room.showChat();
    await tester.tap(find.text('30 / 16 人在线'));
    await tester.pumpAndSettle();

    expect(tester.getRect(_memberPanel).bottom, lessThanOrEqualTo(780 - 420));
    expect(tester.takeException(), isNull);
  });

  group('the member panel', () {
    final eight = [
      _me,
      _xiaoming,
      for (var index = 1; index <= 6; index++)
        Member(id: 'm$index', name: '成员$index', avatarHash: ''),
    ];
    const count = '8 / 16 人在线';
    final flight = find.byKey(ValueKey('member-flight-${_me.id}'));
    Finder inPanel(Finder finder) =>
        find.descendant(of: _memberPanel, matching: finder);

    testWidgets('drops down from the strip without overshooting while the '
        'avatars travel to their rows and the count stays one', (tester) async {
      final room = _Room(tester);
      await room.open(members: eight);
      await room.showChat();
      final strip = tester.getRect(find.bySemanticsLabel(RegExp('查看房间成员')));
      final source = tester.getRect(find.byType(MemberAvatar).first);
      expect(_shownCount(find.text('+3')), 1);

      await tester.tap(find.text(count));
      await tester.pump();
      final heights = <double>[];
      final path = <Rect>[];
      for (var frame = 0; frame < 30; frame++) {
        expect(_shownCount(find.text(count)), 1);
        expect(tester.getRect(_memberPanel).top, closeTo(strip.top, 0.5));
        heights.add(tester.getRect(_memberPanel).height);
        if (flight.evaluate().isNotEmpty) path.add(tester.getRect(flight));
        await tester.pump(_frame);
      }
      await tester.pumpAndSettle();

      final full = tester.getRect(_memberPanel).height;
      final row = tester.getRect(inPanel(find.byType(MemberAvatar)).first);
      expect(heights.first, closeTo(strip.height, 1));
      for (var index = 1; index < heights.length; index++) {
        expect(heights[index], greaterThanOrEqualTo(heights[index - 1]));
        expect(heights[index], lessThanOrEqualTo(full + 0.01));
      }
      expect(path.first.center, _near(source.center));
      expect(path.first.width, closeTo(source.width, 0.5));
      final midway = path[6];
      expect(
        midway.center.dy,
        inExclusiveRange(source.center.dy, row.center.dy),
      );
      expect(midway.width, greaterThan(source.width));
      expect(path.last.center, _near(row.center));
      expect(flight, findsNothing);
      expect(_shownCount(find.text('+3')), 0);
      expect(_shownCount(find.text(count)), 1);
    });

    testWidgets('sets the avatars off one after another', (tester) async {
      final room = _Room(tester);
      await room.open(members: eight);
      await room.showChat();
      final from = [
        for (var index = 0; index < 2; index++)
          tester.getRect(find.byType(MemberAvatar).at(index)).center.dy,
      ];
      final flights = [
        flight,
        find.byKey(ValueKey('member-flight-${_xiaoming.id}')),
      ];

      await tester.tap(find.text(count));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final midway = [
        for (final flight in flights) tester.getRect(flight).center.dy,
      ];
      await tester.pumpAndSettle();
      final to = [
        for (var index = 0; index < 2; index++)
          tester
              .getRect(inPanel(find.byType(MemberAvatar)).at(index))
              .center
              .dy,
      ];

      double travelled(int index) =>
          (midway[index] - from[index]) / (to[index] - from[index]);
      expect(travelled(0), greaterThan(travelled(1) + 0.05));
    });

    testWidgets('pops the names up character by character after the '
        'avatars, the top rows first', (tester) async {
      final room = _Room(tester);
      await room.open(members: eight);
      await room.showChat();
      final me = find.text('${_me.name}（我）');

      await tester.tap(find.text(count));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(_shownCount(me), 0);

      await tester.pump(const Duration(milliseconds: 180));
      expect(_shownCount(find.text('小明')), 1);
      expect(
        _cascadeOf(tester, find.text('小明')),
        inExclusiveRange(0, glyphCascadeSeconds),
      );
      expect(_shownCount(find.text('成员5')), 0);

      // 头像落了地就交给列表那一行，昵称还在一个字一个字地出来。
      await tester.pump(const Duration(milliseconds: 90));
      expect(flight, findsNothing);
      expect(_opacityOf(inPanel(find.byType(MemberAvatar)).first), 1);
      expect(_cascadeOf(tester, me), lessThan(glyphCascadeSeconds));

      await tester.pumpAndSettle();
      for (final name in ['小明', '成员5', '成员6']) {
        expect(_shownCount(find.text(name)), 1);
        expect(
          _cascadeOf(tester, find.text(name)),
          greaterThanOrEqualTo(glyphCascadeSeconds),
        );
      }
      expect(_shownCount(me), 1);
    });

    testWidgets('folding back by a tap on its title, the names fade out first '
        'and then the avatars fly home', (tester) async {
      final room = _Room(tester);
      await room.open(members: eight);
      await room.showChat();
      final source = tester.getRect(find.byType(MemberAvatar).first);
      await tester.tap(find.text(count));
      await tester.pumpAndSettle();
      final row = tester.getRect(inPanel(find.byType(MemberAvatar)).first);

      await tester.tap(inPanel(find.text(count)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_opacityOf(inPanel(find.text('小明'))), inExclusiveRange(0, 1));
      expect(tester.getRect(flight).center, _near(row.center, within: 2));

      await tester.pump(const Duration(milliseconds: 100));
      expect(_opacityOf(inPanel(find.text('小明'))), 0);
      expect(
        tester.getRect(flight).center.dy,
        inExclusiveRange(source.center.dy, row.center.dy),
      );

      await tester.pumpAndSettle();
      expect(_memberPanel, findsNothing);
      expect(_shownCount(find.text(count)), 1);
      expect(_shownCount(find.text('+3')), 1);
      expect(tester.getRect(find.byType(MemberAvatar).first), source);
    });

    testWidgets('an avatar whose row was scrolled away comes home by fading '
        'in on the strip', (tester) async {
      final room = _Room(tester);
      await room.open(
        members: [
          _me,
          for (var index = 1; index < 30; index++)
            Member(id: 'm$index', name: '成员$index', avatarHash: ''),
        ],
        capacity: 64,
      );
      await room.showChat();
      final source = tester.getRect(find.byType(MemberAvatar).first);
      await tester.tap(find.text('30 / 64 人在线'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('成员29'),
        200,
        scrollable: inPanel(find.byType(Scrollable)).first,
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(flight).center, _near(source.center));
      expect(_opacityOf(flight), inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(_memberPanel, findsNothing);
    });

    testWidgets('a tap outside folds it without reaching the page', (
      tester,
    ) async {
      final room = _Room(tester);
      await room.open(members: eight);
      await room.showChat();
      await tester.tap(find.text(count));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(180, 700));
      await tester.pumpAndSettle();
      expect(_memberPanel, findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.testTextInput.hasAnyClients,
        isFalse,
        reason: 'the tap did not reach the composer',
      );
    });

    testWidgets('without animations the panel is simply there and simply '
        'gone', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final room = _Room(tester);
      await room.open(members: eight);
      await room.showChat();

      await tester.tap(find.text(count));
      await tester.pump();
      final height = tester.getRect(_memberPanel).height;
      expect(flight, findsNothing);
      expect(_shownCount(find.text('成员6')), 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(_memberPanel).height, height);

      await tester.tap(inPanel(find.text(count)));
      await tester.pump();
      expect(_memberPanel, findsNothing);
      expect(_shownCount(find.text(count)), 1);
    });
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

  group('sending', () {
    // 飞行逐帧推进，一次长时间的 pump 只有一帧。
    Future<void> frames(WidgetTester tester, Duration duration) async {
      for (var left = duration; left > Duration.zero; left -= _frame) {
        await tester.pump(_frame);
      }
    }

    Future<List<Completer<Map<String, Object?>>>> holdAnswers(
      _Room room,
    ) async {
      final answers = <Completer<Map<String, Object?>>>[];
      room.transport.requestHandler = (type, data) {
        final answer = Completer<Map<String, Object?>>();
        answers.add(answer);
        return answer.future;
      };
      return answers;
    }

    testWidgets('the whole input box flies off into its bubble, which then '
        'spins until the room has it', (tester) async {
      final semantics = tester.ensureSemantics();
      final room = _Room(tester);
      await room.open();
      await room.showChat();
      final answers = await holdAnswers(room);

      await tester.enterText(find.byType(TextField), '飞过去');
      await tester.pump();
      final typed = tester.getRect(find.byType(EditableText));
      final box = find
          .ancestor(
            of: find.byType(TextField),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final boxRect = tester.getRect(box);
      final boxLook =
          tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
      await tester.tap(find.bySemanticsLabel('发送'));
      await tester.pump();

      expect(_fieldText(tester), isEmpty);
      final copies = find.text('飞过去');
      expect(copies, findsNWidgets(2));
      // 飞行中的气泡从输入框里那段文字的位置出发，时间线上的气泡先藏着。
      expect(
        (tester.getRect(copies.last).center.dy - typed.center.dy).abs(),
        lessThan(24),
      );
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(of: copies.first, matching: find.byType(Opacity))
                  .first,
            )
            .opacity,
        0,
      );

      // 飞出去的是整个输入框：同样的位置、圆角和底色。原处的输入框先藏着，
      // 键盘留着。
      BoxDecoration frameOf(Finder text) =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(of: text, matching: find.byType(DecoratedBox))
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      final frame = find
          .ancestor(of: copies.last, matching: find.byType(DecoratedBox))
          .first;
      expect(tester.getRect(frame).topLeft, _near(boxRect.topLeft));
      expect(tester.getRect(frame).bottomRight, _near(boxRect.bottomRight));
      expect(frameOf(copies.last).color, boxLook.color);
      expect(frameOf(copies.last).borderRadius, boxLook.borderRadius);
      expect(_opacityOf(find.byType(TextField)), 0);
      expect(_hasFocus(tester), isTrue);
      final takeoffHeight = tester.getRect(copies.last).height;

      // 飞行中的文字与气泡里的一样，不带缺少 Material 时的下划线。
      final flying = tester.renderObject<RenderParagraph>(copies.last);
      expect(
        flying.text.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
      );

      // 起飞不久：底色正从输入框的颜色变成气泡的颜色，文字大小不变。
      await frames(tester, const Duration(milliseconds: 48));
      final colors = AlistenColors.of(tester.element(find.byType(TextField)));
      expect(frameOf(copies.last).color, isNot(boxLook.color));
      expect(frameOf(copies.last).color, isNot(colors.brand));
      expect(tester.getRect(copies.last).height, closeTo(takeoffHeight, 0.5));

      await frames(tester, const Duration(milliseconds: 102));
      final midway = tester.getRect(copies.last).center.dy;
      expect(midway, lessThan(typed.center.dy - 24));
      expect(tester.getRect(copies.last).height, closeTo(takeoffHeight, 0.5));
      // 新的空输入框正展开出现。
      final returning = _opacityOf(find.byType(TextField));
      expect(returning, inExclusiveRange(0, 1));
      expect(_scaleOf(tester, find.byType(TextField)), lessThan(1));

      await frames(tester, const Duration(seconds: 1));
      expect(find.text('飞过去'), findsOneWidget);
      expect(_opacityOf(find.byType(TextField)), 1);
      expect(_scaleOf(tester, find.byType(TextField)), 1);
      expect(_hasFocus(tester), isTrue);
      expect(find.byType(BusyIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('发送中'), findsOneWidget);
      expect(find.text('发送中'), findsNothing);
      // 发送按钮不转圈，可以接着发下一条。
      expect(
        find.descendant(
          of: find.bySemanticsLabel('发送'),
          matching: find.byType(BusyIndicator),
        ),
        findsNothing,
      );

      answers.single.complete(const {});
      room.say(_me, '飞过去');
      await room.deliver();
      expect(find.text('飞过去'), findsOneWidget);
      expect(find.byType(BusyIndicator), findsNothing);

      semantics.dispose();
      unawaited(room.transport.stop());
    });

    testWidgets('the time over a new message waits for it to land and comes '
        'in with it', (tester) async {
      final room = _Room(tester);
      await room.open();
      await room.showChat();
      await holdAnswers(room);

      await tester.enterText(find.byType(TextField), '几点了');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('发送'));
      await tester.pump();
      final time = find.textContaining(RegExp(r'\d{2}:\d{2}'));
      expect(time, findsOneWidget);
      expect(_opacityOf(time), 0);

      await frames(tester, const Duration(milliseconds: 150));
      expect(_opacityOf(time), 0);
      await frames(tester, const Duration(seconds: 1));
      expect(_opacityOf(time), 1);
      unawaited(room.transport.stop());
    });

    testWidgets('a message the room confirms mid-flight stays hidden in the '
        'timeline until the flight has landed, its avatar until the flight '
        'has reached it', (tester) async {
      final room = _Room(tester);
      await room.open();
      await room.showChat();
      final answers = await holdAnswers(room);

      await tester.enterText(find.byType(TextField), '很快就到');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('发送'));
      await tester.pump();
      answers.single.complete(const {});
      room.say(_me, '很快就到');
      await room.deliver();

      final copies = find.text('很快就到');
      final avatar = find.descendant(
        of: _timeline,
        matching: find.byType(MemberAvatar),
      );
      expect(avatar, findsOneWidget);
      Rect frameOf(Finder text) => tester.getRect(
        find.ancestor(of: text, matching: find.byType(DecoratedBox)).first,
      );
      var checked = 0;
      var reached = false;
      var avatarBeforeLanding = false;
      // 时间线上的那一份排在飞行的几份之前。
      for (var i = 0; i < 60 && copies.evaluate().length > 1; i++) {
        expect(_opacityOf(copies.first), 0);
        expect(find.byType(BusyIndicator), findsNothing);
        // 飞行从下往上：外框顶边到了气泡的顶边就算到了。
        reached |= frameOf(copies.last).top <= frameOf(copies.first).top + 0.5;
        if (!reached) expect(_opacityOf(avatar), 0);
        if (_opacityOf(avatar) > 0) avatarBeforeLanding = true;
        checked++;
        await tester.pump(_frame);
      }
      expect(checked, greaterThan(10), reason: 'the flight was looked at');
      expect(avatarBeforeLanding, isTrue);
      await frames(tester, const Duration(seconds: 1));
      expect(copies, findsOneWidget);
      expect(_opacityOf(copies), 1);
      expect(_opacityOf(avatar), 1);
      unawaited(room.transport.stop());
    });

    testWidgets('a message the room refuses says why, and its mark offers to '
        'send it again or drop it', (tester) async {
      final semantics = tester.ensureSemantics();
      final room = _Room(tester);
      await room.open();
      await room.showChat();
      room.transport.requestError = const RoomRequestException(
        code: 'FORBIDDEN',
        message: '不允许发言',
        outcome: RoomRequestOutcome.failed,
      );

      await tester.enterText(find.byType(TextField), '不能发');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('发送'));
      await tester.pump();
      await frames(tester, const Duration(seconds: 1));

      expect(find.text('不允许发言'), findsOneWidget);
      expect(find.byType(BusyIndicator), findsNothing);

      room.transport.requestError = null;
      await tester.tap(find.bySemanticsLabel('没有发出，重发或删除'));
      await frames(tester, const Duration(milliseconds: 600));
      await tester.tap(find.text('重发'));
      await frames(tester, const Duration(milliseconds: 600));
      expect(room.transport.requests, hasLength(2));
      expect(find.text('不允许发言'), findsNothing);

      semantics.dispose();
      unawaited(room.transport.stop());
    });

    testWidgets('a long message leaves exactly as the input showed it, '
        'within the input, and lands as its bubble', (tester) async {
      final room = _Room(tester);
      await room.open();
      // 矮一点的屏幕，消息的气泡比时间线还高。
      tester.view.physicalSize = const Size(360, 600) * 3;
      await room.showChat();
      await holdAnswers(room);
      final long = '很长的消息' * 99;

      await tester.enterText(find.byType(TextField), long);
      await tester.pump();
      final input = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final field = MatrixUtils.transformRect(
        input.getTransformTo(null),
        Offset.zero & input.size,
      );
      final lines = input.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: long.length),
      );
      final firstLine = MatrixUtils.transformRect(
        input.getTransformTo(null),
        lines.first.toRect(),
      );
      await tester.tap(find.bySemanticsLabel('发送'));
      await tester.pump();

      // 起飞那一帧：飞出的文字按输入框的宽度排，第一行仍在原处，不超出输入框。
      final flying = find.text(long).last;
      final paragraph = tester.renderObject<RenderParagraph>(flying);
      final firstBox = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: long.length),
            )
            .first
            .toRect(),
      );
      expect(firstBox.left, closeTo(firstLine.left, 1));
      expect(firstBox.top, closeTo(firstLine.top, 1));
      expect(firstBox.width, closeTo(firstLine.width, 1));
      final clip = tester.getRect(
        find.ancestor(of: flying, matching: find.byType(ClipRRect)).first,
      );
      expect(clip.top, greaterThanOrEqualTo(field.top - 12));
      expect(clip.bottom, lessThanOrEqualTo(field.bottom + 12));

      // 消息比时间线还高时，飞行也只画在时间线和输入框里，不盖住上面的
      // 成员条和房间顶栏。
      final timelineTop = tester.getTopLeft(_timeline).dy;
      var checked = 0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(_frame);
        if (find.text(long).evaluate().length < 2) break;
        final flying = find.text(long).last;
        // 画出来的部分裁在时间线以内；外框落地时的回弹只多出几个像素。
        final drawn = find.ancestor(
          of: flying,
          matching: find.byType(ClipRect),
        );
        expect(
          tester.getRect(drawn.first).top,
          greaterThanOrEqualTo(timelineTop - 1),
        );
        final frame = find.ancestor(
          of: flying,
          matching: find.byType(ClipRRect),
        );
        expect(
          tester.getRect(frame.first).top,
          greaterThanOrEqualTo(timelineTop - 8),
        );
        checked++;
      }
      expect(checked, greaterThan(5), reason: 'the flight was looked at');

      await frames(tester, const Duration(seconds: 1));
      expect(find.text(long), findsOneWidget);
      unawaited(room.transport.stop());
    });

    testWidgets('without animations the bubble is simply there', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final room = _Room(tester);
      await room.open();
      await room.showChat();
      await holdAnswers(room);

      await tester.enterText(find.byType(TextField), '直接出现');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('发送'));
      await tester.pump();

      expect(_fieldText(tester), isEmpty);
      expect(_opacityOf(find.byType(TextField)), 1);
      expect(find.text('直接出现'), findsOneWidget);
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(
                of: find.text('直接出现'),
                matching: find.byType(Opacity),
              ),
            )
            .every((opacity) => opacity.opacity > 0),
        isTrue,
      );
      unawaited(room.transport.stop());
    });
  });
}

const _frame = Duration(milliseconds: 16);

final _memberPanel = find.byKey(const ValueKey('member-panel'));

// 各层 [Opacity] 和 [FadeTransition] 相乘后的不透明度。
double _opacityOf(Finder finder) {
  var opacity = 1.0;
  finder.evaluate().single.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity) opacity *= widget.opacity;
    if (widget is FadeTransition) opacity *= widget.opacity.value;
    return true;
  });
  return opacity;
}

bool _hasFocus(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

// 最近一层 [Transform] 的横向缩放。
double _scaleOf(WidgetTester tester, Finder finder) => tester
    .widget<Transform>(
      find.ancestor(of: finder, matching: find.byType(Transform)).first,
    )
    .transform
    .entry(0, 0);

// 文字所在那一行开始逐字显出后过了几秒。
double _cascadeOf(WidgetTester tester, Finder text) => tester
    .widget<GlyphCascade>(
      find.ancestor(of: text, matching: find.byType(GlyphCascade)),
    )
    .elapsed;

// 画得出来的几处：不在不透明度为 0 的部件里。
int _shownCount(Finder finder) => finder.evaluate().where((element) {
  var shown = true;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity && widget.opacity == 0) shown = false;
    return shown;
  });
  return shown;
}).length;

Matcher _near(Offset point, {double within = 0.5}) => isA<Offset>()
    .having((p) => p.dx, 'dx', closeTo(point.dx, within))
    .having((p) => p.dy, 'dy', closeTo(point.dy, within));
