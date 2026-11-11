import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/protocol_generator.dart';

// 与后端交叉核对的测试要求后端仓库与本仓库并列检出；CI 不检出后端，因此跳过。
const _backendIdlPath = '../alisten/protocol/idl.json';
const _backendTypesPath = '../alisten/protocol/types.gen.go';
final _backendSkip = Directory('../alisten/protocol').existsSync()
    ? null
    : 'needs the backend checked out at ../alisten';
const _runtimePath = 'lib/core/protocol/protocol_runtime.dart';
const _runtimeImport = 'package:alisten/core/protocol/protocol_runtime.dart';
const _processTimeout = Timeout(Duration(minutes: 2));

void main() {
  group('protocol version', () {
    test('hashes canonical JSON and ignores key order', () {
      final first = <String, Object?>{'b': 'x', 'a': 1};
      final second = <String, Object?>{'a': 1, 'b': 'x'};

      expect(protocolVersionFor(first), 'ecf9e98ec0641e23');
      expect(protocolVersionFor(second), 'ecf9e98ec0641e23');
    });

    test('canonicalizes strings and key order exactly like Go', () {
      // 期望值是 Go 的 protocolVersion（设置了 SetEscapeHTML(false) 的
      // json.Encoder）对同一文档的计算结果，该文档的规范形式是
      // {"$defs":{"Note":{"description":"<&> \"q\" \\ \b\f\n\r\t\u0001<DEL> é",
      // "minLength":1,"type":"string"}},"title":"line paragraph end",
      // "x-order":{"a":4,"b":3,"！":2,"😀":1}}.
      final idl = <String, Object?>{
        'title': 'line paragraph end',
        r'$defs': <String, Object?>{
          'Note': <String, Object?>{
            'type': 'string',
            'description': '<&> "q" \\ \b\f\n\r\t\u0001\u007f é',
            'minLength': 1,
          },
        },
        'x-order': <String, Object?>{
          '\u{1F600}': 1,
          '\u{FF01}': 2,
          'b': 3,
          'a': 4,
        },
      };

      expect(protocolVersionFor(idl), 'd11fa9da357c80a1');
    });

    test('rejects numbers that Go would keep in a different spelling', () {
      for (final number in <Object>[1.5, 1.0, 1e21]) {
        expect(
          () => protocolVersionFor(<String, Object?>{
            r'$defs': <String, Object?>{
              'Page': <String, Object?>{'minimum': number},
            },
          }),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(r'$defs.Page.minimum'),
            ),
          ),
          reason: '$number',
        );
      }
    });

    test('matches the Go constant generated from the backend IDL', () {
      final goVersion = RegExp(r'const Version = "(\w+)"')
          .firstMatch(File(_backendTypesPath).readAsStringSync())
          ?.group(1);

      expect(goVersion, isNotNull);
      expect(protocolVersionFor(_backendIdl()), goVersion);
    }, skip: _backendSkip);
  });

  group('protocol output', () {
    test('contains only schema-derived declarations', () {
      final output = generateProtocol(_minimalIdl());

      expect(output, contains("import '$_runtimeImport';"));
      expect(output, contains('enum Source'));
      expect(output, contains('class Sample'));
      expect(output, contains('final Member? by;'));
      expect(output, contains('final String? note;'));
      expect(output, contains('final List<Source> tags;'));
      expect(output, contains('class QueueAddRequest'));
      expect(output, contains('class HelloRequest'));
      expect(output, contains('class HelloResponse'));
      expect(output, contains('class PlaybackUpdated'));
      expect(output, contains('abstract final class WsCloseCodes'));
      expect(output, contains('clientOutdated'));
      for (final runtime in <String>[
        'isValidLink',
        'normalizeLink',
        'class WsRequest',
        'class WsResponse',
        'class WsEvent',
        'RestEndpoint',
        "r'''",
      ]) {
        expect(output, isNot(contains(runtime)), reason: runtime);
      }
    });

    test('orders definitions and properties by name', () {
      final output = generateProtocol(_minimalIdl());
      int position(String declaration) {
        final index = output.indexOf(declaration);
        expect(index, isNonNegative, reason: declaration);
        return index;
      }

      final definitions = <int>[
        position('class Empty {'),
        position('class Member {'),
        position('class Sample {'),
        position('enum Source {'),
      ];
      expect(definitions, orderedEquals(<int>[...definitions]..sort()));
      final member = output.substring(
        position('class Member {'),
        position('class Sample {'),
      );
      expect(
        member.indexOf('final String avatarHash;'),
        lessThan(member.indexOf('final String id;')),
      );
      expect(
        member.indexOf('final String id;'),
        lessThan(member.indexOf('final String name;')),
      );
    });

    test('emits room request and event type constants', () {
      final output = generateProtocol(_minimalIdl());

      expect(output, contains('abstract final class RoomRequestTypes {'));
      expect(output, contains("static const queueAdd = 'queue.add';"));
      expect(output, contains("static const queueRemove = 'queue.remove';"));
      expect(
        output,
        contains('static const values = <String>[queueAdd, queueRemove];'),
      );
      expect(output, contains('abstract final class RoomEventTypes {'));
      expect(
        output,
        contains("static const playbackUpdated = 'playback.updated';"),
      );
      expect(
        output,
        contains("static const membersUpdated = 'members.updated';"),
      );
      expect(output, isNot(contains("static const hello = 'hello';")));
    });

    test('array bounds are accepted and left to the server', () {
      final idl = _minimalIdl();
      _schema(idl, <String>[r'$defs', 'Sample', 'properties', 'tags'])
        ..['minItems'] = 1
        ..['maxItems'] = 1000;

      final output = generateProtocol(idl);

      expect(output, contains('final List<Source> tags;'));
    });

    test('unsupported keywords fail with their IDL path', () {
      final idl = _minimalIdl();
      _schema(idl, <String>[
        r'$defs',
        'Sample',
        'properties',
        'note',
      ])['format'] = 'uri';

      expect(
        () => generateProtocol(idl),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains(r'$defs.Sample.properties.note'),
              contains('format'),
            ),
          ),
        ),
      );
    });

    test('unsupported shapes fail with their IDL path', () {
      final idl = _minimalIdl();
      _schema(idl, <String>[
        r'$defs',
        'Sample',
        'properties',
      ])['inline'] = <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
      };

      expect(
        () => generateProtocol(idl),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(r'$defs.Sample.properties.inline'),
          ),
        ),
      );
    });

    test('class name conflicts fail with both IDL paths', () {
      final idl = _minimalIdl();
      (idl['x-events']! as List<Object?>).add(<String, Object?>{
        'type': 'sample',
        'data': <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'properties': <String, Object?>{},
        },
      });

      expect(
        () => generateProtocol(idl),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('x-events[2]'), contains(r'$defs.Sample')),
          ),
        ),
      );
    });

    test('admin operations generate their classes', () {
      final output = generateProtocol(_minimalIdl());

      expect(output, contains('class AdminOnly {'));
      expect(output, contains('final String secret;'));
    });

    test('real IDL emits the defs reachable from every operation', () {
      final output = generateProtocol(_backendIdl());

      for (final declaration in <String>[
        'class Empty {',
        'class ErrorInfo {',
        'class Track {',
        'class TrackMeta {',
        'class TrackSummary {',
        'class PlaylistSummary {',
        'class Member {',
        'class Members {',
        'class Entry {',
        'class NowPlaying {',
        'class RoomInfo {',
        'class RoomSnapshot {',
        'class RoomListing {',
        'enum ErrorCode {',
        'enum Source {',
        'enum PlayMode {',
        'enum RoomKind {',
        'enum EntryStatus {',
        'enum ActivityKind {',
        'class APIKey {',
        'class StoredMedia {',
        'class SourceAccount {',
        'enum QQLoginType {',
        'class QRLogin {',
        'enum QRLoginStatus {',
        'class QRLoginResult {',
        'class AdminCreateRoomRequest {',
        'class AdminUpdateRoomRequest {',
        'class AdminGetRoomApiKeyResponse {',
        'class AdminSetYoutubeCredentialRequest {',
        'class AdminUpdateSiteResponse {',
      ]) {
        expect(output, contains(declaration));
      }
    }, skip: _backendSkip);
  });

  group('HTTP output', () {
    test('names every endpoint as a constant, admin ones included', () {
      final output = generateHttp(_minimalIdl());

      expect(output, contains("import '$_runtimeImport';"));
      expect(output, contains('abstract final class RestEndpoints {'));
      expect(output, contains('static const createMember = RestEndpoint('));
      expect(output, contains('static const queueAdd = RestEndpoint('));
      expect(output, contains('static const queueRemove = RestEndpoint('));
      expect(output, contains("pathParameters: <String>['entryId'],"));
      expect(output, contains('auth: HttpAuth.ticket,'));
      expect(output, contains('static const adminListRooms = RestEndpoint('));
      expect(output, contains('auth: HttpAuth.admin,'));
      expect(output, contains("path: '/api/admin/rooms',"));
      expect(
        output,
        contains(
          'static const values = <RestEndpoint>[queueAdd, queueRemove, '
          'createMember, adminListRooms];',
        ),
      );
      expect(output, isNot(contains('class RestEndpoint {')));
    });

    test('unsupported auth values fail with their IDL path', () {
      final idl = _minimalIdl();
      (idl['x-http']! as List<Object?>).add(<String, Object?>{
        'name': 'rootOnly',
        'method': 'GET',
        'path': '/api/root',
        'auth': 'root',
        'response': <String, Object?>{r'$ref': r'#/$defs/Empty'},
      });

      expect(
        () => generateHttp(idl),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('x-http[2].auth'),
              contains('unsupported value "root"'),
            ),
          ),
        ),
      );
    });

    test('real IDL names all 28 admin endpoints', () {
      final output = generateHttp(_backendIdl());

      for (final name in <String>[
        'adminListRooms',
        'adminCreateRoom',
        'adminUpdateRoom',
        'adminDeleteRoom',
        'adminGetRoomApiKey',
        'adminResetRoomApiKey',
        'adminGetNeteaseCredential',
        'adminGetQqCredential',
        'adminStartNeteaseLogin',
        'adminCheckNeteaseLogin',
        'adminStartQqLogin',
        'adminCheckQqLogin',
        'adminGetBilibiliCredential',
        'adminStartBilibiliLogin',
        'adminCheckBilibiliLogin',
        'adminGetYoutubeCredential',
        'adminSetYoutubeCredential',
        'adminDeleteYoutubeCredential',
        'adminGetGithubCredential',
        'adminSetGithubCredential',
        'adminDeleteGithubCredential',
        'adminListMedia',
        'adminRemoveMedia',
        'adminUpdateSite',
        'adminOpenRegistration',
        'adminCloseRegistration',
        'adminGetAccount',
        'adminResetAccountPassword',
      ]) {
        expect(output, contains('static const $name = RestEndpoint('));
      }
      expect(RegExp('auth: HttpAuth.admin,').allMatches(output).length, 28);
    }, skip: _backendSkip);

    test('endpoint name conflicts fail with both IDL paths', () {
      final idl = _minimalIdl();
      (idl['x-http']! as List<Object?>).add(<String, Object?>{
        'name': 'queueAdd',
        'method': 'GET',
        'path': '/api/queue-add',
        'auth': 'none',
        'response': <String, Object?>{r'$ref': r'#/$defs/Empty'},
      });

      expect(
        () => generateHttp(idl),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('x-http[2]'), contains('x-requests[0]')),
          ),
        ),
      );
    });
  });

  group('protocol.lock', () {
    const url =
        'https://github.com/DiheMoe/alisten/releases/download/v0.2.3/idl.json';
    final digest = 'a1' * 32;

    test('parses the attachment URL and the sha256 line', () {
      for (final text in ['$url\nsha256:$digest\n', '$url\nsha256:$digest']) {
        final lock = parseProtocolLock(text);

        expect(lock.url, Uri.parse(url));
        expect(lock.digest, digest);
      }
    });

    test('rejects any carriage return and asks for LF line endings', () {
      for (final text in [
        '$url\r\nsha256:$digest\r\n',
        '$url\r\nsha256:$digest',
        '$url\nsha256:$digest\r\n',
        '$url\rsha256:$digest\n',
        '$url\nsha256:$digest\r',
      ]) {
        expect(
          () => parseProtocolLock(text),
          _throwsSourceError(allOf(contains('protocol.lock'), contains('LF'))),
          reason: jsonEncode(text),
        );
      }
    });

    test('the committed lock is a release attachment', () {
      final lock = parseProtocolLock(File('protocol.lock').readAsStringSync());

      expect(
        lock.url.toString(),
        startsWith('https://github.com/DiheMoe/alisten/releases/download/'),
      );
    });

    test('rejects missing and extra lines', () {
      for (final text in [
        '',
        '\n',
        url,
        '$url\n',
        'sha256:$digest\n',
        '$url\n\nsha256:$digest\n',
        '$url\nsha256:$digest\nextra\n',
        '$url\nsha256:$digest\n\n',
      ]) {
        expect(
          () => parseProtocolLock(text),
          _throwsSourceError(contains('protocol.lock')),
          reason: jsonEncode(text),
        );
      }
    });

    test('rejects addresses that are not plain https', () {
      for (final bad in [
        'http://github.com/DiheMoe/alisten/releases/download/v1/idl.json',
        'file:///tmp/idl.json',
        'ftp://github.com/idl.json',
        '../alisten/protocol/idl.json',
        'https://',
        'https://user:secret@github.com/idl.json',
        'https://github.com/a b/idl.json',
        ' $url',
      ]) {
        expect(
          () => parseProtocolLock('$bad\nsha256:$digest\n'),
          _throwsSourceError(contains('https')),
          reason: bad,
        );
      }
    });

    test('rejects malformed digests', () {
      for (final bad in [
        digest,
        'sha256:',
        'sha256:${digest.substring(1)}',
        'sha256:${digest}0',
        'sha256:${digest.toUpperCase()}',
        'sha256:${'g' * 64}',
        'sha1:${'a1' * 20}',
        'sha256: $digest',
        'sha256:$digest ',
      ]) {
        expect(
          () => parseProtocolLock('$url\n$bad\n'),
          _throwsSourceError(contains('sha256')),
          reason: bad,
        );
      }
    });
  });

  group('IDL digest', () {
    final bytes = utf8.encode('{"title":"x"}');
    final digest = sha256.convert(bytes).toString();

    test('accepts the pinned content', () {
      verifyIdlDigest(bytes, digest);
    });

    test('rejects other content and names both digests', () {
      final other = utf8.encode('{"title":"y"}');

      expect(
        () => verifyIdlDigest(other, digest),
        _throwsSourceError(
          allOf(
            contains('sha256'),
            contains(digest),
            contains(sha256.convert(other).toString()),
          ),
        ),
      );
    });
  });

  group('locked IDL', () {
    final bytes = utf8.encode('{"title":"x"}');
    final lock = ProtocolLock(
      url: Uri.parse('https://example.com/releases/v1/idl.json'),
      digest: sha256.convert(bytes).toString(),
    );

    test('downloads the lock address and returns verified content', () async {
      final requested = <Uri>[];

      final result = await fetchLockedIdl(
        lock,
        download: (uri) async {
          requested.add(uri);
          return bytes;
        },
      );

      expect(result, bytes);
      expect(requested, [lock.url]);
    });

    test('does not return content whose digest differs', () {
      expect(
        fetchLockedIdl(lock, download: (_) async => utf8.encode('{}')),
        _throwsSourceError(contains('sha256')),
      );
    });

    test('lets download failures through', () {
      expect(
        fetchLockedIdl(
          lock,
          download: (_) => throw ProtocolSourceException('offline'),
        ),
        _throwsSourceError(equals('offline')),
      );
    });
  });

  group('IDL source', () {
    final bytes = utf8.encode('{"title":"x"}');
    final url = Uri.parse('https://example.com/releases/v1/idl.json');
    late Directory scratch;
    late File lockFile;
    late List<Uri> requested;
    late List<String> notices;

    setUp(() async {
      scratch = await Directory.systemTemp.createTemp('alisten_idl_source_');
      lockFile = File('${scratch.path}/protocol.lock');
      requested = [];
      notices = [];
    });

    tearDown(() => scratch.delete(recursive: true));

    Future<List<int>> read(String? source) {
      return readIdlSource(
        source,
        lockFile: lockFile,
        notice: notices.add,
        download: (uri) async {
          requested.add(uri);
          return bytes;
        },
      );
    }

    test(
      'without --source downloads and verifies the locked address',
      () async {
        await lockFile.writeAsString('$url\nsha256:${sha256.convert(bytes)}\n');

        expect(await read(null), bytes);
        expect(requested, [url]);
        expect(notices, isEmpty);

        await lockFile.writeAsString('$url\nsha256:${'0' * 64}\n');
        await expectLater(read(null), _throwsSourceError(contains('sha256')));
      },
    );

    test('without --source needs protocol.lock', () {
      expect(
        read(null),
        _throwsSourceError(
          allOf(contains('protocol.lock'), contains('--source')),
        ),
      );
      expect(requested, isEmpty);
    });

    test('a local path is read as is, without protocol.lock', () async {
      final idl = File('${scratch.path}/idl.json')..writeAsBytesSync(bytes);

      expect(await read(idl.path), bytes);
      expect(requested, isEmpty);
      expect(notices, isEmpty);
    });

    test('an https address is not verified and says so', () async {
      expect(await read('$url'), bytes);
      expect(requested, [url]);
      expect(notices.single, contains('未校验'));
    });

    test('other schemes are refused before any download', () async {
      for (final bad in [
        'http://example.com/idl.json',
        'file:///tmp/idl.json',
      ]) {
        await expectLater(read(bad), _throwsSourceError(contains('https')));
      }
      expect(requested, isEmpty);
      expect(notices, isEmpty);
    });
  });

  group('IDL download', () {
    final start = Uri.parse(
      'https://github.com/DiheMoe/alisten/releases/download/v0.2.3/idl.json',
    );
    final body = utf8.encode('{"title":"x"}');

    Future<List<int>> download(
      _FakeClient client, {
      Uri? uri,
      Duration timeout = const Duration(seconds: 5),
    }) {
      return downloadIdl(
        uri ?? start,
        newClient: () => client,
        timeout: timeout,
      );
    }

    test('returns the body of a 200 response', () async {
      final client = _FakeClient((_) => _FakeResponse(chunks: [body]));

      expect(await download(client), body);
      expect(client.requested, [start]);
      expect(client.requests.single.followRedirects, isFalse);
      expect(client.connectionTimeout, isNotNull);
      expect(client.forceClosed, isTrue);
    });

    test('refuses addresses that are not https before connecting', () async {
      for (final bad in [
        'http://github.com/DiheMoe/alisten/releases/download/v1/idl.json',
        'file:///tmp/idl.json',
        'https://user:secret@github.com/idl.json',
        'https:///idl.json',
      ]) {
        var created = false;
        await expectLater(
          downloadIdl(
            Uri.parse(bad),
            newClient: () {
              created = true;
              return _FakeClient((_) => _FakeResponse(chunks: [body]));
            },
          ),
          _throwsSourceError(contains('https')),
          reason: bad,
        );
        expect(created, isFalse, reason: bad);
      }
    });

    test('follows https redirects, relative ones included', () async {
      final storage = Uri.parse('https://objects.example.com/blob/abc?sig=1');
      final client = _FakeClient((uri) {
        if (uri == start) {
          return _FakeResponse(statusCode: 302, location: '$storage');
        }
        if (uri == storage) {
          return _FakeResponse(statusCode: 307, location: '/blob/final');
        }
        return _FakeResponse(chunks: [body]);
      });

      expect(await download(client), body);
      expect(client.requested, [
        start,
        storage,
        Uri.parse('https://objects.example.com/blob/final'),
      ]);
      expect(client.requests.every((r) => !r.followRedirects), isTrue);
    });

    test('refuses a redirect away from https', () async {
      for (final location in [
        'http://objects.example.com/blob/abc?sig=secret',
        'file:///etc/passwd',
        'https://user:secret@objects.example.com/blob',
      ]) {
        final client = _FakeClient((uri) {
          return uri == start
              ? _FakeResponse(statusCode: 302, location: location)
              : _FakeResponse(chunks: [body]);
        });

        await expectLater(
          download(client),
          _throwsSourceError(
            allOf(contains('https'), isNot(contains('sig=secret'))),
          ),
          reason: location,
        );
        expect(client.requested, [start], reason: location);
      }
    });

    test('refuses a later hop that leaves https', () async {
      final storage = Uri.parse('https://objects.example.com/blob/abc?sig=1');
      final client = _FakeClient((uri) {
        if (uri == start) {
          return _FakeResponse(statusCode: 302, location: '$storage');
        }
        if (uri == storage) {
          return _FakeResponse(
            statusCode: 302,
            location: 'http://objects.example.com/blob/final?sig=secret',
          );
        }
        return _FakeResponse(chunks: [body]);
      });

      await expectLater(
        download(client),
        _throwsSourceError(
          allOf(contains('https'), isNot(contains('sig=secret'))),
        ),
      );
      expect(client.requested, [start, storage]);
    });

    test('refuses a redirect without a Location', () {
      final client = _FakeClient((_) => _FakeResponse(statusCode: 302));

      expect(download(client), _throwsSourceError(contains('Location')));
    });

    test('gives up on redirect loops', () {
      final client = _FakeClient(
        (_) => _FakeResponse(statusCode: 302, location: '$start'),
      );

      expect(download(client), _throwsSourceError(contains('redirect')));
    });

    test('rejects other statuses with the status code', () {
      final client = _FakeClient((_) => _FakeResponse(statusCode: 404));

      expect(download(client), _throwsSourceError(contains('404')));
    });

    test('rejects bodies over 1 MiB, announced or streamed', () async {
      const limit = 1024 * 1024;
      final announced = _FakeClient(
        (_) => _FakeResponse(contentLength: limit + 1, chunks: [body]),
      );
      final streamed = _FakeClient(
        (_) => _FakeResponse(
          chunks: [
            List<int>.filled(limit ~/ 2, 0),
            List<int>.filled(limit ~/ 2, 0),
            [0],
          ],
        ),
      );
      final exact = _FakeClient(
        (_) => _FakeResponse(
          chunks: [
            List<int>.filled(limit ~/ 2, 0),
            List<int>.filled(limit ~/ 2, 0),
          ],
        ),
      );

      await expectLater(
        download(announced),
        _throwsSourceError(contains('1 MiB')),
      );
      await expectLater(
        download(streamed),
        _throwsSourceError(contains('1 MiB')),
      );
      expect((await download(exact)).length, limit);
    });

    test('times out as a whole and closes the client', () async {
      final client = _FakeClient((_) => Completer<_FakeResponse>().future);

      await expectLater(
        download(client, timeout: const Duration(milliseconds: 50)),
        _throwsSourceError(contains('timed out')),
      );
      expect(client.forceClosed, isTrue);
    });

    test('reports connection failures with the host and error type', () async {
      final client = _FakeClient(
        (_) => throw const SocketException('Connection refused'),
      );

      await expectLater(
        download(client),
        _throwsSourceError(
          allOf(contains('github.com'), contains('SocketException')),
        ),
      );
      expect(client.forceClosed, isTrue);
    });

    test('never repeats a signed address from an underlying error', () async {
      final signed = Uri.parse('https://o.example.com/blob/x?sig=SECRET');
      final client = _FakeClient(
        (_) => throw HttpException('Connection closed', uri: signed),
      );

      await expectLater(
        download(client),
        _throwsSourceError(
          allOf(
            contains('github.com'),
            contains('HttpException'),
            isNot(contains('SECRET')),
            isNot(contains('o.example.com')),
            isNot(contains('/blob/x')),
          ),
        ),
      );
    });
  });

  test('a digest mismatch exits non-zero and writes nothing', () async {
    final package = await Directory.systemTemp.createTemp(
      'alisten_protocol_mismatch_',
    );
    addTearDown(() => package.delete(recursive: true));
    final served = utf8.encode(jsonEncode(_minimalIdl()));
    final pinned = sha256.convert(utf8.encode('some other content'));
    await File('${package.path}/protocol.lock').writeAsString(
      'https://example.com/releases/v1/idl.json\nsha256:$pinned\n',
    );

    for (final arguments in [
      const <String>[],
      const <String>['--check'],
    ]) {
      final requested = <Uri>[];
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runGenerator(
        arguments,
        packageRoot: package.uri,
        out: out,
        err: err,
        download: (uri) async {
          requested.add(uri);
          return served;
        },
      );

      expect(code, isNot(0), reason: '$arguments');
      expect(requested, [
        Uri.parse('https://example.com/releases/v1/idl.json'),
      ], reason: '$arguments');
      expect(
        err.toString(),
        allOf(
          contains('does not match protocol.lock'),
          contains('$pinned'),
          contains('${sha256.convert(served)}'),
        ),
        reason: '$arguments',
      );
      expect(out.toString(), isEmpty, reason: '$arguments');
      expect(
        Directory('${package.path}/lib').existsSync(),
        isFalse,
        reason: '$arguments',
      );
    }
  });

  test('CLI without --source reads protocol.lock and fails clearly', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'alisten_protocol_lock_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final script = File('${sandbox.path}/tool/protocol_generator.dart');
    await script.parent.create();
    await File('tool/protocol_generator.dart').copy(script.path);
    final dart = await _dartExecutable(sandbox);
    final packages = File('.dart_tool/package_config.json').absolute.path;
    final lock = File('${sandbox.path}/protocol.lock');
    final zeros = 'sha256:${'0' * 64}';

    Future<ProcessResult> run(List<String> arguments) {
      return Process.run(
        dart,
        <String>['--packages=$packages', script.path, ...arguments],
        environment: <String, String>{'no_proxy': '127.0.0.1'},
      );
    }

    void expectFailure(ProcessResult result, Matcher message) {
      expect(result.exitCode, isNot(0), reason: '${result.stdout}');
      expect(result.stderr, message);
      expect(Directory('${sandbox.path}/lib').existsSync(), isFalse);
    }

    expectFailure(
      await run(const <String>['--check']),
      contains('protocol.lock'),
    );

    await lock.writeAsString('https://127.0.0.1:1/idl.json\n');
    expectFailure(await run(const <String>['--check']), contains('sha256'));

    await lock.writeAsString('http://127.0.0.1:1/idl.json\n$zeros\n');
    expectFailure(await run(const <String>['--check']), contains('https'));

    await lock.writeAsString('https://127.0.0.1:1/idl.json\n$zeros\n');
    expectFailure(
      await run(const <String>[]),
      allOf(contains('download'), contains('127.0.0.1')),
    );

    expectFailure(
      await run(const <String>['--source', 'http://127.0.0.1:1/idl.json']),
      contains('https'),
    );
    expectFailure(
      await run(const <String>['--source', 'https://127.0.0.1:1/idl.json']),
      contains('download'),
    );
  }, timeout: _processTimeout);

  test(
    'generated code compiles and decodes leniently in a standalone package',
    () async {
      final package = await Directory.systemTemp.createTemp(
        'alisten_protocol_compile_',
      );
      addTearDown(() => package.delete(recursive: true));
      final idl = _minimalIdl();
      // 生成的文件以 package URI 导入运行时，所以独立包须沿用应用的包名和目录
      // 结构。
      await Directory('${package.path}/lib/core/protocol')
          .create(recursive: true);
      await Directory('${package.path}/bin').create();
      await File('${package.path}/pubspec.yaml')
          .writeAsString('name: alisten\nenvironment:\n  sdk: ^3.8.0\n');
      await File('${package.path}/lib/core/protocol/protocol.gen.dart')
          .writeAsString(generateProtocol(idl));
      await File('${package.path}/lib/core/protocol/http.gen.dart')
          .writeAsString(generateHttp(idl));
      await File(_runtimePath)
          .copy('${package.path}/lib/core/protocol/protocol_runtime.dart');
      await File('${package.path}/bin/check.dart')
          .writeAsString(_decodeAssertions);

      final result = await Process.run('dart', <String>[
        'run',
        '--enable-asserts',
        'bin/check.dart',
      ], workingDirectory: package.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: _processTimeout,
  );

  test('CLI writes beside the script, formats without PATH, and --check never '
      'writes', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'alisten_protocol_cli_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final script = File('${sandbox.path}/tool/protocol_generator.dart');
    await script.parent.create();
    await File('tool/protocol_generator.dart').copy(script.path);
    final elsewhere = await Directory('${sandbox.path}/elsewhere').create();
    await File('${elsewhere.path}/idl.json')
        .writeAsString(jsonEncode(_minimalIdl()));
    final dart = await _dartExecutable(sandbox);
    final packages = File('.dart_tool/package_config.json').absolute.path;

    Future<ProcessResult> run(List<String> arguments) {
      return Process.run(
        dart,
        <String>[
          '--packages=$packages',
          script.path,
          '--source',
          'idl.json',
          ...arguments,
        ],
        workingDirectory: elsewhere.path,
        environment: <String, String>{'PATH': elsewhere.path},
      );
    }

    final generated = await run(const <String>[]);
    expect(
      generated.exitCode,
      0,
      reason: '${generated.stdout}\n${generated.stderr}',
    );
    expect(Directory('${elsewhere.path}/lib').existsSync(), isFalse);
    final protocol = File(
      '${sandbox.path}/lib/core/protocol/protocol.gen.dart',
    );
    final http = File('${sandbox.path}/lib/core/protocol/http.gen.dart');
    final expectedProtocol = await protocol.readAsString();
    final expectedHttp = await http.readAsString();
    expect(expectedProtocol, contains('abstract final class RoomEventTypes'));
    expect(expectedHttp, contains('abstract final class RestEndpoints'));

    final checked = await run(const <String>['--check']);
    expect(checked.exitCode, 0, reason: '${checked.stdout}\n${checked.stderr}');
    expect(await protocol.readAsString(), expectedProtocol);
    expect(await http.readAsString(), expectedHttp);

    const stale = '// stale output must not be overwritten by --check\n';
    await protocol.writeAsString(stale);
    final mismatch = await run(const <String>['--check']);
    expect(mismatch.exitCode, isNot(0));
    expect(await protocol.readAsString(), stale);
    expect(await http.readAsString(), expectedHttp);
  }, timeout: _processTimeout);
}

/// 直接定位 Dart VM，子进程不依赖 PATH 中的 `dart`。
Future<String> _dartExecutable(Directory scratch) async {
  final probe = File('${scratch.path}/dart_executable.dart');
  await probe.writeAsString(
    "import 'dart:io';\n\n"
    'void main() => stdout.write(Platform.resolvedExecutable);\n',
  );
  final result = await Process.run('dart', <String>[probe.path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return result.stdout as String;
}

Map<String, Object?> _backendIdl() {
  final decoded = jsonDecode(
    File(_backendIdlPath).readAsStringSync(),
  ) as Map<String, dynamic>;
  return decoded.cast<String, Object?>();
}

Matcher _throwsSourceError(Matcher message) => throwsA(
  isA<ProtocolSourceException>().having(
    (error) => error.message,
    'message',
    message,
  ),
);

// 下载器只能用到这里实现的成员；用到其他成员（凭据、请求头、Cookie 等）时
// 抛出 NoSuchMethodError，测试失败。
final class _FakeClient implements HttpClient {
  _FakeClient(this._respond);

  final FutureOr<_FakeResponse> Function(Uri uri) _respond;
  final requested = <Uri>[];
  final requests = <_FakeRequest>[];
  var forceClosed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    final request = _FakeRequest(await _respond(url));
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => forceClosed = force;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._response);

  final _FakeResponse _response;

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeResponse({
    this.statusCode = 200,
    this.location,
    this.contentLength = -1,
    this.chunks = const <List<int>>[],
  });

  @override
  final int statusCode;

  @override
  final int contentLength;

  final String? location;
  final List<List<int>> chunks;

  @override
  HttpHeaders get headers => _FakeHeaders(location);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.fromIterable(chunks).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this._location);

  final String? _location;

  @override
  String? value(String name) =>
      name.toLowerCase() == HttpHeaders.locationHeader ? _location : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _schema(Map<String, Object?> idl, List<String> path) {
  Object? value = idl;
  for (final key in path) {
    value = (value! as Map<String, Object?>)[key];
  }
  return value! as Map<String, Object?>;
}

const _decodeAssertions = r'''
import 'package:alisten/core/protocol/http.gen.dart';
import 'package:alisten/core/protocol/protocol.gen.dart';

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void checkThrows<T>(void Function() body, String description) {
  try {
    body();
  } on Object catch (error) {
    if (error is T) return;
    throw StateError('$description: threw $error');
  }
  throw StateError('$description: did not throw');
}

void main() {
  final json = <String, Object?>{
    'source': 'link',
    'id': 'not a link',
    'by': null,
    'tags': <Object?>['qq'],
    'gain': 1,
    'count': 0,
    'live': true,
    'note': 'longer than three',
    'futureField': <String, Object?>{'nested': true},
  };
  final sample = Sample.fromJson(json);
  check(sample.id == 'not a link', 'allOf rules are not applied');
  check(sample.note == 'longer than three', 'maxLength is not applied');
  check(sample.count == 0, 'minimum is not applied');
  check(sample.gain == 1.0, 'integers decode as numbers');
  check(sample.by == null, 'required nullable fields accept null');
  check(sample.tags.single == Source.qq, 'arrays of enums decode');
  check(sample.live, 'booleans decode');
  final encoded = sample.toJson();
  check(!encoded.containsKey('futureField'), 'unknown fields are dropped');
  check(encoded.containsKey('by') && encoded['by'] == null, 'null is kept');
  check(encoded['tags'] is List && (encoded['tags'] as List).single == 'qq',
      'enum arrays encode wire values');
  final withMember = Sample.fromJson(<String, Object?>{
    ...json,
    'by': <String, Object?>{'id': 'm', 'name': 'n', 'avatarHash': ''},
  });
  check(withMember.by?.name == 'n', 'nullable objects decode');
  check(Sample.fromJson(<String, Object?>{...json}..remove('note')).note == null,
      'optional fields may be absent');

  checkThrows<ProtocolMismatchException>(
    () => Sample.fromJson(<String, Object?>{...json, 'source': 'youtube'}),
    'unknown enum value',
  );
  checkThrows<FormatException>(
    () => Sample.fromJson(<String, Object?>{...json}..remove('by')),
    'missing required nullable field',
  );
  checkThrows<FormatException>(
    () => Sample.fromJson(<String, Object?>{...json, 'count': '1'}),
    'wrong JSON type',
  );
  checkThrows<FormatException>(
    () => Sample.fromJson(<String, Object?>{...json, 'note': null}),
    'explicit null for an optional field',
  );

  const byChoice = QueueAddRequest(choice: 'x');
  check(byChoice.toJson().length == 1, 'optional fields are omitted');
  checkThrows<AssertionError>(QueueAddRequest.new, 'oneOf requires a branch');
  final source = Source.fromJson('qq');
  checkThrows<AssertionError>(
    () => QueueAddRequest(choice: 'x', source: source, keyword: 'k'),
    'oneOf allows only one branch',
  );
  check(const Empty().toJson().isEmpty, 'empty objects encode');
  check(PlaybackUpdated.fromJson(<String, Object?>{'member': null}).member ==
      null, 'event data decodes');

  check(RoomRequestTypes.queueAdd == 'queue.add', 'request constants');
  check(RoomRequestTypes.values.length == 2, 'request constant list');
  check(RoomEventTypes.values.length == 2, 'event constant list');
  check(WsCloseCodes.clientOutdated == 4426, 'close codes');
  check(
    RestEndpoints.queueRemove.buildPath(<String, String>{'entryId': 'a/b'}) ==
        '/api/room/queue/a%2Fb',
    'endpoint constants',
  );
  check(RestEndpoints.queueRemove.auth == HttpAuth.ticket, 'room auth');
  check(RestEndpoints.adminListRooms.auth == HttpAuth.admin, 'admin auth');
  check(AdminOnly.fromJson(<String, Object?>{'secret': 's'}).secret == 's',
      'admin response decodes');
  check(RestEndpoints.values.length == 4, 'endpoint list');
}
''';

Map<String, Object?> _minimalIdl() {
  final decoded = jsonDecode(r'''
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Minimal",
  "$defs": {
    "Source": {
      "type": "string",
      "enum": ["netease", "qq", "link"]
    },
    "Sample": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "source": {"$ref": "#/$defs/Source"},
        "id": {"type": "string", "description": "a link when source is link"},
        "by": {"anyOf": [{"$ref": "#/$defs/Member"}, {"type": "null"}]},
        "note": {"type": "string", "maxLength": 3},
        "tags": {"type": "array", "items": {"$ref": "#/$defs/Source"}},
        "gain": {"type": "number"},
        "count": {"type": "integer", "minimum": 1},
        "live": {"type": "boolean"}
      },
      "required": ["source", "id", "by", "tags", "gain", "count", "live"],
      "allOf": [
        {
          "if": {"properties": {"source": {"const": "link"}}, "required": ["source"]},
          "then": {"properties": {"id": {"$ref": "#/$defs/Link"}}}
        }
      ]
    },
    "Member": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "name": {"type": "string"},
        "id": {"type": "string"},
        "avatarHash": {"type": "string"}
      },
      "required": ["name", "id", "avatarHash"]
    },
    "Link": {"type": "string", "x-url": true, "x-maxBytes": 2048},
    "Empty": {
      "type": "object",
      "additionalProperties": false,
      "properties": {}
    },
    "AdminOnly": {
      "type": "object",
      "additionalProperties": false,
      "properties": {"secret": {"type": "string"}},
      "required": ["secret"]
    }
  },
  "x-ws": {
    "requests": [
      {
        "type": "hello",
        "request": {
          "type": "object",
          "additionalProperties": false,
          "properties": {"protocolVersion": {"type": "string"}},
          "required": ["protocolVersion"]
        },
        "response": {
          "type": "object",
          "additionalProperties": false,
          "properties": {"sample": {"$ref": "#/$defs/Sample"}},
          "required": ["sample"]
        }
      }
    ],
    "events": [
      {"type": "error", "data": {"$ref": "#/$defs/Member"}}
    ],
    "closeCodes": [
      {"name": "clientOutdated", "code": 4426, "description": "upgrade"}
    ]
  },
  "x-requests": [
    {
      "type": "queue.add",
      "http": {"method": "POST", "path": "/api/room/queue", "status": 201, "location": true},
      "request": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "choice": {"type": "string"},
          "source": {"$ref": "#/$defs/Source"},
          "keyword": {"type": "string"},
          "requester": {"type": "string"}
        },
        "oneOf": [
          {"required": ["choice"], "properties": {"choice": {}, "requester": {}}, "additionalProperties": false},
          {"required": ["source", "keyword"], "properties": {"source": {}, "keyword": {}, "requester": {}}, "additionalProperties": false}
        ]
      },
      "response": {"$ref": "#/$defs/Empty"}
    },
    {
      "type": "queue.remove",
      "http": {"method": "DELETE", "path": "/api/room/queue/{entryId}", "status": 204},
      "request": {
        "type": "object",
        "additionalProperties": false,
        "properties": {"entryId": {"type": "string"}},
        "required": ["entryId"]
      },
      "response": {"$ref": "#/$defs/Empty"}
    }
  ],
  "x-events": [
    {
      "type": "playback.updated",
      "data": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "member": {"anyOf": [{"$ref": "#/$defs/Member"}, {"type": "null"}]}
        },
        "required": ["member"]
      }
    },
    {"type": "members.updated", "data": {"$ref": "#/$defs/Member"}}
  ],
  "x-http": [
    {
      "name": "createMember",
      "method": "POST",
      "path": "/api/members",
      "auth": "none",
      "status": 201,
      "request": {
        "type": "object",
        "additionalProperties": false,
        "properties": {}
      },
      "response": {
        "type": "object",
        "additionalProperties": false,
        "properties": {"member": {"$ref": "#/$defs/Member"}},
        "required": ["member"]
      }
    },
    {
      "name": "adminListRooms",
      "method": "GET",
      "path": "/api/admin/rooms",
      "auth": "admin",
      "response": {"$ref": "#/$defs/AdminOnly"}
    }
  ]
}
''') as Map<String, dynamic>;
  return decoded.cast<String, Object?>();
}
