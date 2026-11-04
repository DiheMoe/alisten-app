import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:alisten/core/clock/server_clock.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/core/realtime/websocket_room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_web_socket_channel.dart';

void main() {
  test('hello is the first frame with exact protocol and ping runs every five seconds', () {
    fakeAsync((async) {
      final fake = _FakeTransport();
      fake.start(async);
      final channel = fake.channels.single;

      expect(fake.uri.scheme, 'wss');
      expect(fake.uri.path, '/ws');
      expect(channel.messages, hasLength(1));
      final hello = jsonDecode(channel.messages.single) as Map<String, Object?>;
      expect(hello['kind'], 'request');
      expect(hello['type'], 'hello');
      expect(hello['data'], {
        'roomId': 'room-id',
        'ticket': 'ticket',
        'protocolVersion': '473ee31f5ef912b4',
      });

      channel.receive(_response(hello['id']! as String, 'hello', _helloData()));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));

      final ping = jsonDecode(channel.messages.last) as Map<String, Object?>;
      expect(ping['type'], 'ping');
      expect(
        (ping['data']! as Map<String, Object?>)['clientTimeMs'],
        isA<int>(),
      );
      unawaited(fake.transport.stop());
    });
  });

  test('responses can complete out of order and events may precede command responses', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final channel = fake.channels.single;
      final events = <RoomTransportEvent>[];
      final subscription = fake.transport.events.listen(events.add);
      Map<String, Object?>? first;
      Map<String, Object?>? second;
      unawaited(
        fake.transport
            .request('queue.remove', {'entryId': 'one'})
            .then((value) => first = value),
      );
      unawaited(
        fake.transport
            .request('queue.like', {'entryId': 'two'})
            .then((value) => second = value),
      );
      final removeId = _lastRequestId(channel, 'queue.remove');
      final likeId = _lastRequestId(channel, 'queue.like');

      channel.receive(_response(likeId, 'queue.like', {'likes': 3}));
      channel.receive(_event('settings.updated', 1, 2, {'playMode': 'random'}));
      channel.receive(_response(removeId, 'queue.remove', {}));
      _answerPing(channel);
      async.flushMicrotasks();

      expect(second, {'likes': 3});
      expect(first, isEmpty);
      expect(
        events.whereType<RoomEventReceived>().single.event,
        isA<SettingsUpdatedEvent>(),
      );
      expect(fake.transport.clock.serverNow(), isNotNull);
      unawaited(subscription.cancel());
      unawaited(fake.transport.stop());
    });
  });

  test('events before the hello response are covered by its snapshot and not reapplied', () {
    fakeAsync((async) {
      final fake = _FakeTransport();
      final events = <RoomTransportEvent>[];
      final subscription = fake.transport.events.listen(events.add);
      unawaited(fake.transport.start());
      async.flushMicrotasks();
      final channel = fake.channels.single;
      final helloId = _lastRequestId(channel, 'hello');

      channel.receive(_event('settings.updated', 1, 2, {'playMode': 'random'}));
      channel.receive(_response(helloId, 'hello', _helloData()));
      async.flushMicrotasks();

      expect(events.whereType<RoomEventReceived>(), isEmpty);
      final hello = events.whereType<RoomHelloReceived>().single.hello;
      expect(hello.room.room.id, 'room-id');
      expect(hello.member.id, 'member-id');
      unawaited(subscription.cancel());
      unawaited(fake.transport.stop());
    });
  });

  test('disconnect rejects pending requests as unknown and reconnects with exponential backoff', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final firstChannel = fake.channels.single;
      final failure = _failureOf(fake.transport.request('queue.like', {}));

      firstChannel.serverClose(1012);
      async.flushMicrotasks();

      expect(failure.value?.outcome, RoomRequestOutcome.unknown);
      expect(fake.channels, hasLength(1));
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(fake.channels, hasLength(2));
      unawaited(fake.transport.stop());
    });
  });

  test('request timeout has an unknown outcome and is not replayed', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final channel = fake.channels.single;
      final failure = _failureOf(
        fake.transport.request('queue.add', {'track': _trackData()}),
      );

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();

      expect(failure.value?.outcome, RoomRequestOutcome.unknown);
      expect(
        channel.messages.where((message) => message.contains('queue.add')),
        hasLength(1),
      );
      unawaited(fake.transport.stop());
    });
  });

  test('an error response fails its request with the server error code', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final channel = fake.channels.single;
      final failure = _failureOf(
        fake.transport.request('queue.remove', {'entryId': 'entry'}),
      );
      async.flushMicrotasks();

      channel.receive(
        _errorResponse(
          _lastRequestId(channel, 'queue.remove'),
          'queue.remove',
          'FORBIDDEN',
          '不能删除别人点的歌',
        ),
      );
      async.flushMicrotasks();

      expect(
        failure.value,
        isA<RoomRequestException>()
            .having((error) => error.code, 'code', 'FORBIDDEN')
            .having((error) => error.message, 'message', '不能删除别人点的歌')
            .having(
              (error) => error.outcome,
              'outcome',
              RoomRequestOutcome.failed,
            ),
      );
      unawaited(fake.transport.stop());
    });
  });

  test('UNAVAILABLE and INTERNAL leave a mutation unknown but fail a read', () {
    final cases = [
      ('queue.like', 'UNAVAILABLE', RoomRequestOutcome.unknown),
      ('queue.like', 'INTERNAL', RoomRequestOutcome.unknown),
      ('queue.like', 'RATE_LIMITED', RoomRequestOutcome.failed),
      ('search.tracks', 'UNAVAILABLE', RoomRequestOutcome.failed),
      ('room.sync', 'INTERNAL', RoomRequestOutcome.failed),
    ];
    for (final (type, code, outcome) in cases) {
      fakeAsync((async) {
        final fake = _FakeTransport()..start(async, open: true);
        final channel = fake.channels.single;
        final failure = _failureOf(fake.transport.request(type, {}));

        channel.receive(
          _errorResponse(_lastRequestId(channel, type), type, code, '稍后再试'),
        );
        async.flushMicrotasks();

        expect(failure.value?.outcome, outcome, reason: '$type $code');
        expect(failure.value?.code, code);
        unawaited(fake.transport.stop());
      });
    }
  });

  test('a response with an id but an unreadable body fails at once', () {
    final cases = [
      (
        'search.tracks',
        {'kind': 'response', 'type': 'search.tracks'},
        RoomRequestOutcome.failed,
      ),
      (
        'search.tracks',
        {
          'kind': 'response',
          'type': 'search.tracks',
          'data': <String, Object?>{},
          'error': {'code': 'FUTURE_CODE', 'message': '新错误'},
        },
        RoomRequestOutcome.failed,
      ),
      (
        'queue.like',
        {
          'kind': 'response',
          'type': 'queue.like',
          'data': <String, Object?>{},
          'error': {'code': 'FUTURE_CODE', 'message': '新错误'},
        },
        RoomRequestOutcome.unknown,
      ),
    ];
    for (final (type, frame, outcome) in cases) {
      fakeAsync((async) {
        final fake = _FakeTransport()..start(async, open: true);
        final channel = fake.channels.single;
        final failure = _failureOf(fake.transport.request(type, {}));

        channel.receive(
          jsonEncode({...frame, 'id': _lastRequestId(channel, type)}),
        );
        async.flushMicrotasks();

        expect(
          failure.value,
          isA<RoomRequestException>()
              .having((error) => error.outcome, 'outcome', outcome)
              .having((error) => error.code, 'code', 'PROTOCOL_MISMATCH'),
          reason: jsonEncode(frame),
        );
        expect(fake.channels, hasLength(1));
        unawaited(fake.transport.stop());
      });
    }
  });

  test('an undecodable hello response stops as client outdated without reconnecting', () {
    final helloResponses = [
      {
        ..._helloData(),
        'room': {..._snapshotData(), 'playMode': 'shuffle'},
      },
      {'member': _helloData()['member'], 'serverTimeMs': 1000000},
    ];
    for (final data in helloResponses) {
      fakeAsync((async) {
        final fake = _FakeTransport();
        final events = <RoomTransportEvent>[];
        final subscription = fake.transport.events.listen(events.add);
        fake.start(async);
        final channel = fake.channels.single;

        channel.receive(
          _response(_lastRequestId(channel, 'hello'), 'hello', data),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));

        expect(events.whereType<RoomStopped>().single.code, 4426);
        expect(events.whereType<RoomHelloReceived>(), isEmpty);
        expect(fake.channels, hasLength(1));
        unawaited(subscription.cancel());
        unawaited(fake.transport.stop());
      });
    }
  });

  test('hello error responses map to their close codes', () {
    final cases = [
      ('UNAUTHORIZED', 4401),
      ('NOT_FOUND', 4404),
      ('CLIENT_OUTDATED', 4426),
      ('FUTURE_CODE', 4426),
    ];
    for (final (code, closeCode) in cases) {
      fakeAsync((async) {
        final fake = _FakeTransport();
        final events = <RoomTransportEvent>[];
        final subscription = fake.transport.events.listen(events.add);
        fake.start(async);
        final channel = fake.channels.single;

        channel.receive(
          _errorResponse(_lastRequestId(channel, 'hello'), 'hello', code, '拒绝'),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));

        expect(events.whereType<RoomStopped>().single.code, closeCode);
        expect(fake.channels, hasLength(1), reason: code);
        if (code == 'FUTURE_CODE') {
          expect(
            events.whereType<RoomErrorReceived>().single.message,
            allOf(contains('协议不兼容'), isNot(contains('结果未知'))),
          );
        }
        unawaited(subscription.cancel());
        unawaited(fake.transport.stop());
      });
    }
    fakeAsync((async) {
      final fake = _FakeTransport();
      fake.start(async);
      final channel = fake.channels.single;

      channel.receive(
        _errorResponse(
          _lastRequestId(channel, 'hello'),
          'hello',
          'INTERNAL',
          '内部错误',
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));

      expect(fake.channels, hasLength(2));
      unawaited(fake.transport.stop());
    });
  });

  test('a hello without a response for ten seconds reconnects', () {
    fakeAsync((async) {
      final fake = _FakeTransport();
      final events = <RoomTransportEvent>[];
      final subscription = fake.transport.events.listen(events.add);
      fake.start(async);
      final channel = fake.channels.single;

      async.elapse(const Duration(milliseconds: 9999));
      expect(channel.webSocketSink.closeCalls, 0);
      async.elapse(const Duration(milliseconds: 1));

      expect(channel.webSocketSink.closeCalls, 1);
      expect(
        events.whereType<RoomConnectionChanged>().last.status,
        RoomConnectionStatus.reconnecting,
      );
      async.elapse(const Duration(seconds: 3));
      expect(fake.channels, hasLength(2));
      unawaited(subscription.cancel());
      unawaited(fake.transport.stop());
    });
  });

  test(
    'backoff grows 3/6/12/24/30 seconds with jitter and resets after hello',
    () {
      fakeAsync((async) {
        final fake = _FakeTransport(random: Random(7))..connectFails = true;
        final events = <RoomTransportEvent>[];
        final subscription = fake.transport.events.listen(events.add);
        fake.start(async);

        final delays = <Duration>[];
        for (final base in [3, 6, 12, 24, 30, 30]) {
          final delay = events.whereType<RoomConnectionChanged>().last.retryIn!;
          expect(delay, _within20Percent(base), reason: '$base s');
          delays.add(delay);
          final attempts = fake.channels.length;
          async.elapse(delay - const Duration(milliseconds: 1));
          expect(fake.channels, hasLength(attempts));
          async.elapse(const Duration(milliseconds: 1));
          expect(fake.channels, hasLength(attempts + 1));
        }
        expect(delays.toSet(), hasLength(delays.length));

        fake.connectFails = false;
        async.elapse(events.whereType<RoomConnectionChanged>().last.retryIn!);
        final channel = fake.channels.last;
        channel.receive(
          _response(_lastRequestId(channel, 'hello'), 'hello', _helloData()),
        );
        async.flushMicrotasks();
        channel.serverClose(1012);
        async.flushMicrotasks();

        expect(
          events.whereType<RoomConnectionChanged>().last.retryIn,
          _within20Percent(3),
        );
        unawaited(subscription.cancel());
        unawaited(fake.transport.stop());
      });
    },
  );

  test('check connects at once during backoff and restart keeps a connection that is not ready', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      fake.channels.single.serverClose(1012);
      async.flushMicrotasks();
      expect(fake.channels, hasLength(1));

      fake.transport.check();
      async.flushMicrotasks();
      expect(fake.channels, hasLength(2));
      final connecting = fake.channels.last;

      fake.transport.restart();
      fake.transport.check();
      async.flushMicrotasks();

      expect(connecting.webSocketSink.closeCalls, 0);
      expect(fake.channels, hasLength(2));

      connecting.receive(
        _response(_lastRequestId(connecting, 'hello'), 'hello', _helloData()),
      );
      async.flushMicrotasks();
      fake.transport.restart();
      expect(connecting.webSocketSink.closeCalls, 1);
      async.elapse(const Duration(seconds: 3));
      expect(fake.channels, hasLength(3));
      unawaited(fake.transport.stop());
    });
  });

  test('probe drops a silent connection after its deadline', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final channel = fake.channels.single;
      final events = <RoomTransportEvent>[];
      final subscription = fake.transport.events.listen(events.add);

      fake.transport.probe(const Duration(seconds: 5));
      async.elapse(const Duration(milliseconds: 4999));
      expect(channel.webSocketSink.closeCalls, 0);
      async.elapse(const Duration(milliseconds: 1));

      expect(channel.webSocketSink.closeCalls, 1);
      expect(
        events.whereType<RoomConnectionChanged>().last.status,
        RoomConnectionStatus.reconnecting,
      );
      async.elapse(const Duration(seconds: 3));
      expect(fake.channels, hasLength(2));
      unawaited(subscription.cancel());
      unawaited(fake.transport.stop());
    });
  });

  test('probe keeps a connection that answers its ping', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final channel = fake.channels.single;

      fake.transport.probe(const Duration(seconds: 5));
      _answerPing(channel);
      async.elapse(const Duration(seconds: 6));

      expect(channel.webSocketSink.closeCalls, 0);
      expect(fake.channels, hasLength(1));
      unawaited(fake.transport.stop());
    });
  });

  test('a request whose data cannot be encoded is not sent and keeps the connection', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final channel = fake.channels.single;

      final failure = _failureOf(
        fake.transport.request('queue.like', {'entryId': Object()}),
      );
      async.flushMicrotasks();

      expect(failure.value?.outcome, RoomRequestOutcome.notSent);
      expect(channel.webSocketSink.closeCalls, 0);
      unawaited(fake.transport.request('queue.like', {'entryId': 'entry'}));
      expect(_lastRequestId(channel, 'queue.like'), isNotEmpty);
      unawaited(fake.transport.stop());
    });
  });

  test(
    'idle read timeout re-evaluates the connection even while pings are sent',
    () {
      fakeAsync((async) {
        final fake = _FakeTransport()..start(async, open: true);
        final channel = fake.channels.single;
        final before = channel.messages.length;

        async.elapse(const Duration(seconds: 28));
        async.flushMicrotasks();

        expect(channel.messages.length, greaterThan(before));
        expect(fake.channels, hasLength(2));
        unawaited(fake.transport.stop());
      });
    },
  );

  test(
    'handshake timeout enters reconnecting instead of marking the room open',
    () {
      fakeAsync((async) {
        final channel = FakeWebSocketChannel(ready: Completer<void>().future);
        final fake = _FakeTransport(channel: channel);
        final events = <RoomTransportEvent>[];
        final subscription = fake.transport.events.listen(events.add);
        unawaited(fake.transport.start());

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        expect(channel.messages, isEmpty);
        expect(
          events.whereType<RoomConnectionChanged>().last.status,
          RoomConnectionStatus.reconnecting,
        );
        unawaited(subscription.cancel());
        unawaited(fake.transport.stop());
      });
    },
  );

  test(
    'unrecoverable close codes stop and recoverable service codes reconnect',
    () {
      for (final code in [1008, 4401, 4404, 4426]) {
        fakeAsync((async) {
          final fake = _FakeTransport()..start(async, open: true);
          final events = <RoomTransportEvent>[];
          var closed = false;
          fake.transport.events.listen(events.add, onDone: () => closed = true);
          fake.channels.single.serverClose(code);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 31));

          expect(events.whereType<RoomStopped>().single.code, code);
          expect(fake.channels, hasLength(1));
          unawaited(fake.transport.stop());
          async.flushMicrotasks();
          expect(
            closed,
            isTrue,
            reason: 'stop() still closes the event stream',
          );
        });
      }
      for (final code in [1012, 1013]) {
        fakeAsync((async) {
          final fake = _FakeTransport()..start(async, open: true);
          fake.channels.single.serverClose(code);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();

          expect(fake.channels, hasLength(2));
          unawaited(fake.transport.stop());
        });
      }
    },
  );

  test('events from a replaced connection are dropped', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final first = fake.channels.single;
      final events = <RoomTransportEvent>[];
      final subscription = fake.transport.events.listen(events.add);

      async.elapse(const Duration(seconds: 28));
      final second = fake.channels.last;
      expect(second, isNot(same(first)));
      second.receive(
        _response(_lastRequestId(second, 'hello'), 'hello', _helloData()),
      );
      async.flushMicrotasks();
      first.receive(_event('settings.updated', 1, 2, {'playMode': 'random'}));
      async.flushMicrotasks();

      expect(events.whereType<RoomEventReceived>(), isEmpty);
      unawaited(subscription.cancel());
      unawaited(fake.transport.stop());
    });
  });

  test(
    'stop leaves written mutations unknown, fails reads and sends nothing more',
    () {
      fakeAsync((async) {
        final fake = _FakeTransport()..start(async, open: true);
        final mutation = _failureOf(fake.transport.request('queue.like', {}));
        final read = _failureOf(fake.transport.request('room.sync', {}));

        unawaited(fake.transport.stop());
        final late = _failureOf(fake.transport.request('queue.like', {}));
        async.flushMicrotasks();

        expect(mutation.value?.outcome, RoomRequestOutcome.unknown);
        expect(read.value?.outcome, RoomRequestOutcome.failed);
        expect(late.value?.outcome, RoomRequestOutcome.notSent);
      });
    },
  );

  test('hello time stands in for the clock until the first ping answer', () {
    fakeAsync((async) {
      var now = 1000;
      final fake = _FakeTransport(clock: ServerClock(now: () => now));
      fake.start(async);
      final channel = fake.channels.single;

      now = 1010;
      channel.receive(
        _response(_lastRequestId(channel, 'hello'), 'hello', {
          ..._helloData(),
          'serverTimeMs': 5000,
        }),
      );
      async.flushMicrotasks();
      expect(
        fake.transport.clock.serverNow(),
        5005,
        reason: 'available when the hello event is delivered',
      );

      now = 1210;
      _answerPing(channel, serverTimeMs: 9000);
      async.flushMicrotasks();

      expect(
        fake.transport.clock.serverNow(),
        9100,
        reason: 'a ping sample replaces the hello sample despite a larger RTT',
      );
      unawaited(fake.transport.stop());
    });
  });

  test('an unreadable room event is delivered as a position needing sync', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final events = <RoomTransportEvent>[];
      final subscription = fake.transport.events.listen(events.add);

      fake.channels.single.receive(
        _event('settings.updated', 1, 2, {'playMode': 'shuffle'}),
      );
      async.flushMicrotasks();

      expect(
        events.whereType<RoomEventReceived>().single.event,
        isA<UnreadableRoomEvent>()
            .having((event) => event.term, 'term', 1)
            .having((event) => event.seq, 'seq', 2),
      );
      unawaited(subscription.cancel());
      unawaited(fake.transport.stop());
    });
  });

  test('old connection events after stop cannot reach room listeners', () {
    fakeAsync((async) {
      final fake = _FakeTransport()..start(async, open: true);
      final channel = fake.channels.single;
      final events = <RoomTransportEvent>[];
      final subscription = fake.transport.events.listen(events.add);
      unawaited(fake.transport.stop());
      async.flushMicrotasks();
      events.clear();

      channel.receive(_event('settings.updated', 1, 2, {'playMode': 'random'}));
      async.flushMicrotasks();

      expect(events, isEmpty);
      unawaited(subscription.cancel());
    });
  });
}

Matcher _within20Percent(int seconds) {
  return isA<Duration>().having(
    (delay) => delay.inMicroseconds,
    'microseconds',
    inInclusiveRange(seconds * 800000, seconds * 1200000),
  );
}

final class _Failure {
  RoomRequestException? value;
}

_Failure _failureOf(Future<Object?> request) {
  final failure = _Failure();
  unawaited(
    request.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        failure.value = error as RoomRequestException;
      },
    ),
  );
  return failure;
}

// 浮动系数为 1.0，退避严格按 3/6/12/24/30 秒进行。
final class _MidpointRandom implements Random {
  @override
  double nextDouble() => 0.5;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}

final class _FakeTransport {
  _FakeTransport({
    FakeWebSocketChannel? channel,
    Random? random,
    ServerClock? clock,
  }) : _initialChannel = channel {
    transport = WebSocketRoomTransport(
      baseUri: Uri.parse('https://livehouse.dihe.moe'),
      roomId: 'room-id',
      ticket: 'ticket',
      clock: clock,
      random: random ?? _MidpointRandom(),
      channelFactory: (uri) {
        this.uri = uri;
        final next =
            _initialChannel ??
            FakeWebSocketChannel(
              ready: connectFails
                  ? Future<void>.error(const _ConnectFailed())
                  : null,
            );
        _initialChannel = null;
        channels.add(next);
        return next;
      },
    );
  }

  FakeWebSocketChannel? _initialChannel;
  late final WebSocketRoomTransport transport;
  final List<FakeWebSocketChannel> channels = [];
  bool connectFails = false;
  late Uri uri;

  void start(FakeAsync async, {bool open = false}) {
    unawaited(transport.start());
    async.flushMicrotasks();
    if (open) {
      final channel = channels.single;
      channel.receive(
        _response(_lastRequestId(channel, 'hello'), 'hello', _helloData()),
      );
      async.flushMicrotasks();
    }
  }
}

final class _ConnectFailed implements Exception {
  const _ConnectFailed();
}

String _lastRequestId(FakeWebSocketChannel channel, String type) {
  for (final message in channel.messages.reversed) {
    final json = jsonDecode(message) as Map<String, Object?>;
    if (json['type'] == type) return json['id']! as String;
  }
  throw StateError('No request of type $type');
}

void _answerPing(FakeWebSocketChannel channel, {int serverTimeMs = 1000100}) {
  final ping = jsonDecode(
    channel.messages.lastWhere((message) => message.contains('"ping"')),
  ) as Map<String, Object?>;
  final data = ping['data']! as Map<String, Object?>;
  channel.receive(
    _response(ping['id']! as String, 'ping', {
      'clientTimeMs': data['clientTimeMs'],
      'serverTimeMs': serverTimeMs,
    }),
  );
}

String _response(String id, String type, Map<String, Object?> data) {
  return jsonEncode({'kind': 'response', 'id': id, 'type': type, 'data': data});
}

String _errorResponse(String id, String type, String code, String message) {
  return jsonEncode({
    'kind': 'response',
    'id': id,
    'type': type,
    'data': <String, Object?>{},
    'error': {'code': code, 'message': message},
  });
}

String _event(String type, int term, int seq, Map<String, Object?> data) {
  return jsonEncode({
    'kind': 'event',
    'type': type,
    'term': term,
    'seq': seq,
    'data': data,
  });
}

Map<String, Object?> _helloData() {
  return {
    'member': {'id': 'member-id', 'name': '听众', 'avatarHash': 'hash'},
    'serverTimeMs': 1000000,
    'room': _snapshotData(),
  };
}

Map<String, Object?> _snapshotData() {
  return {
    'term': 1,
    'seq': 1,
    'room': {
      'id': 'room-id',
      'name': '房间',
      'description': '描述',
      'kind': 'ephemeral',
    },
    'playMode': 'sequential',
    'nowPlaying': {
      'entry': _entryData(),
      'mediaUrl': '/media/netease/track-id',
      'startedAtMs': 1000000,
      'durationMs': 180000,
      'gain': 1.0,
      'lyric': '',
    },
    'pending': null,
    'items': [_entryData()],
    'members': {
      'sessions': [
        {'id': 'member-id', 'name': '听众', 'avatarHash': 'hash'},
      ],
      'onlineCount': 1,
    },
  };
}

Map<String, Object?> _entryData() {
  return {
    'id': 'entry-id',
    'track': _trackData(),
    'meta': {
      'title': '歌曲',
      'artist': '歌手',
      'album': '专辑',
      'coverUrl': 'https://example.com/cover.jpg',
      'pageUrl': 'https://example.com/track',
      'durationMs': 180000,
    },
    'by': {'id': 'member-id', 'name': '听众', 'avatarHash': 'hash'},
    'auto': false,
    'likes': 0,
    'status': 'ready',
  };
}

Map<String, Object?> _trackData() {
  return {'source': 'netease', 'id': 'track-id'};
}
