import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/protocol/http.gen.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_adapter.dart';

const _requestTimeout = Duration(seconds: 15);

void main() {
  late FakeHttpAdapter adapter;
  late Dio dio;
  late ApiTransport transport;
  late AlistenApi api;
  late String memberToken;

  AlistenApi createApi(AppConfig config) {
    transport = ApiTransport(dio, config);
    return RestAlistenApi(transport, () async => memberToken);
  }

  setUp(() {
    memberToken = 'member-token';
    adapter = FakeHttpAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    api = createApi(
      AppConfig(
        baseUrl: 'http://127.0.0.1:9876',
        isRelease: false,
        allowCleartext: true,
        requestTimeout: _requestTimeout,
      ),
    );
  });

  tearDown(() {
    dio.close(force: true);
  });

  test(
    'createMember decodes the unwrapped response and returns its credential',
    () async {
      adapter.respond(201, {
        'memberToken': 'new-member-token',
        'member': _memberJson(id: 'member-1', name: 'Listener'),
      });

      final result = await api.createMember();

      expect(result.memberToken, 'new-member-token');
      expect(result.member.id, 'member-1');
      expect(result.member.name, 'Listener');
      expect(result.member.avatarHash, 'avatar-hash');
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/members');
      expect(request.authorization, isNull);
      expect(request.contentType, 'application/json');
      expect(request.jsonBody, <String, Object?>{});
    },
  );

  test(
    'getMe sends member bearer authentication and maps the domain member',
    () async {
      adapter.respond(200, {
        'member': _memberJson(id: 'member-2', name: 'Current listener'),
      });

      final member = await api.getMe();

      expect(member.id, 'member-2');
      expect(member.name, 'Current listener');
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/api/me');
      expect(request.authorization, 'Bearer member-token');
    },
  );

  test(
    'updateMe sends only supplied profile fields without hashing email',
    () async {
      adapter.respond(200, {
        'member': _memberJson(id: 'member-3', name: 'Renamed'),
      });

      final member = await api.updateMe(
        name: 'Renamed',
        email: 'person@example.com',
      );

      expect(member.name, 'Renamed');
      final request = adapter.requests.single;
      expect(request.method, 'PATCH');
      expect(request.authorization, 'Bearer member-token');
      expect(request.jsonBody, <String, Object?>{
        'name': 'Renamed',
        'email': 'person@example.com',
      });
    },
  );

  test(
    'listRooms preserves every room listing field in domain read models',
    () async {
      adapter.respond(200, {
        'items': [_roomListingJson()],
      });

      final rooms = await api.listRooms();

      expect(rooms, hasLength(1));
      final room = rooms.single;
      expect(room.id, 'room-id');
      expect(room.slug, 'listening-room');
      expect(room.name, 'Listening room');
      expect(room.description, 'A room for synchronized listening');
      expect(room.kind, RoomKind.ephemeral);
      expect(room.hasPassword, isTrue);
      expect(room.onlineCount, 7);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, '/api/rooms');
    },
  );

  test(
    'getRoom percent-encodes a room reference as one path segment',
    () async {
      adapter.respond(200, _roomListingJson());

      final room = await api.getRoom('alias /?#%');

      expect(room.slug, 'listening-room');
      expect(adapter.requests.single.path, '/api/rooms/alias%20%2F%3F%23%25');
    },
  );

  test(
    'createRoom sends the protocol body and returns the created room id',
    () async {
      adapter.respond(201, {'id': 'created-id'});

      final id = await api.createRoom(
        name: 'New room',
        description: 'Room description',
        password: 'secret',
      );

      expect(id, 'created-id');
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/rooms');
      expect(request.jsonBody, <String, Object?>{
        'name': 'New room',
        'description': 'Room description',
        'password': 'secret',
      });
    },
  );

  test(
    'createTicket uses member authentication and returns the room ticket',
    () async {
      adapter.respond(201, {'ticket': 'room-ticket'});

      final ticket = await api.createTicket('room-id', password: 'secret');

      expect(ticket, 'room-ticket');
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/rooms/room-id/tickets');
      expect(request.authorization, 'Bearer member-token');
      expect(request.jsonBody, <String, Object?>{'password': 'secret'});
    },
  );

  test(
    'structured protocol errors retain code message and HTTP status',
    () async {
      adapter.respond(401, {
        'error': {'code': 'UNAUTHORIZED', 'message': 'Member token expired'},
      });

      await expectLater(
        api.getMe(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'UNAUTHORIZED')
              .having(
                (error) => error.message,
                'message',
                'Member token expired',
              )
              .having((error) => error.status, 'status', 401),
        ),
      );
    },
  );

  test(
    'non-JSON proxy errors become network errors without exposing HTML',
    () async {
      adapter.respondRaw(502, '<html>upstream failed</html>', 'Bad Gateway');

      await expectLater(
        api.getMe(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'NETWORK')
              .having((error) => error.message, 'message', contains('502'))
              .having((error) => error.message, 'message', isNot(contains('<')))
              .having((error) => error.status, 'status', 502),
        ),
      );
    },
  );

  group('a request turned away for coming too often', () {
    Matcher rateLimited({Duration? retryAfter}) => isA<ApiException>()
        .having((error) => error.code, 'code', 'RATE_LIMITED')
        .having((error) => error.message, 'message', '请求太频繁，请稍后再试。')
        .having((error) => error.status, 'status', 429)
        .having((error) => error.rateLimited, 'rateLimited', isTrue)
        .having((error) => error.answerLost, 'answerLost', isFalse)
        .having((error) => error.retryAfter, 'retryAfter', retryAfter);

    test('by a proxy in plain text was not carried out, and says when to try '
        'again', () async {
      adapter.respondRaw(
        429,
        'Too Many Requests',
        'Too Many Requests',
        headers: {
          Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
          'retry-after': ['3'],
        },
      );

      await expectLater(
        transport.execute(
          RestEndpoints.adminDeleteRoom,
          pathParameters: {'id': 'r1'},
          token: 'admin-token',
        ),
        throwsA(rateLimited(retryAfter: const Duration(seconds: 3))),
      );
    });

    test(
      'by Alisten with a protocol error was not carried out either',
      () async {
        adapter.respond(429, {
          'error': {'code': 'RATE_LIMITED', 'message': '搜索过于频繁，请稍后再试。'},
        });

        await expectLater(api.listRooms(), throwsA(rateLimited()));
      },
    );

    test('with a wait that is not a number of seconds says no wait', () async {
      for (final value in ['Wed, 21 Oct 2026 07:28:00 GMT', '-1', 'soon']) {
        adapter.respondRaw(
          429,
          'Too Many Requests',
          null,
          headers: {
            'retry-after': [value],
          },
        );

        await expectLater(
          api.listRooms(),
          throwsA(rateLimited()),
          reason: value,
        );
      }
    });
  });

  test('responses this client cannot decode are protocol mismatches', () async {
    final responses =
        <({int status, String body, Future<Object?> Function() call})>[
          (status: 200, body: '<html>ok</html>', call: api.getMe),
          (
            status: 200,
            body: jsonEncode({
              'items': [
                {..._roomListingJson(), 'kind': 'future-kind'},
              ],
            }),
            call: api.listRooms,
          ),
          (
            status: 404,
            body: jsonEncode({
              'error': {'code': 'FUTURE_CODE', 'message': '新错误'},
            }),
            call: api.listRooms,
          ),
        ];
    for (final response in responses) {
      adapter.respondRaw(response.status, response.body, null);

      await expectLater(
        response.call(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'PROTOCOL_MISMATCH',
          ),
        ),
        reason: response.body,
      );
    }
  });

  test('a missing member token fails locally without sending', () async {
    memberToken = '';

    await expectLater(
      api.getMe(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'LOCAL_NO_TOKEN')
            .having((error) => error.status, 'status', isNull),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('transport treats an expected 204 response as no content', () async {
    adapter.respondRaw(204, '', null);
    final result = await transport.execute(
      RestEndpoints.queueRemove,
      pathParameters: {'entryId': 'entry-id'},
      token: 'room-ticket',
    );

    expect(result, isNull);
    expect(adapter.requests.single.authorization, 'Bearer room-ticket');
  });

  test('admin endpoints send the caller supplied admin token', () async {
    adapter.respond(200, {'items': <Object?>[]});

    await transport.execute(RestEndpoints.adminListRooms, token: 'admin-token');

    final request = adapter.requests.single;
    expect(request.authorization, 'Bearer admin-token');
    expect(request.path, '/api/admin/rooms');
    expect(request.method, 'GET');
  });

  test(
    'admin endpoints without a token fail locally without sending',
    () async {
      await expectLater(
        transport.execute(RestEndpoints.adminListRooms),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            LocalErrorCodes.noToken,
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test('connection failures report a network error in Chinese', () async {
    adapter.fail();

    await expectLater(
      api.listRooms(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'NETWORK')
            .having((error) => error.message, 'message', '网络请求失败，请检查网络后重试。'),
      ),
    );
  });

  test('total timeout cancels a request whose server never responds', () {
    fakeAsync((async) {
      adapter.neverRespond();
      Object? failure;
      unawaited(
        api.getMe().then<void>(
          (_) {},
          onError: (Object error) => failure = error,
        ),
      );

      async.elapse(_requestTimeout - const Duration(milliseconds: 1));
      expect(failure, isNull);
      expect(adapter.cancelled, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(
        failure,
        isA<ApiException>()
            .having((error) => error.code, 'code', 'NETWORK')
            .having((error) => error.message, 'message', '请求超时，请检查网络后重试。')
            .having((error) => error.status, 'status', isNull),
      );
      expect(adapter.cancelled, isTrue);
    });
  });

  test('a request given its own timeout waits that long instead', () {
    fakeAsync((async) {
      adapter.neverRespond();
      Object? failure;
      unawaited(
        transport
            .execute(
              RestEndpoints.adminListRooms,
              token: 'admin-token',
              timeout: const Duration(seconds: 45),
            )
            .then<void>((_) {}, onError: (Object error) => failure = error),
      );

      async.elapse(
        const Duration(seconds: 45) - const Duration(milliseconds: 1),
      );
      expect(failure, isNull);
      expect(adapter.cancelled, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(
        failure,
        isA<ApiException>().having((error) => error.code, 'code', 'NETWORK'),
      );
      expect(adapter.cancelled, isTrue);
    });
  });
}

Map<String, Object?> _memberJson({required String id, required String name}) {
  return {'id': id, 'name': name, 'avatarHash': 'avatar-hash'};
}

Map<String, Object?> _roomListingJson() {
  return {
    'id': 'room-id',
    'slug': 'listening-room',
    'name': 'Listening room',
    'description': 'A room for synchronized listening',
    'kind': 'ephemeral',
    'hasPassword': true,
    'onlineCount': 7,
  };
}
