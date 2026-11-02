// just_audio 的流式音源 API 是实验性的。
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/features/playback/data/audio_stream_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final uri = Uri.parse('https://media.test/a.mp3?sig=secret');

  AudioStreamFactory factoryWith(_FakeAdapter adapter) {
    return AudioStreamFactory(Dio()..httpClientAdapter = adapter);
  }

  test('a failed request does not reveal the media URL', () async {
    final factory = factoryWith(
      _FakeAdapter((_) => ResponseBody.fromString('denied', 403)),
    );

    final error = await factory
        .source(uri)
        .request(0)
        .then<Object?>((_) => null, onError: (Object error) => error);

    expect(error, isNotNull);
    expect(error.toString(), isNot(contains('http')));
    expect(error.toString(), isNot(contains('secret')));
  });

  test('a range request answered with the whole file reports offset 0, '
      'and cancelling the stream cancels the request', () async {
    final body = StreamController<Uint8List>();
    final adapter = _FakeAdapter(
      (_) => ResponseBody(
        body.stream,
        200,
        headers: {
          'content-length': ['100'],
          'content-type': ['audio/mpeg'],
        },
      ),
    );
    final factory = factoryWith(adapter);

    final response = await factory.source(uri).request(50);

    expect(adapter.requests.single.headers['range'], 'bytes=50-');
    expect(response.offset, 0);
    expect(response.sourceLength, 100);

    final subscription = response.stream.listen((_) {});
    await subscription.cancel();
    await pumpEventQueue();

    expect(adapter.cancelled, isTrue);
    await body.close();
  });
}

final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._respond);

  final ResponseBody Function(RequestOptions options) _respond;
  final List<RequestOptions> requests = [];
  bool cancelled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    unawaited(cancelFuture?.then((_) => cancelled = true));
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}
