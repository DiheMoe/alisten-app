import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  FakeWebSocketChannel({Future<void>? ready})
    : ready = ready ?? Future<void>.value();

  final StreamController<String> _controller = StreamController<String>();
  final List<String> messages = [];
  // 由被测代码关闭，测试据此断言是否关闭及关闭码。
  // ignore: close_sinks
  late final FakeWebSocketSink webSocketSink = FakeWebSocketSink(messages);

  @override
  final Future<void> ready;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  String? get protocol => null;

  @override
  Stream<String> get stream => _controller.stream;

  @override
  WebSocketSink get sink => webSocketSink;

  bool get hasListener => _controller.hasListener;

  void receive(String message) => _controller.add(message);

  // 不经过 sink：`closeCalls` 和 `closedWith` 只记录被测代码发起的关闭。
  void serverClose(int code) {
    closeCode = code;
    closeReason = 'test close';
    unawaited(_controller.close());
  }
}

final class FakeWebSocketSink implements WebSocketSink {
  FakeWebSocketSink(this.messages);

  final List<String> messages;
  int closeCalls = 0;
  int? closedWith;

  @override
  Future<void> get done => Future<void>.value();

  @override
  void add(Object? data) => messages.add(data! as String);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closeCalls++;
    closedWith = closeCode;
  }
}
