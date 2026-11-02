import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/features/search/application/clipboard_link_controller.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:dio/dio.dart';

final class FakeSharedTextSource implements SharedTextSource {
  final _texts = StreamController<String>.broadcast();

  @override
  Stream<String> get texts => _texts.stream;

  void share(String text) => _texts.add(text);

  void fail(Object error) => _texts.addError(error);
}

final class FakeLinkResolver implements LinkResolver {
  final Map<String, ResolvedShare?> answers = {};
  final Map<String, ResolvedShare?> recognitions = {};

  final List<String> asked = [];
  final List<Future<void>?> cancels = [];
  final Map<String, Completer<ResolvedShare?>> _held = {};
  bool hold = false;

  @override
  ResolvedShare? recognize(String text) {
    return recognitions.containsKey(text) ? recognitions[text] : answers[text];
  }

  @override
  Future<ResolvedShare?> resolve(String text, {Future<void>? cancel}) {
    asked.add(text);
    cancels.add(cancel);
    if (!hold) return Future.value(answers[text]);
    return (_held[text] = Completer()).future;
  }

  void release(String text) => _held.remove(text)!.complete(answers[text]);
}

final class FakeUrlHttpAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function()> answers = {};
  final List<RequestOptions> requests = [];
  bool hang = false;
  int cancelled = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    unawaited(cancelFuture?.then((_) => cancelled++));
    if (hang) return Completer<ResponseBody>().future;
    final answer = answers[options.uri.toString()];
    return Future.value(answer?.call() ?? ResponseBody.fromString('', 404));
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody redirectTo(String location, {int status = 302}) {
  return ResponseBody.fromString(
    '',
    status,
    headers: {
      'location': [location],
    },
  );
}

const neteaseShareText =
    '分享周杰伦的单曲《晴天》: https://music.163.com/song?id=186016&userid=1 '
    '(来自@网易云音乐)';

/// 与 Android 一样，内容每次变化都更新标记；[stamped] 为 false 时模拟没有标记
/// 的 iOS。
final class FakeClipboardSource implements ClipboardSource {
  FakeClipboardSource([String? text]) {
    if (text != null) copy(text);
  }

  String? _text;
  int? _stamp;
  int _changes = 0;
  bool stamped = true;
  int reads = 0;

  /// 即使文本相同，每次复制也会改变标记。
  void copy(String text) {
    _text = text;
    _stamp = ++_changes;
  }

  @override
  Future<int?> stamp() async => stamped ? _stamp : null;

  @override
  Future<String?> read() async {
    reads++;
    return _text;
  }
}
