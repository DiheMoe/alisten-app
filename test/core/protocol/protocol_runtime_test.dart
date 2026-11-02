import 'dart:convert';
import 'dart:io';

import 'package:alisten/core/protocol/protocol_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

// 与后端交叉核对的测试要求后端仓库与本仓库并列检出；CI 不检出后端，因此跳过。
const _backendLinkCasesPath = '../alisten/protocol/testdata/Link.json';
final _backendSkip = Directory('../alisten/protocol').existsSync()
    ? null
    : 'needs the backend checked out at ../alisten';

void main() {
  group('link validation', () {
    test('agrees with every case in the backend Link.json', () {
      final decoded = jsonDecode(
        File(_backendLinkCasesPath).readAsStringSync(),
      ) as List<dynamic>;
      expect(decoded, isNotEmpty);
      for (final value in decoded) {
        final testCase = (value as Map<String, dynamic>)
            .cast<String, Object?>();
        final link = testCase['value']! as String;
        final valid = testCase['valid']! as bool;
        final note = testCase['note']! as String;
        expect(isValidLink(link), valid, reason: '$note: $link');
      }
    }, skip: _backendSkip);

    test('rejects IPv4 octets with leading zeros like Go netip', () {
      for (final link in <String>[
        'https://01.2.3.4/a',
        'https://1.2.3.00/a',
        'https://010.1.1.1/a',
        'https://[::ffff:01.2.3.4]/a',
        'https://[::ffff:1.2.3.004]/a',
      ]) {
        expect(isValidLink(link), isFalse, reason: link);
      }
      for (final link in <String>[
        'https://0.0.0.0/a',
        'https://1.2.3.4/a',
        'https://[::ffff:1.2.3.4]/a',
      ]) {
        expect(isValidLink(link), isTrue, reason: link);
      }
    });

    test('rejects hexadecimal numeric final labels', () {
      for (final link in <String>[
        'https://example.0x10/a',
        'https://example.0XFF/a',
        'https://example.0x/a',
      ]) {
        expect(isValidLink(link), isFalse, reason: link);
      }
    });

    test('accepts an uncompressed IPv6 address with an IPv4 tail', () {
      expect(isValidLink('https://[0:0:0:0:0:ffff:192.0.2.1]/a'), isTrue);
    });
  });

  group('link normalization', () {
    test('lowercases only ASCII letters in scheme and authority', () {
      expect(normalizeLink('https://ÜBER.Example/a'), 'https://Über.example/a');
      expect(
        normalizeLink('hTTp://Example.com/A?b=2&a=1#Frag'),
        'http://example.com/A?b=2&a=1#Frag',
      );
      expect(
        normalizeLink('HTTPS://[2606:4700:4700::ABCD]:8443/A'),
        'https://[2606:4700:4700::abcd]:8443/A',
      );
    });

    test('rejects links that fail validation', () {
      expect(
        () => normalizeLink('https://user@example.com/a'),
        throwsFormatException,
      );
    });
  });

  group('JSON readers', () {
    test('a protocol mismatch is still a FormatException', () {
      const error = ProtocolMismatchException('Source has no value "x"');

      expect(error, isA<FormatException>());
      expect(error.message, 'Source has no value "x"');
      expect(error.toString(), contains('Source has no value "x"'));
    });

    test('unknown enum values are protocol mismatches', () {
      expect(
        readEnum('b', const <String>['a', 'b'], (value) => value, 'Letter'),
        'b',
      );
      expect(
        () => readEnum('c', const <String>['a'], (value) => value, 'Letter'),
        throwsA(
          isA<ProtocolMismatchException>().having(
            (error) => error.message,
            'message',
            contains('Letter'),
          ),
        ),
      );
      expect(
        () => readEnum(1, const <String>['a'], (value) => value, 'Letter'),
        throwsA(
          allOf(
            isA<FormatException>(),
            isNot(isA<ProtocolMismatchException>()),
          ),
        ),
      );
    });

    test('required fields may be null but must be present', () {
      final json = <String, Object?>{'present': null};

      expect(requiredField(json, 'present', 'Owner'), isNull);
      expect(
        () => requiredField(json, 'absent', 'Owner'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Owner.absent'),
          ),
        ),
      );
    });

    test('optional fields may be absent but not null', () {
      expect(optionalField(<String, Object?>{}, 'note', 'Owner'), isNull);
      expect(
        optionalField(<String, Object?>{'note': 'x'}, 'note', 'Owner'),
        'x',
      );
      expect(
        () => optionalField(<String, Object?>{'note': null}, 'note', 'Owner'),
        throwsFormatException,
      );
    });

    test('value readers check only the JSON type', () {
      expect(readString('', 'path'), '');
      expect(readInt(-3, 'path'), -3);
      expect(readNumber(2, 'path'), 2.0);
      expect(readNumber(0.5, 'path'), 0.5);
      expect(readBool(false, 'path'), isFalse);
      expect(readObject(<String, Object?>{}, 'path'), isEmpty);
      expect(readList(<Object?>[1], 'path'), <Object?>[1]);

      expect(() => readString(1, 'Owner.name'), throwsFormatException);
      expect(() => readInt(1.5, 'Owner.count'), throwsFormatException);
      expect(() => readNumber('1', 'Owner.gain'), throwsFormatException);
      expect(() => readBool(null, 'Owner.live'), throwsFormatException);
      expect(() => readObject(<Object?>[], 'Owner.by'), throwsFormatException);
      expect(
        () => readList(<String, Object?>{}, 'Owner.items'),
        throwsFormatException,
      );
    });
  });

  group('WS envelopes', () {
    test('a request encodes the request wire shape', () {
      const request = WsRequest(
        id: 'request-1',
        type: 'ping',
        data: <String, Object?>{'clientTimeMs': 10},
      );

      expect(request.toJson(), <String, Object?>{
        'kind': 'request',
        'id': 'request-1',
        'type': 'ping',
        'data': <String, Object?>{'clientTimeMs': 10},
      });
    });

    test('a response keeps data and the undecoded error object', () {
      final response = WsResponse.fromJson(<String, Object?>{
        'kind': 'response',
        'type': 'ping',
        'id': 'request-1',
        'data': <String, Object?>{},
        'error': <String, Object?>{
          'code': 'UNAVAILABLE',
          'message': 'try later',
        },
        'futureField': true,
      });
      final success = WsResponse.fromJson(<String, Object?>{
        'kind': 'response',
        'type': 'ping',
        'id': 'request-2',
        'data': <String, Object?>{'clientTimeMs': 1},
      });

      expect(response.id, 'request-1');
      expect(response.type, 'ping');
      expect(response.data, isEmpty);
      expect(response.error, <String, Object?>{
        'code': 'UNAVAILABLE',
        'message': 'try later',
      });
      expect(success.error, isNull);
      expect(success.data, <String, Object?>{'clientTimeMs': 1});
    });

    test('room events carry term and seq; connection events carry neither', () {
      final event = WsEvent.fromJson(<String, Object?>{
        'kind': 'event',
        'type': 'playback.updated',
        'term': 3,
        'seq': 4,
        'data': <String, Object?>{'nowPlaying': null},
        'futureField': true,
      });
      final errorEvent = WsEvent.fromJson(<String, Object?>{
        'kind': 'event',
        'type': 'error',
        'data': <String, Object?>{'code': 'INTERNAL', 'message': 'failed'},
      });

      expect(event.type, 'playback.updated');
      expect(event.term, 3);
      expect(event.seq, 4);
      expect(event.data, <String, Object?>{'nowPlaying': null});
      expect(errorEvent.term, isNull);
      expect(errorEvent.seq, isNull);
    });

    test('malformed envelopes are format errors', () {
      expect(
        () => WsResponse.fromJson(<String, Object?>{
          'kind': 'response',
          'type': 'ping',
          'id': 'bad',
        }),
        throwsFormatException,
      );
      expect(
        () => WsResponse.fromJson(<String, Object?>{
          'kind': 'event',
          'type': 'ping',
          'id': 'bad',
          'data': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => WsEvent.fromJson(<String, Object?>{
          'kind': 'event',
          'type': 'playback.updated',
          'term': 3,
          'data': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });
  });

  group('REST endpoint descriptors', () {
    const endpoint = RestEndpoint(
      name: 'playlistTracks',
      method: 'GET',
      path: '/api/room/playlists/{source}/{playlistId}/tracks',
      auth: HttpAuth.ticket,
      successStatus: 200,
      hasLocation: false,
      pathParameters: <String>['source', 'playlistId'],
    );

    test('path parameters are percent-encoded', () {
      expect(
        endpoint.buildPath(<String, String>{
          'source': 'qq',
          'playlistId': 'a/b c',
        }),
        '/api/room/playlists/qq/a%2Fb%20c/tracks',
      );
    });

    test('path parameters must match exactly', () {
      expect(
        () => endpoint.buildPath(<String, String>{'source': 'qq'}),
        throwsArgumentError,
      );
      expect(
        () => endpoint.buildPath(<String, String>{
          'source': 'qq',
          'playlistId': '1',
          'extra': 'x',
        }),
        throwsArgumentError,
      );
    });
  });
}
