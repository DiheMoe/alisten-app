import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/chat/application/chat_controller.dart';
import 'package:alisten/features/chat/application/chat_item.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory factory;
  late ProviderContainer container;
  late RoomController room;
  late ChatController chat;

  setUp(() async {
    api = FakeAlistenApi()
      ..rooms = [
        roomListing(id: 'room-id', slug: 'listen'),
        roomListing(id: 'room-two', slug: 'two'),
      ];
    credentials = FakeCredentialStore()
      ..tickets['room-id'] = 'saved-ticket'
      ..tickets['room-two'] = 'ticket-two';
    factory = FakeRoomTransportFactory();
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(api),
        credentialStoreProvider.overrideWithValue(credentials),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(),
      ],
    );
    room = container.read(roomControllerProvider.notifier);
    await room.openRoom('listen');
    factory.last.emitHello();
    await pumpEventQueue();
    chat = container.read(chatControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> receive(RoomEvent event) async {
    factory.last.emit(RoomEventReceived(event));
    await pumpEventQueue();
  }

  test('send trims the draft, refuses a second send while pending and keeps '
      'text typed meanwhile', () async {
    final completer = Completer<Map<String, Object?>>();
    factory.last.requestCompleter = completer;

    chat.setDraft('  你好  ');
    final first = chat.send();
    chat.setDraft('继续输入');
    final second = await chat.send();

    expect(second, isA<MutationNotSent<void>>());
    expect(factory.last.requests, hasLength(1));
    expect(factory.last.requests.single['data'], {'content': '你好'});
    expect(chat.state.sending, isTrue);

    completer.complete(const {});
    expect(await first, isA<MutationSucceeded<void>>());
    expect(chat.state.sending, isFalse);
    expect(chat.state.draft, '继续输入');
  });

  test('an empty draft is not sent', () async {
    chat.setDraft('   ');

    expect(await chat.send(), isA<MutationNotSent<void>>());
    expect(factory.last.requests, isEmpty);
  });

  test('300 emoji, 600 UTF-16 units, are within the limit and sent', () async {
    final content = '😀' * 300;
    chat.setDraft(content);

    expect(await chat.send(), isA<MutationSucceeded<void>>());
    expect(factory.last.requests.single['data'], {'content': content});
    expect(chat.state.sendError, isNull);
  });

  test('more than 500 characters is refused and says so until the draft is '
      'edited', () async {
    chat.setDraft('😀' * 501);

    final result = await chat.send();

    expect(
      result,
      isA<MutationNotSent<void>>().having(
        (r) => r.message,
        'message',
        '消息不能超过 500 字',
      ),
    );
    expect(chat.state.sendError, '消息不能超过 500 字');
    expect(chat.state.sending, isFalse);
    expect(chat.state.draft, '😀' * 501);
    expect(factory.last.requests, isEmpty);

    chat.setDraft('😀' * 500);
    expect(chat.state.sendError, isNull);
  });

  test(
    'unknown chat delivery is not a confirmed failure and is not resent',
    () async {
      factory.last.requestError = const RoomRequestException(
        code: null,
        message: '连接中断',
        outcome: RoomRequestOutcome.unknown,
      );
      chat.setDraft('可能已发送');

      final result = await chat.send();
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<void>>());
      expect(chat.state.sendError, contains('未知'));
      expect(chat.state.sendError, isNot(contains('消息发送失败')));
      expect(chat.state.draft, '可能已发送');
      expect(factory.last.requests, hasLength(1));
    },
  );

  test('a send that breaks unexpectedly ends sending, keeps the draft and is '
      'not resent', () async {
    factory.last.requestError = StateError('broken');
    chat.setDraft('可能已发送');

    final result = await chat.send();
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<void>>());
    expect(chat.state.sending, isFalse);
    expect(chat.state.draft, '可能已发送');
    expect(chat.state.sendError, contains('未知'));
    expect(factory.last.requests, hasLength(1));

    factory.last.requestError = null;
    expect(await chat.send(), isA<MutationSucceeded<void>>());
  });

  test('a rejected chat mutation shows the confirmed server failure', () async {
    factory.last.requestError = const RoomRequestException(
      code: 'FORBIDDEN',
      message: '不允许发言',
      outcome: RoomRequestOutcome.failed,
    );
    chat.setDraft('不能发送');

    final result = await chat.send();

    expect(result, isA<MutationFailed<void>>());
    expect(chat.state.sendError, contains('不允许发言'));
    expect(chat.state.sendError, isNot(contains('未知')));
  });

  test('the draft stays in the controller until its text is sent', () async {
    chat.setDraft('  草稿  ');
    expect(chat.state.draft, '  草稿  ');

    factory.last.requestError = const RoomRequestException(
      code: 'FORBIDDEN',
      message: '不允许发言',
      outcome: RoomRequestOutcome.failed,
    );
    await chat.send();
    expect(chat.state.draft, '  草稿  ');

    factory.last.requestError = null;
    await chat.send();
    expect(chat.state.draft, isEmpty);
  });

  test('timeline window, unread count and activity text follow the '
      'room notices', () async {
    for (var i = 1; i <= 81; i++) {
      await receive(
        ChatMessageEvent(
          term: 1,
          seq: i + 1,
          member: testMember,
          content: '消息 $i',
          sentAtMs: i,
        ),
      );
    }
    expect(chat.state.messages, hasLength(81));
    expect(chat.state.visibleCount, 80);
    expect(chat.state.atBottom, isTrue);
    expect(chat.state.unread, 0);

    chat.setAtBottom(false);
    await receive(
      const ChatMessageEvent(
        term: 1,
        seq: 83,
        member: testMember,
        content: '新消息',
        sentAtMs: 83,
      ),
    );
    expect(chat.state.unread, 1);
    final latest = chat.state.messages.last;
    expect(latest, isA<ChatMessageItem>());
    expect((latest as ChatMessageItem).text, '新消息');
    expect(latest.member, testMember);

    chat.showEarlier();
    expect(chat.state.visibleCount, 160);
    chat.setAtBottom(true);
    expect(chat.state.unread, 0);

    chat.setAtBottom(false);
    await receive(
      const RoomActivityEvent(
        term: 1,
        seq: 84,
        kind: RoomActivityKind.added,
        message: '点了《晴天》',
        member: testMember,
        entry: testQueueEntry,
      ),
    );
    await receive(
      const RoomActivityEvent(
        term: 1,
        seq: 85,
        kind: RoomActivityKind.added,
        message: '点了《雨天》',
      ),
    );
    expect(chat.state.unread, 2);
    final activities = chat.state.messages.reversed
        .take(2)
        .cast<ChatActivityItem>()
        .toList();
    expect(activities[1].text, '听众 点了《晴天》');
    expect(activities[0].text, '点了《雨天》');

    chat.markRead();
    expect(chat.state.unread, 0);
    expect(chat.state.atBottom, isFalse);
  });

  test('setAtBottom with an unchanged value does not notify', () async {
    var notifications = 0;
    container.listen(chatControllerProvider, (_, _) => notifications++);

    chat.setAtBottom(true);
    chat.setAtBottom(true);
    expect(notifications, 0);

    chat.setAtBottom(false);
    chat.setAtBottom(false);
    expect(notifications, 1);
    expect(chat.state.atBottom, isFalse);
  });

  test(
    'room changes unrelated to chat do not rebuild the chat state',
    () async {
      await receive(
        const ChatMessageEvent(
          term: 1,
          seq: 2,
          member: testMember,
          content: '你好',
          sentAtMs: 1,
        ),
      );
      final before = chat.state;
      var notifications = 0;
      container.listen(chatControllerProvider, (_, _) => notifications++);

      await receive(
        const MembersUpdatedEvent(
          term: 1,
          seq: 3,
          members: [testMember, testMember],
          onlineCount: 2,
        ),
      );
      await receive(
        const SettingsUpdatedEvent(
          term: 1,
          seq: 4,
          playMode: RoomPlayMode.random,
        ),
      );
      factory.last.disconnect();
      await pumpEventQueue();
      expect(room.state.status, RoomConnectionStatus.reconnecting);

      expect(notifications, 0);
      expect(chat.state, same(before));

      await receive(
        const ChatMessageEvent(
          term: 1,
          seq: 5,
          member: testMember,
          content: '再见',
          sentAtMs: 2,
        ),
      );
      expect(notifications, 1);
      expect(chat.state.messages, hasLength(2));
    },
  );

  test('a reconnect of the same room keeps the messages and changing rooms '
      'clears them', () async {
    await receive(
      const ChatMessageEvent(
        term: 1,
        seq: 2,
        member: testMember,
        content: '保留',
        sentAtMs: 1,
      ),
    );
    chat.setDraft('未发送');

    factory.last.disconnect();
    await pumpEventQueue();
    expect(room.state.status, RoomConnectionStatus.reconnecting);
    await room.checkConnection();
    factory.last.emitHello();
    await pumpEventQueue();
    expect(room.state.status, RoomConnectionStatus.open);

    expect(factory.transports, hasLength(1));
    expect(chat.state.messages, hasLength(1));
    expect(chat.state.draft, '未发送');

    await room.openRoom('two');
    expect(chat.state.messages, isEmpty);
    expect(chat.state.draft, isEmpty);
  });

  test('a failed track of the own request raises a notification, '
      'others do not', () async {
    // 服务端的失败动态不带成员，点歌人取自条目的 `by`。
    const message = '《歌曲》没能准备好：下载失败';
    const otherEntry = QueueEntry(
      id: 'other-entry',
      track: testTrack,
      meta: testTrackMeta,
      requestedBy: Member(id: 'other-id', name: '路人', avatarHash: ''),
      auto: false,
      likes: 0,
      status: QueueEntryStatus.preparing,
    );
    const autoEntry = QueueEntry(
      id: 'auto-entry',
      track: testTrack,
      meta: testTrackMeta,
      requestedBy: null,
      auto: true,
      likes: 0,
      status: QueueEntryStatus.preparing,
    );

    await receive(
      const RoomActivityEvent(
        term: 1,
        seq: 2,
        kind: RoomActivityKind.failed,
        message: message,
        entry: otherEntry,
      ),
    );
    await receive(
      const RoomActivityEvent(
        term: 1,
        seq: 3,
        kind: RoomActivityKind.failed,
        message: message,
        entry: autoEntry,
      ),
    );
    expect(chat.state.failureNotice, isNull);
    expect(chat.state.failureNoticeId, 0);

    await receive(
      const RoomActivityEvent(
        term: 1,
        seq: 4,
        kind: RoomActivityKind.failed,
        message: message,
        entry: testQueueEntry,
      ),
    );
    expect(chat.state.failureNotice, message);
    expect(chat.state.failureNoticeId, 1);

    await receive(
      const RoomActivityEvent(
        term: 1,
        seq: 5,
        kind: RoomActivityKind.added,
        message: '点了《歌曲》',
        entry: testQueueEntry,
      ),
    );
    expect(chat.state.failureNoticeId, 1);
  });
}
