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

  group('after the media URL redirects', () {
    final cdn = Uri.parse('https://cdn.test/a.mp3?expires=1');
    final renewed = Uri.parse('https://cdn.test/a.mp3?expires=2');

    ResponseBody audio({Uri? redirectedTo, int status = 206}) => ResponseBody(
      Stream.value(Uint8List(10)),
      status,
      headers: {
        'content-range': ['bytes 0-9/100'],
        'content-type': ['audio/mpeg'],
      },
      redirects: [
        if (redirectedTo != null) RedirectRecord(302, 'GET', redirectedTo),
      ],
    );

    test('later ranges are asked of the redirected address directly', () async {
      final adapter = _FakeAdapter(
        (options) => options.uri == uri ? audio(redirectedTo: cdn) : audio(),
      );
      final source = factoryWith(adapter).source(uri);

      await source.request(0);
      await source.request(50);

      expect([for (final r in adapter.requests) r.uri], [uri, cdn]);
      expect(adapter.requests.last.headers['range'], 'bytes=50-');
    });

    test('a redirected address that stops working is resolved again through '
        'the media URL, and the new one is used from then on', () async {
      var resolved = 0;
      final adapter = _FakeAdapter((options) {
        if (options.uri == uri) {
          return audio(redirectedTo: ++resolved == 1 ? cdn : renewed);
        }
        if (options.uri == cdn) return ResponseBody.fromString('expired', 403);
        return audio();
      });
      final source = factoryWith(adapter).source(uri);

      await source.request(0);
      final response = await source.request(50);
      await source.request(70);

      expect(response.contentType, 'audio/mpeg');
      expect(
        [for (final r in adapter.requests) r.uri],
        [uri, cdn, uri, renewed],
      );
      expect(adapter.requests[2].headers['range'], 'bytes=50-');
    });

    test('a cancelled request is not asked again', () async {
      final adapter = _FakeAdapter(
        (options) => options.uri == uri
            ? audio(redirectedTo: cdn)
            : throw DioException.requestCancelled(
                requestOptions: options,
                reason: 'cancelled',
              ),
      );
      final source = factoryWith(adapter).source(uri);
      await source.request(0);

      final error = await source
          .request(50)
          .then<Object?>((_) => null, onError: (Object error) => error);

      expect((error! as AudioStreamException).reason, 'cancel');
      expect([for (final r in adapter.requests) r.uri], [uri, cdn]);
    });
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
