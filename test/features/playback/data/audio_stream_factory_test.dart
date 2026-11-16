// just_audio 的流式音源 API 是实验性的。
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:alisten/features/playback/data/audio_stream_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  final uri = Uri.parse('https://media.test/a.mp3?sig=secret');

  AudioStreamFactory factoryWith(_FakeAdapter adapter) {
    return AudioStreamFactory(Dio()..httpClientAdapter = adapter);
  }

  Future<List<int>> read(StreamAudioResponse response) async {
    return [for (final chunk in await response.stream.toList()) ...chunk];
  }

  final flac = [...'fLaC'.codeUnits, 0, 0, 0, 0x22, ...List.filled(92, 0)];

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

  group('the media type given to the player', () {
    // 按 Range 截取 [file] 作答；声明的类型和跳转后的文件名由 CDN 给出。
    _FakeAdapter cdn(String? declared, {String path = '/a', List<int>? file}) {
      final bytes = file ?? List.filled(100, 0);
      return _FakeAdapter((options) {
        final range = RegExp(r'bytes=(\d+)-(\d*)')
            .firstMatch(options.headers['range'] as String)!;
        final start = int.parse(range.group(1)!);
        final last = range.group(2)!.isEmpty
            ? bytes.length - 1
            : math.min(int.parse(range.group(2)!), bytes.length - 1);
        return ResponseBody(
          Stream.value(Uint8List.fromList(bytes.sublist(start, last + 1))),
          206,
          headers: {
            'content-range': ['bytes $start-$last/${bytes.length}'],
            'content-type': ?declared == null ? null : [declared],
          },
          redirects: [
            RedirectRecord(302, 'GET', Uri.parse('https://cdn.test$path?k=1')),
          ],
        );
      });
    }

    // 播放器第一次只要前两个字节。
    Future<String> typeOf(
      String? declared, {
      String path = '/a',
      List<int>? file,
    }) async {
      final adapter = cdn(declared, path: path, file: file);
      final response = await factoryWith(adapter).source(uri).request(0, 2);
      return response.contentType;
    }

    test('comes from the opening bytes, whatever the CDN declares', () async {
      final mp3 = [0xFF, 0xFB, 0x90, 0x64, ...List.filled(96, 0)];
      final mp4 = [
        0,
        0,
        0,
        0x20,
        ...'ftypM4A '.codeUnits,
        ...List.filled(88, 0),
      ];

      expect(await typeOf('audio/x-ogg', file: flac), 'audio/flac');
      expect(
        await typeOf('application/octet-stream', path: '/a.flac', file: mp3),
        'audio/mpeg',
      );
      expect(await typeOf('audio/mpeg', file: mp4), 'audio/mp4');
    });

    test('is read without giving the player more than it asked for', () async {
      final adapter = cdn('audio/x-ogg', file: flac);

      final response = await factoryWith(adapter).source(uri).request(0, 2);

      expect(await read(response), 'fL'.codeUnits);
      expect(response.offset, 0);
      expect(response.contentLength, 2);
      expect(response.sourceLength, flac.length);
      expect(adapter.requests, hasLength(1));
    });

    test('stays the same for the rest of the file', () async {
      final source = factoryWith(cdn('audio/x-ogg', file: flac)).source(uri);

      await source.request(0, 2);

      expect((await source.request(50)).contentType, 'audio/flac');
      expect((await source.request(0)).contentType, 'audio/flac');
    });

    test(
      'is not taken from an ID3 tag, which FLAC files can carry too',
      () async {
        final tagged = [
          ...'ID3'.codeUnits,
          4,
          0,
          0,
          0,
          0,
          0,
          0x10,
          ...List.filled(90, 0),
        ];

        expect(await typeOf('audio/x-flac', file: tagged), 'audio/flac');
        expect(
          await typeOf(
            'application/octet-stream',
            path: '/a.mp3',
            file: tagged,
          ),
          'audio/mpeg',
        );
      },
    );

    test('hands on the whole file after reading its opening, and cancelling '
        'it cancels the request', () async {
      final body = StreamController<Uint8List>();
      final adapter = _FakeAdapter(
        (_) => ResponseBody(
          body.stream,
          206,
          headers: {
            'content-range': ['bytes 0-99/100'],
            'content-type': ['audio/x-ogg'],
          },
        ),
      );
      final source = factoryWith(adapter).source(uri);
      body
        ..add(Uint8List.fromList(flac.sublist(0, 3)))
        ..add(Uint8List.fromList(flac.sublist(3, 20)));

      final response = await source.request(0);
      final received = <int>[];
      final subscription = response.stream.listen(received.addAll);
      body.add(Uint8List.fromList(flac.sublist(20, 30)));
      await pumpEventQueue();

      expect(response.contentType, 'audio/flac');
      expect(received, flac.sublist(0, 30));

      await subscription.cancel();
      await pumpEventQueue();

      expect(adapter.cancelled, isTrue);
      await body.close();
    });

    test('uses the registered name for FLAC', () async {
      expect(await typeOf('audio/x-flac'), 'audio/flac');
      expect(await typeOf('audio/flac'), 'audio/flac');
    });

    test('follows the file name when the type says nothing', () async {
      // 网易云有的 MP3 声明为 application/octet-stream;charset=UTF-8。
      for (final declared in [
        null,
        '',
        'application/octet-stream',
        'application/octet-stream;charset=UTF-8',
      ]) {
        expect(await typeOf(declared, path: '/F000x.flac'), 'audio/flac');
        expect(await typeOf(declared, path: '/M500x.MP3'), 'audio/mpeg');
        expect(await typeOf(declared, path: '/C400x.m4a'), 'audio/mp4');
        expect(
          await typeOf(declared, path: '/unknown'),
          'application/octet-stream',
        );
      }
    });

    test('keeps any other audio type as declared', () async {
      expect(
        await typeOf('audio/mpeg;charset=UTF-8', path: '/a.flac'),
        'audio/mpeg;charset=UTF-8',
      );
    });
  });

  group('a preloaded opening', () {
    const head = AudioStreamFactory.preloadBytes;
    const total = head * 3;
    final cdn = Uri.parse('https://cdn.test/a.mp3?expires=1');

    // 媒体地址跳转到 CDN；每个字节的值是它的位置对 251 取余，拼错了看得出来。
    ResponseBody file(
      RequestOptions options, {
      int length = total,
      List<int> opening = const [],
      String declared = 'audio/mpeg',
    }) {
      final range = RegExp(r'bytes=(\d+)-(\d*)')
          .firstMatch(options.headers['range'] as String);
      final start = int.parse(range!.group(1)!);
      final last = range.group(2)!.isEmpty
          ? length - 1
          : int.parse(range.group(2)!);
      return ResponseBody(
        Stream.value(
          Uint8List.fromList([
            for (var i = start; i <= last; i++)
              i < opening.length ? opening[i] : i % 251,
          ]),
        ),
        206,
        headers: {
          'content-range': ['bytes $start-$last/$length'],
          'content-type': [declared],
        },
        redirects: [if (options.uri == uri) RedirectRecord(302, 'GET', cdn)],
      );
    }

    test('starts the source from memory and goes on from the redirected '
        'address, and outlives switching sources', () async {
      final adapter = _FakeAdapter(file);
      final factory = factoryWith(adapter)..preload(uri);
      await pumpEventQueue();
      factory.cancelAll();

      final source = factory.source(uri);
      expect(adapter.requests, hasLength(1));
      final response = await source.request(10);
      final bytes = await read(response);

      expect(response.offset, 10);
      expect(response.sourceLength, total);
      expect(bytes, hasLength(total - 10));
      expect(bytes.first, 10);
      expect(bytes[head - 10], head % 251);
      expect(bytes.last, (total - 1) % 251);
      expect([for (final r in adapter.requests) r.uri], [uri, cdn]);
      expect(adapter.requests.first.headers['range'], 'bytes=0-${head - 1}');
      expect(adapter.requests.last.headers['range'], 'bytes=$head-');
    });

    test('is used once, and only by its own address', () async {
      final adapter = _FakeAdapter(file);
      final factory = factoryWith(adapter)..preload(uri);
      await pumpEventQueue();

      await read(
        await factory.source(Uri.parse('https://media.test/b')).request(0),
      );
      await read(await factory.source(uri).request(0, 100));
      await read(await factory.source(uri).request(0, 100));

      expect(
        [for (final r in adapter.requests) r.uri.path],
        ['/a.mp3', '/b', '/a.mp3'],
      );
    });

    test(
      'tells the player the format its bytes show, for all of the file',
      () async {
        final adapter = _FakeAdapter(
          (options) => file(
            options,
            opening: flac.sublist(0, 8),
            declared: 'audio/x-ogg',
          ),
        );
        final factory = factoryWith(adapter)..preload(uri);
        await pumpEventQueue();
        final source = factory.source(uri);

        expect((await source.request(0, 2)).contentType, 'audio/flac');
        expect((await source.request(head + 10)).contentType, 'audio/flac');
      },
    );

    test('fails rather than joining it to a different file', () async {
      var first = true;
      final adapter = _FakeAdapter((options) {
        final answer = file(options, length: first ? total : total + 1);
        first = false;
        return answer;
      });
      final factory = factoryWith(adapter)..preload(uri);
      await pumpEventQueue();

      final response = await factory.source(uri).request(0);
      final error = await read(response)
          .then<Object?>((_) => null, onError: (Object error) => error);

      expect(error, isA<AudioStreamException>());
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
