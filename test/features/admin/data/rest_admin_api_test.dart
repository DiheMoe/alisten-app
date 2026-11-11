import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/data/rest_admin_api.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/api/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late Dio dio;
  late RestAdminApi api;

  setUp(() {
    adapter = FakeHttpAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    api = RestAdminApi(
      ApiTransport(
        dio,
        AppConfig(baseUrl: 'https://example.com:8443', isRelease: false),
      ),
    );
  });

  tearDown(() => dio.close(force: true));

  test('the rooms are listed with the admin token and read as rooms', () async {
    adapter.respond(200, {
      'items': [
        {
          'id': 'room-id',
          'slug': 'listen',
          'name': '一起听',
          'description': '每晚八点',
          'kind': 'persistent',
          'hasPassword': true,
          'onlineCount': 4,
        },
      ],
    });

    final rooms = await api.listRooms('t');

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/admin/rooms');
    expect(request.uri.toString(), 'https://example.com:8443/api/admin/rooms');
    expect(request.authorization, 'Bearer t');
    final room = rooms.single;
    expect(room.id, 'room-id');
    expect(room.slug, 'listen');
    expect(room.name, '一起听');
    expect(room.description, '每晚八点');
    expect(room.kind, RoomKind.persistent);
    expect(room.hasPassword, isTrue);
    expect(room.onlineCount, 4);
  });

  test('the brand name is saved with the admin token, and the saved name is '
      'the one the server answers with', () async {
    adapter.respond(200, {'brandName': '周末听歌会！'});

    final saved = await api.updateBrandName('t', '周末听歌会');

    final request = adapter.requests.single;
    expect(request.method, 'PATCH');
    expect(request.path, '/api/admin/site');
    expect(request.authorization, 'Bearer t');
    expect(request.jsonBody, {'brandName': '周末听歌会'});
    expect(saved, '周末听歌会！');
  });

  test('the brand name is read from the public site endpoint without any '
      'token', () async {
    adapter.respond(200, {
      'brandName': '大猫听歌房',
      'registrationOpen': true,
      'githubLogin': false,
    });

    final name = await api.getBrandName();

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/site');
    expect(request.authorization, isNull);
    expect(
      request.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(name, '大猫听歌房');
  });

  test(
    'registration is read publicly and switched with the admin token',
    () async {
      adapter.respond(200, {
        'brandName': 'Alisten',
        'registrationOpen': false,
        'githubLogin': false,
      });
      expect(await api.getRegistrationOpen(), isFalse);
      expect(adapter.requests.last.authorization, isNull);

      adapter.respondRaw(204, '', null);
      await api.openRegistration('t');
      expect(adapter.requests.last.method, 'PUT');
      expect(adapter.requests.last.path, '/api/admin/registration');
      expect(adapter.requests.last.authorization, 'Bearer t');

      adapter.respondRaw(204, '', null);
      await api.closeRegistration('t');
      expect(adapter.requests.last.method, 'DELETE');
      expect(adapter.requests.last.path, '/api/admin/registration');
      expect(adapter.requests.last.authorization, 'Bearer t');
    },
  );

  test('a refused token keeps the error code from the server', () async {
    adapter.respond(401, {
      'error': {'code': 'UNAUTHORIZED', 'message': '管理 token 无效'},
    });

    await expectLater(
      api.listRooms('t'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'UNAUTHORIZED')
            .having((e) => e.status, 'status', 401),
      ),
    );
  });

  test('an answer this version cannot read asks for an upgrade', () async {
    adapter.respond(200, {'name': 'not a brand'});

    await expectLater(
      api.updateBrandName('t', '周末听歌会'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', LocalErrorCodes.protocolMismatch)
            .having((e) => e.status, 'status', 200),
      ),
    );
  });

  test('a new room is created with the admin token and its id is the '
      'answer', () async {
    adapter.respond(201, {'id': 'r1'});

    final id = await api.createRoom(
      't',
      const RoomDraft(name: '大厅', description: '', slug: 'hall'),
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/admin/rooms');
    expect(request.authorization, 'Bearer t');
    expect(request.jsonBody, {'description': '', 'name': '大厅', 'slug': 'hall'});
    expect(id, 'r1');
  });

  test('a new room with a password carries it', () async {
    adapter.respond(201, {'id': 'r1'});

    await api.createRoom(
      't',
      const RoomDraft(name: '大厅', description: 'd', password: 'p'),
    );

    expect(adapter.requests.single.jsonBody, {
      'description': 'd',
      'name': '大厅',
      'password': 'p',
    });
  });

  test('a change carries only its fields, an empty alias among them', () async {
    adapter.respondRaw(204, '', null);

    await api.updateRoom('t', 'r1', const RoomPatch(slug: ''));

    final request = adapter.requests.single;
    expect(request.method, 'PATCH');
    expect(request.path, '/api/admin/rooms/r1');
    expect(request.authorization, 'Bearer t');
    expect(request.jsonBody, {'slug': ''});
  });

  test('a room is deleted by its id', () async {
    adapter.respondRaw(204, '', null);

    await api.deleteRoom('t', 'r1');

    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/api/admin/rooms/r1');
    expect(request.authorization, 'Bearer t');
  });

  test('a deletion refused keeps the error code from the server', () async {
    adapter.respond(404, {
      'error': {'code': 'NOT_FOUND', 'message': '房间不存在'},
    });

    await expectLater(
      api.deleteRoom('t', 'r1'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'NOT_FOUND')
            .having((e) => e.message, 'message', '房间不存在'),
      ),
    );
  });

  test('the key status tells whether a key exists and since when', () async {
    adapter.respond(200, {'set': false, 'createdAtMs': 0});

    final status = await api.getApiKeyStatus('t', 'r1');

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/admin/rooms/r1/api-key');
    expect(request.authorization, 'Bearer t');
    expect(status.generated, isFalse);
    expect(status.createdAtMs, 0);

    adapter.respond(200, {'set': true, 'createdAtMs': 1700000000000});
    final generated = await api.getApiKeyStatus('t', 'r1');
    expect(generated.generated, isTrue);
    expect(generated.createdAtMs, 1700000000000);
  });

  test(
    'a new key is the answer to a reset, which sends an empty body',
    () async {
      adapter.respond(201, {'key': 'k-new'});

      final key = await api.resetApiKey('t', 'r1');

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/admin/rooms/r1/api-key');
      expect(request.authorization, 'Bearer t');
      expect(request.jsonBody, <String, Object?>{});
      expect(key, 'k-new');
    },
  );

  test('a new key never reaches the log, even when its answer cannot be '
      'read', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    adapter.respond(201, {'secret': 'k-secret'});

    await expectLater(
      api.resetApiKey('t', 'r1'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', LocalErrorCodes.protocolMismatch)
            .having((e) => e.status, 'status', 201),
      ),
    );
    expect(records, isNotEmpty);
    expect(records.where((r) => r.contains('k-secret')), isEmpty);
  });

  test('a source account is read from the endpoint of its source', () async {
    adapter.respond(200, {
      'set': true,
      'account': {'id': '1', 'name': null, 'vip': null, 'verified': false},
    });

    final status = await api.getSourceAccount('t', LoginSource.bilibili);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/admin/credentials/bilibili');
    expect(request.authorization, 'Bearer t');
    expect(status.saved, isTrue);
    final account = status.account!;
    expect(account.id, '1');
    expect(account.name, isNull);
    expect(account.vip, isNull);
    expect(account.verified, isFalse);

    adapter.respond(200, {
      'set': true,
      'account': {'id': '42', 'name': '小明', 'vip': true, 'verified': true},
    });
    final netease = await api.getSourceAccount('t', LoginSource.netease);
    expect(adapter.requests.last.path, '/api/admin/credentials/netease');
    expect(netease.account!.name, '小明');
    expect(netease.account!.vip, isTrue);
    expect(netease.account!.verified, isTrue);

    adapter.respond(200, {'set': false, 'account': null});
    final qq = await api.getSourceAccount('t', LoginSource.qq);
    expect(adapter.requests.last.path, '/api/admin/credentials/qq');
    expect(qq.saved, isFalse);
    expect(qq.account, isNull);
  });

  test('a QQ music code is asked for with the way it is scanned', () async {
    adapter.respond(201, {
      'key': 'k-1',
      'qrImage': 'https://img.example/qr.png',
      'expiresAtMs': 1700000120000,
    });

    final ticket = await api.startQrLogin(
      't',
      LoginSource.qq,
      qqType: QqLoginType.wx,
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/admin/credentials/qq/qr-logins');
    expect(request.authorization, 'Bearer t');
    expect(request.jsonBody, {'type': 'wx'});
    expect(ticket.key, 'k-1');
    expect(ticket.qrImage, 'https://img.example/qr.png');
    expect(ticket.expiresAtMs, 1700000120000);
  });

  test('codes of the other sources are asked for with an empty body', () async {
    for (final (source, path) in [
      (LoginSource.netease, '/api/admin/credentials/netease/qr-logins'),
      (LoginSource.bilibili, '/api/admin/credentials/bilibili/qr-logins'),
    ]) {
      adapter.respond(201, {
        'key': 'k',
        'qrImage': 'data:image/png;base64,iVBORw0KGgo=',
        'expiresAtMs': 1,
      });

      await api.startQrLogin('t', source);

      expect(adapter.requests.last.method, 'POST');
      expect(adapter.requests.last.path, path);
      expect(adapter.requests.last.jsonBody, <String, Object?>{});
    }
  });

  test('a code is checked with its key, and QQ music also with the way it '
      'is scanned', () async {
    adapter.respond(200, {'status': 'waiting', 'message': ''});

    final netease = await api.checkQrLogin('t', LoginSource.netease, 'k');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/admin/credentials/netease/qr-logins/status');
    expect(request.authorization, 'Bearer t');
    expect(request.jsonBody, {'key': 'k'});
    expect(netease.state, QrCheckState.waiting);

    await api.checkQrLogin('t', LoginSource.qq, 'k', qqType: QqLoginType.wx);
    expect(
      adapter.requests.last.path,
      '/api/admin/credentials/qq/qr-logins/status',
    );
    expect(adapter.requests.last.jsonBody, {'key': 'k', 'type': 'wx'});

    await api.checkQrLogin('t', LoginSource.bilibili, 'k');
    expect(
      adapter.requests.last.path,
      '/api/admin/credentials/bilibili/qr-logins/status',
    );
    expect(adapter.requests.last.jsonBody, {'key': 'k'});
  });

  test('every state of a code is read with its message', () async {
    for (final (wire, state) in [
      ('waiting', QrCheckState.waiting),
      ('scanned', QrCheckState.scanned),
      ('success', QrCheckState.success),
      ('expired', QrCheckState.expired),
      ('failed', QrCheckState.failed),
    ]) {
      adapter.respond(200, {'status': wire, 'message': '说明'});

      final check = await api.checkQrLogin('t', LoginSource.netease, 'k');

      expect(check.state, state);
      expect(check.message, '说明');
    }
  });

  test('a code key never reaches the log, even when the answer cannot be '
      'read', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    adapter.respond(201, {'key': 'k-secret'});

    await expectLater(
      api.startQrLogin('t', LoginSource.netease),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', LocalErrorCodes.protocolMismatch)
            .having((e) => e.status, 'status', 201),
      ),
    );
    expect(records, isNotEmpty);
    expect(records.where((r) => r.contains('k-secret')), isEmpty);
  });

  test('the YouTube cookie status tells whether cookies are saved and since '
      'when', () async {
    adapter.respond(200, {'set': true, 'updatedAtMs': 1700000000000});

    final status = await api.getYoutubeCookie('t');

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/admin/credentials/youtube');
    expect(request.authorization, 'Bearer t');
    expect(status.saved, isTrue);
    expect(status.updatedAtMs, 1700000000000);

    adapter.respond(200, {'set': false, 'updatedAtMs': 0});
    final unset = await api.getYoutubeCookie('t');
    expect(unset.saved, isFalse);
    expect(unset.updatedAtMs, 0);
  });

  test('a YouTube cookie status this version cannot read asks for an '
      'upgrade', () async {
    adapter.respond(200, {'set': true});

    await expectLater(
      api.getYoutubeCookie('t'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', LocalErrorCodes.protocolMismatch)
            .having((e) => e.status, 'status', 200),
      ),
    );
  });

  test('YouTube cookies are put as they are, with the admin token', () async {
    adapter.respondRaw(204, '', null);

    await api.setYoutubeCookie('t', 'c=1');

    final request = adapter.requests.single;
    expect(request.method, 'PUT');
    expect(request.path, '/api/admin/credentials/youtube');
    expect(request.authorization, 'Bearer t');
    expect(request.jsonBody, {'cookies': 'c=1'});
  });

  test('YouTube cookies the server cannot recognise keep its code and '
      'message, and never reach the log', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    adapter.respond(400, {
      'error': {
        'code': 'INVALID_ARGUMENT',
        'message': '没有识别出 YouTube 的 cookies',
      },
    });

    await expectLater(
      api.setYoutubeCookie('t', 'SID=secret-sid'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'INVALID_ARGUMENT')
            .having((e) => e.message, 'message', '没有识别出 YouTube 的 cookies')
            .having((e) => e.status, 'status', 400),
      ),
    );
    expect(records.where((r) => r.contains('secret-sid')), isEmpty);
  });

  test('YouTube cookies are cleared with the admin token', () async {
    adapter.respondRaw(204, '', null);

    await api.deleteYoutubeCookie('t');

    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/api/admin/credentials/youtube');
    expect(request.authorization, 'Bearer t');
  });

  test('an account is found by its username and its password reset', () async {
    adapter.respond(200, {
      'member': {'id': 'm-1', 'name': '大猫', 'avatarHash': ''},
      'username': 'mao',
    });
    final account = await api.findAccount('t', 'mao');
    expect(adapter.requests.last.path, '/api/admin/accounts/mao');
    expect(adapter.requests.last.authorization, 'Bearer t');
    expect(account.username, 'mao');
    expect(account.member.name, '大猫');

    adapter.respond(200, {'password': 'new-secret-password'});
    final password = await api.resetAccountPassword('t', 'mao');
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.path, '/api/admin/accounts/mao/password');
    expect(password, 'new-secret-password');
  });

  test('without a token nothing is sent', () async {
    await expectLater(
      api.listRooms(''),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          LocalErrorCodes.noToken,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  group('an answer is waited for', () {
    // 请求始终没有回复：[limit] 前一刻仍在等待，到 [limit] 时以网络错误结束并
    // 断开连接。
    void waitsFor(Duration limit, Future<Object?> Function() call) {
      fakeAsync((async) {
        adapter
          ..neverRespond()
          ..cancelled = false;
        Object? failure;
        unawaited(
          call().then<void>((_) {}, onError: (Object error) => failure = error),
        );

        async.elapse(limit - const Duration(milliseconds: 1));
        expect(failure, isNull);
        expect(adapter.cancelled, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(
          failure,
          isA<ApiException>()
              .having((e) => e.code, 'code', LocalErrorCodes.network)
              .having((e) => e.message, 'message', '请求超时，请检查网络后重试。'),
        );
        expect(adapter.cancelled, isTrue);
      });
    }

    final upstream = <String, Future<Object?> Function()>{
      'netease account': () => api.getSourceAccount('t', LoginSource.netease),
      'bilibili account': () => api.getSourceAccount('t', LoginSource.bilibili),
      'netease code': () => api.startQrLogin('t', LoginSource.netease),
      'QQ code': () => api.startQrLogin('t', LoginSource.qq),
      'WeChat code': () =>
          api.startQrLogin('t', LoginSource.qq, qqType: QqLoginType.wx),
      'bilibili code': () => api.startQrLogin('t', LoginSource.bilibili),
      'netease check': () => api.checkQrLogin('t', LoginSource.netease, 'k'),
      'QQ check': () => api.checkQrLogin('t', LoginSource.qq, 'k'),
      'WeChat check': () =>
          api.checkQrLogin('t', LoginSource.qq, 'k', qqType: QqLoginType.wx),
      'bilibili check': () => api.checkQrLogin('t', LoginSource.bilibili, 'k'),
    };
    for (final MapEntry(key: name, value: call) in upstream.entries) {
      test('45 seconds for the $name, which the server asks of the source '
          'with 30 seconds to answer', () {
        waitsFor(const Duration(seconds: 45), call);
      });
    }

    final local = <String, Future<Object?> Function()>{
      'rooms': () => api.listRooms('t'),
      'brand name': () => api.getBrandName(),
      'registration': () => api.getRegistrationOpen(),
      'registration opened': () => api.openRegistration('t'),
      'registration closed': () => api.closeRegistration('t'),
      'brand name saved': () => api.updateBrandName('t', '周末听歌会'),
      'new room': () =>
          api.createRoom('t', const RoomDraft(name: '大厅', description: '')),
      'room change': () =>
          api.updateRoom('t', 'r1', const RoomPatch(name: 'B')),
      'room deletion': () => api.deleteRoom('t', 'r1'),
      'key status': () => api.getApiKeyStatus('t', 'r1'),
      'key reset': () => api.resetApiKey('t', 'r1'),
      // QQ 音乐账号只从保存的 Cookie 中解析，不请求 QQ 音乐。
      'QQ music account': () => api.getSourceAccount('t', LoginSource.qq),
      'YouTube cookie status': () => api.getYoutubeCookie('t'),
      'YouTube cookies saved': () => api.setYoutubeCookie('t', 'c=1'),
      'YouTube cookies cleared': () => api.deleteYoutubeCookie('t'),
    };
    for (final MapEntry(key: name, value: call) in local.entries) {
      test('15 seconds for the $name, which the server answers by itself', () {
        waitsFor(const Duration(seconds: 15), call);
      });
    }
  });
}
