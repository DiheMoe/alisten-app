import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpHeaders, HttpServer, HttpStatus, InternetAddress;
import 'dart:typed_data';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' show protocolVersion;
import 'package:alisten/features/server/data/alisten_server_probe.dart';
import 'package:alisten/features/server/index.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/api/fake_http_adapter.dart';
import '../../../core/realtime/fake_web_socket_channel.dart';

// 本机后端对不存在的房间与旧协议版本的真实回复。
const _notFoundReply =
    '{"kind":"response","type":"hello","id":"probe","data":{},'
    '"error":{"code":"NOT_FOUND","message":"房间不存在"}}';
const _outdatedReply =
    '{"kind":"response","type":"hello","id":"probe","data":{},'
    '"error":{"code":"CLIENT_OUTDATED","message":"前端与服务端的协议版本不一致，请刷新页面"}}';

const _origin = 'https://example.com:8443';
const _found = ProbeSucceeded(origin: _origin, brandName: '大猫听歌房');

void main() {
  late FakeHttpAdapter adapter;
  late FakeWebSocketChannel channel;
  late List<Uri> uris;
  late AlistenServerProbe probe;

  AlistenServerProbe probeWith(HttpClientAdapter httpAdapter) {
    return AlistenServerProbe(
      dio: Dio()..httpClientAdapter = httpAdapter,
      connect: (uri) {
        uris.add(uri);
        return channel;
      },
    );
  }

  setUp(() {
    adapter = FakeHttpAdapter()..respond(200, {'brandName': '大猫听歌房'});
    channel = FakeWebSocketChannel();
    uris = [];
    probe = probeWith(adapter);
  });

  group('probe', () {
    test('a server that answers the hello with NOT_FOUND is a compatible '
        'Alisten server', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);

        expect(adapter.requests.single.method, 'GET');
        expect(
          adapter.requests.single.uri,
          Uri.parse('https://example.com:8443/api/site'),
        );
        expect(uris.single, Uri.parse('wss://example.com:8443/ws'));
        expect(jsonDecode(channel.messages.single), {
          'kind': 'request',
          'id': 'probe',
          'type': 'hello',
          'data': {
            'roomId': '00000000-0000-4000-8000-000000000000',
            'ticket': 'probe',
            'protocolVersion': protocolVersion,
          },
        });
        expect(result.value, isNull);

        channel.receive(_notFoundReply);
        channel.serverClose(4404);
        async.elapse(Duration.zero);

        expect(result.value, _found);
        expect(channel.webSocketSink.closeCalls, 1);
        expect(channel.webSocketSink.closedWith, 1000);
        expect(channel.hasListener, isFalse);
      });
    });

    test('a close with 4401 and no reply is compatible', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        channel.serverClose(4401);
        async.elapse(Duration.zero);

        expect(result.value, _found);
        expect(channel.webSocketSink.closedWith, 1000);
      });
    });

    test('a close with 4404 and no reply is compatible', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        channel.serverClose(4404);
        async.elapse(Duration.zero);

        expect(result.value, _found);
      });
    });

    test('an UNAUTHORIZED reply is compatible', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        channel.receive(
          '{"kind":"response","type":"hello","id":"probe","data":{},'
          '"error":{"code":"UNAUTHORIZED","message":"票据无效"}}',
        );
        async.elapse(Duration.zero);

        expect(result.value, _found);
      });
    });

    test('CLIENT_OUTDATED is incompatible', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        channel.receive(_outdatedReply);
        channel.serverClose(4426);
        async.elapse(Duration.zero);

        expect(result.value, const ProbeFailed(ProbeFailure.incompatible));
        expect(channel.webSocketSink.closeCalls, 1);
        expect(channel.webSocketSink.closedWith, 1000);
      });
    });

    test('a close with 4426 and no reply is incompatible', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        channel.serverClose(4426);
        async.elapse(Duration.zero);

        expect(result.value, const ProbeFailed(ProbeFailure.incompatible));
      });
    });

    for (final code in [1011, 4408, 1000]) {
      test('a close with $code and no reply leaves the version unverified', () {
        fakeAsync((async) {
          final result = _outcome(probe.probe(_origin));
          async.elapse(Duration.zero);
          channel.serverClose(code);
          async.elapse(Duration.zero);

          expect(result.value, const ProbeFailed(ProbeFailure.unverified));
          expect(channel.webSocketSink.closedWith, 1000);
        });
      });
    }

    test('the first of the reply and the close decides', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        channel.serverClose(4426);
        async.elapse(Duration.zero);
        expect(result.value, const ProbeFailed(ProbeFailure.incompatible));

        final second = FakeWebSocketChannel();
        channel = second;
        final next = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        second.receive(_notFoundReply);
        async.elapse(Duration.zero);
        expect(next.value, _found);
        second.serverClose(4426);
        async.elapse(Duration.zero);
        expect(next.value, _found);
      });
    });

    test('frames other than the reply to the hello are ignored', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        channel
          ..receive('not json')
          ..receive('[]')
          ..receive(
            '{"kind":"response","type":"hello","id":"1","data":{},'
            '"error":{"code":"CLIENT_OUTDATED","message":"x"}}',
          )
          ..receive(
            '{"kind":"event","type":"error","data":'
            '{"code":"CLIENT_OUTDATED","message":"x"}}',
          );
        async.elapse(Duration.zero);
        expect(result.value, isNull);

        channel.receive(_notFoundReply);
        async.elapse(Duration.zero);
        expect(result.value, _found);
      });
    });

    test('a hello that succeeds or fails with another code leaves the '
        'version unverified', () {
      for (final reply in [
        '{"kind":"response","type":"hello","id":"probe","data":{}}',
        '{"kind":"response","type":"hello","id":"probe","data":{},'
            '"error":{"code":"INVALID_ARGUMENT","message":"x"}}',
        '{"kind":"response","type":"hello","id":"probe","data":{},'
            '"error":{"code":"SOMETHING_NEW","message":"x"}}',
      ]) {
        fakeAsync((async) {
          channel = FakeWebSocketChannel();
          final result = _outcome(probe.probe(_origin));
          async.elapse(Duration.zero);
          channel.receive(reply);
          async.elapse(Duration.zero);

          expect(
            result.value,
            const ProbeFailed(ProbeFailure.unverified),
            reason: reply,
          );
        });
      }
    });

    test('a connection that is never ready is given up after ten seconds', () {
      fakeAsync((async) {
        channel = FakeWebSocketChannel(ready: Completer<void>().future);
        final result = _outcome(probe.probe(_origin));
        async.elapse(const Duration(milliseconds: 9999));
        expect(result.value, isNull);

        async.elapse(const Duration(milliseconds: 1));
        expect(result.value, const ProbeFailed(ProbeFailure.unverified));
        expect(channel.messages, isEmpty);
        expect(channel.webSocketSink.closedWith, 1000);
      });
    });

    test('a connection that fails is unverified', () {
      fakeAsync((async) {
        final ready = Completer<void>();
        channel = FakeWebSocketChannel(ready: ready.future);
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);
        ready.completeError(const ConnectionRefused());
        async.elapse(Duration.zero);

        expect(result.value, const ProbeFailed(ProbeFailure.unverified));
        expect(channel.messages, isEmpty);
        expect(channel.webSocketSink.closedWith, 1000);
      });
    });

    test('a connection that cannot be made is unverified', () {
      fakeAsync((async) {
        final throwing = AlistenServerProbe(
          dio: Dio()..httpClientAdapter = adapter,
          connect: (uri) => throw const ConnectionRefused(),
        );
        final result = _outcome(throwing.probe(_origin));
        async.elapse(Duration.zero);

        expect(result.value, const ProbeFailed(ProbeFailure.unverified));
      });
    });

    test('a silent connection is given up fifteen seconds after the '
        'handshake starts', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe(_origin));
        async.elapse(const Duration(seconds: 14));
        expect(channel.messages, hasLength(1));
        expect(result.value, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(result.value, const ProbeFailed(ProbeFailure.unverified));
        expect(channel.webSocketSink.closedWith, 1000);
        expect(channel.hasListener, isFalse);
      });
    });

    test('a site that cannot be reached is unreachable and skips the '
        'handshake', () {
      fakeAsync((async) {
        adapter.fail();
        final result = _outcome(probe.probe(_origin));
        async.elapse(Duration.zero);

        expect(result.value, const ProbeFailed(ProbeFailure.unreachable));
        expect(uris, isEmpty);
      });
    });

    test('a site that does not answer in ten seconds is unreachable and its '
        'request is cancelled', () {
      fakeAsync((async) {
        adapter.neverRespond();
        final result = _outcome(probe.probe(_origin));
        async.elapse(const Duration(milliseconds: 9999));
        expect(result.value, isNull);
        expect(adapter.cancelled, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(result.value, const ProbeFailed(ProbeFailure.unreachable));
        expect(adapter.cancelled, isTrue);
        expect(uris, isEmpty);
      });
    });

    test('a site that is not an Alisten site, or an Alisten site that is '
        'not available', () {
      final cases = <(int, String, ProbeFailure)>[
        (200, '<html><body>hello</body></html>', ProbeFailure.notAlisten),
        (200, '{"name":"x"}', ProbeFailure.notAlisten),
        (200, '{"brandName":1}', ProbeFailure.notAlisten),
        (200, '["大猫听歌房"]', ProbeFailure.notAlisten),
        (404, '<html>', ProbeFailure.notAlisten),
        (404, '{"error":"not found"}', ProbeFailure.notAlisten),
        (301, '', ProbeFailure.notAlisten),
        (
          409,
          '{"error":{"code":"CONFLICT","message":"x"}}',
          ProbeFailure.unreachable,
        ),
        (
          409,
          '{"error":{"code":"SOMETHING_NEW","message":"x"}}',
          ProbeFailure.unreachable,
        ),
        (
          503,
          '{"error":{"code":"UNAVAILABLE","message":"维护中"}}',
          ProbeFailure.unreachable,
        ),
        (502, '<html>Bad Gateway</html>', ProbeFailure.unreachable),
        (503, '<html>Service Unavailable</html>', ProbeFailure.unreachable),
        (504, '<html>Gateway Timeout</html>', ProbeFailure.unreachable),
        (500, '', ProbeFailure.unreachable),
      ];
      for (final (status, body, failure) in cases) {
        fakeAsync((async) {
          adapter.respondRaw(status, body, null);
          final result = _outcome(probe.probe(_origin));
          async.elapse(Duration.zero);

          expect(result.value, ProbeFailed(failure), reason: '$status $body');
        });
      }
      expect(uris, isEmpty);
    });

    test('the site request does not follow redirects', () {
      fakeAsync((async) {
        final recording = _RecordingAdapter();
        final result = _outcome(probeWith(recording).probe(_origin));
        async.elapse(Duration.zero);
        channel.serverClose(4404);
        async.elapse(Duration.zero);

        expect(result.value, _found);
        expect(recording.options.single.followRedirects, isFalse);
      });
    });

    test('a redirect from the site is not followed', () async {
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => target.close(force: true));
      var targetHits = 0;
      target.listen((request) {
        targetHits++;
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"brandName":"大猫听歌房"}');
        unawaited(request.response.close());
      });
      final site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => site.close(force: true));
      site.listen((request) {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${target.port}/api/site',
          );
        unawaited(request.response.close());
      });
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final loopback = AlistenServerProbe(
        dio: dio,
        connect: (uri) {
          uris.add(uri);
          return channel;
        },
      );

      expect(
        await loopback.probe('http://127.0.0.1:${site.port}'),
        const ProbeFailed(ProbeFailure.notAlisten),
      );
      expect(targetHits, 0);
      expect(uris, isEmpty);
    });

    test('a brand name is trimmed and must look like one', () {
      const notAlisten = ProbeFailed(ProbeFailure.notAlisten);
      final longest = '🎵' * AlistenServerProbe.maxBrandNameRunes;
      final cases = <(String, ProbeResult)>[
        ('{"brandName":"  大猫听歌房 "}', _found),
        ('{"brandName":""}', notAlisten),
        ('{"brandName":" \\t "}', notAlisten),
        ('{"brandName":"大猫\\u0007听歌房"}', notAlisten),
        ('{"brandName":"大猫\\u0085听歌房"}', notAlisten),
        (
          jsonEncode({'brandName': longest}),
          ProbeSucceeded(origin: _origin, brandName: longest),
        ),
        (jsonEncode({'brandName': '$longest🎵'}), notAlisten),
      ];
      for (final (body, expected) in cases) {
        fakeAsync((async) {
          adapter.respondRaw(200, body, null);
          final result = _outcome(probe.probeSite(_origin));
          async.elapse(Duration.zero);

          expect(result.value, expected, reason: body);
        });
      }
    });

    // 读到上限时提前结束 `await for`，其后续执行在 fake_async 中会一直挂起，
    // 所以这两个用例使用真实的事件循环。
    test('a site body is read only up to its limit', () async {
      String padded(int bytes) {
        const head = '{"brandName":"大猫听歌房","padding":"';
        const tail = '"}';
        final used = utf8.encode(head).length + tail.length;
        return '$head${'x' * (bytes - used)}$tail';
      }

      const limit = AlistenServerProbe.maxSiteBodyBytes;
      final cases = <(int, String, ProbeResult)>[
        (200, padded(limit), _found),
        (200, padded(limit + 1), const ProbeFailed(ProbeFailure.notAlisten)),
        (
          404,
          '{"error":{"code":"NOT_FOUND","message":"${'x' * limit}"}}',
          const ProbeFailed(ProbeFailure.notAlisten),
        ),
        (
          503,
          '<html>${'x' * limit}</html>',
          const ProbeFailed(ProbeFailure.unreachable),
        ),
      ];
      for (final (status, body, expected) in cases) {
        adapter.respondRaw(status, body, null);

        expect(
          await probe.probeSite(_origin),
          expected,
          reason: '$status ${body.length}',
        );
      }
    });

    test('a site body that does not end stops being read at its '
        'limit', () async {
      final streaming = _StreamingAdapter();
      addTearDown(streaming.close);
      streaming.body
        ..add(Uint8List(AlistenServerProbe.maxSiteBodyBytes))
        ..add(Uint8List(1));

      expect(
        await probeWith(streaming).probeSite(_origin),
        const ProbeFailed(ProbeFailure.notAlisten),
      );
      expect(streaming.body.hasListener, isFalse);
    });

    test('logs carry the outcome, the error code and the close code but '
        'never the server', () {
      final records = <String>[];
      AppLog.onRecord = (name, level, message) => records.add('$name $message');
      addTearDown(() => AppLog.onRecord = null);
      const secret = 'https://secret-host.example:8443';
      fakeAsync((async) {
        adapter.respondRaw(
          503,
          '{"error":{"code":"UNAVAILABLE","message":"维护中"}}',
          null,
        );
        unawaited(probe.probe(secret));
        async.elapse(Duration.zero);

        adapter.respond(200, {'brandName': '大猫听歌房'});
        unawaited(probe.probe(secret));
        async.elapse(Duration.zero);
        channel
          ..receive(_outdatedReply)
          ..serverClose(4426);
        async.elapse(Duration.zero);

        channel = FakeWebSocketChannel();
        unawaited(probe.probe(secret));
        async.elapse(Duration.zero);
        channel.serverClose(1011);
        async.elapse(Duration.zero);
      });

      expect(records, [
        'alisten.server site probe failed outcome=unreachable',
        'alisten.server handshake probe failed code=CLIENT_OUTDATED '
            'outcome=incompatible',
        'alisten.server handshake probe failed closeCode=1011 '
            'outcome=unverified',
      ]);
      for (final record in records) {
        expect(record, isNot(contains('secret-host')));
        expect(record, isNot(contains('维护中')));
        expect(record, isNot(contains('前端与服务端')));
      }
    });

    test('a cleartext server is probed over ws', () {
      fakeAsync((async) {
        final result = _outcome(probe.probe('http://10.0.2.2:9876'));
        async.elapse(Duration.zero);
        channel.serverClose(4404);
        async.elapse(Duration.zero);

        expect(
          adapter.requests.single.uri,
          Uri.parse('http://10.0.2.2:9876/api/site'),
        );
        expect(uris.single, Uri.parse('ws://10.0.2.2:9876/ws'));
        expect(
          result.value,
          const ProbeSucceeded(
            origin: 'http://10.0.2.2:9876',
            brandName: '大猫听歌房',
          ),
        );
      });
    });

    test('a server on the default port is probed without a port', () {
      fakeAsync((async) {
        unawaited(probe.probe('https://example.com'));
        async.elapse(Duration.zero);

        expect(uris.single, Uri.parse('wss://example.com/ws'));
        channel.serverClose(4404);
        async.elapse(Duration.zero);
      });
    });
  });

  group('probeSite', () {
    test('only reads the site', () {
      fakeAsync((async) {
        final result = _outcome(probe.probeSite(_origin));
        async.elapse(Duration.zero);

        expect(result.value, _found);
        expect(uris, isEmpty);
      });
    });

    test('gives up after the given time', () {
      fakeAsync((async) {
        adapter.neverRespond();
        final result = _outcome(
          probe.probeSite(_origin, timeout: const Duration(seconds: 5)),
        );
        async.elapse(const Duration(milliseconds: 4999));
        expect(result.value, isNull);

        async.elapse(const Duration(milliseconds: 1));
        expect(result.value, const ProbeFailed(ProbeFailure.unreachable));
        expect(adapter.cancelled, isTrue);
      });
    });

    test('stops the request when told to', () {
      fakeAsync((async) {
        adapter.neverRespond();
        final stop = Completer<void>();
        final result = _outcome(
          probe.probeSite(
            _origin,
            timeout: const Duration(seconds: 5),
            cancel: stop.future,
          ),
        );
        async.elapse(const Duration(seconds: 1));
        expect(result.value, isNull);
        expect(adapter.cancelled, isFalse);

        stop.complete();
        async.elapse(Duration.zero);

        expect(adapter.cancelled, isTrue);
        expect(result.value, const ProbeFailed(ProbeFailure.unreachable));
      });
    });
  });

  group('probeHandshake', () {
    test('only tries the handshake', () {
      fakeAsync((async) {
        ProbeFailure? failure = ProbeFailure.unreachable;
        var done = false;
        unawaited(
          probe.probeHandshake(_origin).then((value) {
            failure = value;
            done = true;
          }),
        );
        async.elapse(Duration.zero);
        channel.receive(_notFoundReply);
        async.elapse(Duration.zero);

        expect(done, isTrue);
        expect(failure, isNull);
        expect(adapter.requests, isEmpty);
        expect(uris.single, Uri.parse('wss://example.com:8443/ws'));
      });
    });

    test('stops and closes the connection when told to', () {
      fakeAsync((async) {
        final stop = Completer<void>();
        ProbeFailure? failure;
        var done = false;
        unawaited(
          probe.probeHandshake(_origin, cancel: stop.future).then((value) {
            failure = value;
            done = true;
          }),
        );
        async.elapse(const Duration(seconds: 1));
        expect(channel.messages, hasLength(1));
        expect(done, isFalse);

        stop.complete();
        async.elapse(Duration.zero);

        expect(done, isTrue);
        expect(failure, ProbeFailure.unverified);
        expect(channel.webSocketSink.closeCalls, 1);
        expect(channel.webSocketSink.closedWith, 1000);
        expect(channel.hasListener, isFalse);
      });
    });

    test('an origin that cannot be parsed is unverified', () async {
      expect(
        await probe.probeHandshake('http://[::1'),
        ProbeFailure.unverified,
      );
      expect(uris, isEmpty);
    });

    test('reports an incompatible server', () {
      fakeAsync((async) {
        ProbeFailure? failure;
        unawaited(
          probe.probeHandshake(_origin).then((value) => failure = value),
        );
        async.elapse(Duration.zero);
        channel.receive(_outdatedReply);
        async.elapse(Duration.zero);

        expect(failure, ProbeFailure.incompatible);
      });
    });
  });

  group('fetchBrandName', () {
    test('reads the brand name without connecting', () {
      fakeAsync((async) {
        String? brandName;
        unawaited(
          probe.fetchBrandName(_origin).then((value) => brandName = value),
        );
        async.elapse(Duration.zero);

        expect(brandName, '大猫听歌房');
        expect(uris, isEmpty);
      });
    });

    test('is null when the site cannot be read', () {
      fakeAsync((async) {
        adapter.fail();
        String? brandName = 'unchanged';
        var done = false;
        unawaited(
          probe.fetchBrandName(_origin).then((value) {
            brandName = value;
            done = true;
          }),
        );
        async.elapse(Duration.zero);

        expect(done, isTrue);
        expect(brandName, isNull);
        expect(uris, isEmpty);
      });
    });
  });
}

final class _Outcome {
  ProbeResult? value;
}

_Outcome _outcome(Future<ProbeResult> probing) {
  final outcome = _Outcome();
  unawaited(probing.then((value) => outcome.value = value));
  return outcome;
}

final class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> options = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options.add(options);
    return ResponseBody.fromString('{"brandName":"大猫听歌房"}', 200);
  }

  @override
  void close({bool force = false}) {}
}

final class _StreamingAdapter implements HttpClientAdapter {
  final body = StreamController<Uint8List>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(body.stream, 200);
  }

  @override
  void close({bool force = false}) => unawaited(body.close());
}
