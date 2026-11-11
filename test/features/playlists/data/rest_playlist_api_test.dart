import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:alisten/features/playlists/data/rest_playlist_api.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/api/fake_http_adapter.dart';

const _shareId = 'AbCdEfGhIjKlMnOpQrStUv';
const _a = Track(source: TrackSource.netease, id: '1');
const _b = Track(source: TrackSource.bilibili, id: 'BV1xx411c7mD');
const _wireA = {'source': 'netease', 'id': '1'};
const _wireB = {'source': 'bilibili', 'id': 'BV1xx411c7mD'};

// 请求体不做比较：DELETE 的请求体由传输层决定。
const _anyBody = Object();

Map<String, Object?> _playlistJson({
  String id = 'pl-1',
  String? coverUrl = 'http://p1.music.126.net/cover.jpg',
  String? shareId,
}) {
  return {
    'id': id,
    'name': '夜跑',
    'favorites': false,
    'trackCount': 2,
    'createdAtMs': 10,
    'updatedAtMs': 20,
    'coverUrl': coverUrl,
    'shareId': shareId,
  };
}

Map<String, Object?> _itemJson(Map<String, Object?> track) {
  return {
    'track': track,
    'meta': {
      'title': '晴天',
      'artist': '周杰伦',
      'album': '叶惠美',
      'coverUrl': 'http://p2.music.126.net/song.jpg',
      'pageUrl': 'https://music.163.com/song?id=1',
      'durationMs': 269000,
    },
  };
}

final _sharedJson = {
  'name': '夜跑',
  'favorites': true,
  'ownerName': '阿柚',
  'ownerAvatarHash': 'abc123',
  'items': [_itemJson(_wireA), _itemJson(_wireB)],
};

final class _Case {
  const _Case(
    this.name, {
    required this.status,
    required this.reply,
    required this.call,
    required this.method,
    required this.path,
    required this.body,
  });

  final String name;
  final int status;

  /// 为 null 时回复 204 空正文。
  final Object? reply;
  final Future<Object?> Function(PlaylistApi api) call;
  final String method;
  final String path;
  final Object? body;
}

void main() {
  late FakeHttpAdapter adapter;
  late Dio dio;
  late PlaylistApi api;
  late int tokenReads;
  late String? memberToken;
  late Exception? tokenError;

  setUp(() {
    adapter = FakeHttpAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    tokenReads = 0;
    memberToken = 'member-token';
    tokenError = null;
    api = RestPlaylistApi(
      ApiTransport(
        dio,
        AppConfig(
          baseUrl: 'http://127.0.0.1:9876',
          isRelease: false,
          allowCleartext: true,
        ),
      ),
      () async {
        tokenReads++;
        final error = tokenError;
        if (error != null) throw error;
        return memberToken;
      },
    );
  });

  tearDown(() => dio.close(force: true));

  final cases = [
    _Case(
      'listMine',
      status: 200,
      reply: {
        'items': [_playlistJson()],
      },
      call: (api) => api.listMine(),
      method: 'GET',
      path: '/api/me/playlists',
      body: null,
    ),
    _Case(
      'create',
      status: 201,
      reply: _playlistJson(),
      call: (api) => api.create('夜跑'),
      method: 'POST',
      path: '/api/me/playlists',
      body: {'name': '夜跑'},
    ),
    _Case(
      'rename',
      status: 204,
      reply: null,
      call: (api) => api.rename('pl-1', '晨跑'),
      method: 'PATCH',
      path: '/api/me/playlists/pl-1',
      body: {'name': '晨跑'},
    ),
    _Case(
      'delete',
      status: 204,
      reply: null,
      call: (api) => api.delete('pl-1'),
      method: 'DELETE',
      path: '/api/me/playlists/pl-1',
      body: _anyBody,
    ),
    _Case(
      'items',
      status: 200,
      reply: {
        'items': [_itemJson(_wireA)],
      },
      call: (api) => api.items('pl-1'),
      method: 'GET',
      path: '/api/me/playlists/pl-1/items',
      body: null,
    ),
    _Case(
      'add',
      status: 201,
      reply: {'item': _itemJson(_wireA)},
      call: (api) => api.add('pl-1', _a),
      method: 'POST',
      path: '/api/me/playlists/pl-1/items',
      body: {'track': _wireA},
    ),
    _Case(
      'remove',
      status: 204,
      reply: null,
      call: (api) => api.remove('pl-1', [_a, _b]),
      method: 'POST',
      path: '/api/me/playlists/pl-1/removals',
      body: {
        'tracks': [_wireA, _wireB],
      },
    ),
    _Case(
      'copy',
      status: 200,
      reply: {'added': 1},
      call: (api) => api.copy(from: 'pl-2', to: 'pl-1', tracks: [_a]),
      method: 'POST',
      path: '/api/me/playlists/pl-1/copies',
      body: {
        'from': 'pl-2',
        'tracks': [_wireA],
      },
    ),
    _Case(
      'move before a song',
      status: 204,
      reply: null,
      call: (api) => api.move('pl-1', [_a], before: _b),
      method: 'POST',
      path: '/api/me/playlists/pl-1/moves',
      body: {
        'before': _wireB,
        'tracks': [_wireA],
      },
    ),
    _Case(
      'move to the end',
      status: 204,
      reply: null,
      call: (api) => api.move('pl-1', [_a]),
      method: 'POST',
      path: '/api/me/playlists/pl-1/moves',
      body: {
        'tracks': [_wireA],
      },
    ),
    _Case(
      'containing',
      status: 200,
      reply: {
        'playlistIds': ['pl-1'],
      },
      call: (api) => api.containing(_a),
      method: 'POST',
      path: '/api/me/playlist-memberships',
      body: {'track': _wireA},
    ),
    _Case(
      'importFile',
      status: 201,
      reply: {'playlist': _playlistJson(), 'imported': 1},
      call: (api) => api.importFile('旧歌单', const [
        PlaylistFileTrack(track: _a, title: '晴天', durationMs: 0),
        PlaylistFileTrack(
          track: _b,
          title: '视频',
          artist: 'UP 主',
          album: '',
          durationMs: 61000,
          coverUrl: 'https://i0.hdslb.com/a.jpg',
          pageUrl: 'https://www.bilibili.com/video/BV1xx411c7mD',
        ),
      ]),
      method: 'POST',
      path: '/api/me/playlists/imports',
      body: {
        'name': '旧歌单',
        'tracks': [
          {'durationMs': 0, 'title': '晴天', 'track': _wireA},
          {
            'album': '',
            'artist': 'UP 主',
            'coverUrl': 'https://i0.hdslb.com/a.jpg',
            'durationMs': 61000,
            'pageUrl': 'https://www.bilibili.com/video/BV1xx411c7mD',
            'title': '视频',
            'track': _wireB,
          },
        ],
      },
    ),
    _Case(
      'resolveLink',
      status: 200,
      reply: {'source': 'netease', 'playlistId': '24381616'},
      call: (api) =>
          api.resolveLink('https://music.163.com/playlist?id=24381616'),
      method: 'POST',
      path: '/api/me/playlist-links',
      body: {'link': 'https://music.163.com/playlist?id=24381616'},
    ),
    _Case(
      'importPlatform',
      status: 201,
      reply: {'playlist': _playlistJson(), 'imported': 30},
      call: (api) => api.importPlatform(
        name: '导入的歌单',
        source: TrackSource.netease,
        playlistId: '24381616',
      ),
      method: 'POST',
      path: '/api/me/playlists/platform-imports',
      body: {'name': '导入的歌单', 'playlistId': '24381616', 'source': 'netease'},
    ),
    _Case(
      'share',
      status: 200,
      reply: {'shareId': _shareId},
      call: (api) => api.share('pl-1'),
      method: 'POST',
      path: '/api/me/playlists/pl-1/share',
      body: <String, Object?>{},
    ),
    _Case(
      'unshare',
      status: 204,
      reply: null,
      call: (api) => api.unshare('pl-1'),
      method: 'DELETE',
      path: '/api/me/playlists/pl-1/share',
      body: _anyBody,
    ),
    _Case(
      'shared',
      status: 200,
      reply: _sharedJson,
      call: (api) => api.shared(_shareId),
      method: 'GET',
      path: '/api/shared-playlists/$_shareId',
      body: null,
    ),
    _Case(
      'copyShared',
      status: 201,
      reply: _playlistJson(),
      call: (api) => api.copyShared(_shareId, '复制的歌单'),
      method: 'POST',
      path: '/api/shared-playlists/$_shareId/copies',
      body: {'name': '复制的歌单'},
    ),
  ];

  for (final example in cases) {
    test('${example.name} sends ${example.method} ${example.path}', () async {
      final reply = example.reply;
      if (reply == null) {
        adapter.respondRaw(204, '', null);
      } else {
        adapter.respond(example.status, reply);
      }

      await example.call(api);

      final request = adapter.requests.single;
      expect(request.method, example.method);
      expect(request.path, example.path);
      if (!identical(example.body, _anyBody)) {
        expect(request.jsonBody, example.body);
      }
      expect(
        request.authorization,
        example.name == 'shared' ? isNull : 'Bearer member-token',
      );
    });
  }

  test('playlists are mapped, with the cover upgraded to https and empty '
      'values kept empty', () async {
    adapter.respond(200, {
      'items': [
        _playlistJson(shareId: _shareId),
        _playlistJson(id: 'pl-2', coverUrl: null),
      ],
    });

    final playlists = await api.listMine();

    expect(playlists[0].id, 'pl-1');
    expect(playlists[0].name, '夜跑');
    expect(playlists[0].favorites, isFalse);
    expect(playlists[0].trackCount, 2);
    expect(playlists[0].createdAtMs, 10);
    expect(playlists[0].updatedAtMs, 20);
    expect(playlists[0].coverUrl, 'https://p1.music.126.net/cover.jpg');
    expect(playlists[0].shareId, _shareId);
    expect(playlists[1].coverUrl, isNull);
    expect(playlists[1].shareId, isNull);
  });

  test('songs keep their order and get https covers', () async {
    adapter.respond(200, {
      'items': [_itemJson(_wireB), _itemJson(_wireA)],
    });

    final items = await api.items('pl-1');

    expect([for (final item in items) item.track.id], ['BV1xx411c7mD', '1']);
    expect(items.first.track.source, TrackSource.bilibili);
    expect(items.first.meta.title, '晴天');
    expect(items.first.meta.coverUrl, 'https://p2.music.126.net/song.jpg');
  });

  test('copy, containing, imports and share return what the server '
      'says', () async {
    adapter.respond(200, {'added': 3});
    expect(await api.copy(from: 'pl-2', to: 'pl-1', tracks: [_a]), 3);

    adapter.respond(200, {
      'playlistIds': ['pl-1', 'fav'],
    });
    expect(await api.containing(_a), {'pl-1', 'fav'});

    adapter.respond(201, {'playlist': _playlistJson(), 'imported': 7});
    final imported = await api.importFile('旧歌单', const [
      PlaylistFileTrack(track: _a, title: '晴天', durationMs: 0),
    ]);
    expect(imported.imported, 7);
    expect(imported.playlist.id, 'pl-1');

    adapter.respond(200, {'source': 'qq', 'playlistId': '7'});
    final resolved = await api.resolveLink(
      'https://y.qq.com/n/ryqq/playlist/7',
    );
    expect(resolved.source, TrackSource.qq);
    expect(resolved.playlistId, '7');

    adapter.respond(200, {'shareId': _shareId});
    expect(await api.share('pl-1'), _shareId);
  });

  test('a shared playlist is read without a member token', () async {
    memberToken = null;
    adapter.respond(200, _sharedJson);

    final shared = await api.shared(_shareId);

    expect(tokenReads, 0);
    expect(adapter.requests.single.authorization, isNull);
    expect(shared.name, '夜跑');
    expect(shared.favorites, isTrue);
    expect(shared.ownerName, '阿柚');
    expect(shared.ownerAvatarHash, 'abc123');
    expect(shared.items, hasLength(2));
    expect(shared.coverUrl, 'https://p2.music.126.net/song.jpg');
  });

  test('every request that needs a member reads the token again', () async {
    adapter.respond(200, {'items': <Object?>[]});
    await api.listMine();
    memberToken = 'renewed-token';
    adapter.respond(200, {'items': <Object?>[]});
    await api.listMine();

    expect(tokenReads, 2);
    expect(adapter.requests.last.authorization, 'Bearer renewed-token');
  });

  test('without a token nothing that needs a member is sent', () async {
    memberToken = null;

    await expectLater(
      api.listMine(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          LocalErrorCodes.noToken,
        ),
      ),
    );
    await expectLater(api.rename('pl-1', '晨跑'), throwsA(isA<ApiException>()));
    expect(adapter.requests, isEmpty);
  });

  test('a token that cannot be read is no token, and nothing is '
      'sent', () async {
    tokenError = Exception('keystore');

    for (final call in <Future<Object?> Function()>[
      api.listMine,
      () => api.rename('pl-1', '晨跑'),
    ]) {
      await expectLater(
        call(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', LocalErrorCodes.noToken)
              .having((e) => e.message, 'message', '身份凭据暂时无法读取，请稍后重试。'),
        ),
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('error codes and messages pass through', () async {
    adapter.respond(409, {
      'error': {'code': 'CONFLICT', 'message': '一个歌单最多 1000 首歌'},
    });

    await expectLater(
      api.add('pl-1', _a),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'CONFLICT')
            .having((error) => error.message, 'message', '一个歌单最多 1000 首歌'),
      ),
    );
  });

  test(
    'create and copyShared return the playlist with an https cover',
    () async {
      adapter.respond(201, _playlistJson());
      final created = await api.create('夜跑');
      expect(created.id, 'pl-1');
      expect(created.coverUrl, 'https://p1.music.126.net/cover.jpg');

      adapter.respond(201, _playlistJson());
      final copied = await api.copyShared(_shareId, '复制的歌单');
      expect(copied.id, 'pl-1');
      expect(copied.coverUrl, 'https://p1.music.126.net/cover.jpg');
    },
  );

  test('importPlatform returns the playlist and the imported count', () async {
    adapter.respond(201, {'playlist': _playlistJson(), 'imported': 30});

    final imported = await api.importPlatform(
      name: '导入的歌单',
      source: TrackSource.netease,
      playlistId: '24381616',
    );

    expect(imported.imported, 30);
    expect(imported.playlist.id, 'pl-1');
  });

  test('importPlatform waits 45 seconds before giving up and cancels', () {
    fakeAsync((async) {
      adapter.neverRespond();
      Object? failure;
      unawaited(
        api
            .importPlatform(
              name: '导入的歌单',
              source: TrackSource.netease,
              playlistId: '24381616',
            )
            .then<void>((_) {}, onError: (Object error) => failure = error),
      );

      async.elapse(const Duration(seconds: 44));
      expect(failure, isNull);

      async.elapse(const Duration(seconds: 1));
      expect(
        failure,
        isA<ApiException>()
            .having((e) => e.code, 'code', LocalErrorCodes.network)
            .having((e) => e.answerLost, 'answerLost', isTrue),
      );
      expect(adapter.cancelled, isTrue);
    });
  });

  test('replies that cannot be decoded are protocol mismatches with the '
      'success status, so changes count as unknown', () async {
    final replies =
        <({int status, String body, Future<Object?> Function() call})>[
          (status: 201, body: jsonEncode(['x']), call: () => api.create('夜跑')),
          (
            status: 201,
            body: jsonEncode({
              'item': {'track': _wireA},
            }),
            call: () => api.add('pl-1', _a),
          ),
          (
            status: 200,
            body: jsonEncode({'added': '1'}),
            call: () => api.copy(from: 'pl-2', to: 'pl-1', tracks: [_a]),
          ),
          (
            status: 200,
            body: jsonEncode({'source': 'spotify', 'playlistId': '7'}),
            call: () => api.resolveLink('https://music.163.com/playlist?id=7'),
          ),
          (
            status: 200,
            body: jsonEncode(<String, Object?>{}),
            call: () => api.share('pl-1'),
          ),
          (
            status: 200,
            body: jsonEncode({..._sharedJson, 'items': null}),
            call: () => api.shared(_shareId),
          ),
        ];
    for (final reply in replies) {
      adapter.respondRaw(reply.status, reply.body, null);
      await expectLater(
        reply.call(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', LocalErrorCodes.protocolMismatch)
              .having((e) => e.status, 'status', reply.status)
              .having((e) => e.answerLost, 'answerLost', isTrue),
        ),
        reason: reply.body,
      );
    }
  });

  test('errors of requests without a reply body pass through', () async {
    adapter.respond(409, {
      'error': {'code': 'CONFLICT', 'message': '歌单已变化'},
    });

    await expectLater(
      api.move('pl-1', [_a]),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CONFLICT')),
    );
  });

  test('a missing shared playlist fails without reading the token', () async {
    memberToken = null;
    adapter.respond(404, {
      'error': {'code': 'NOT_FOUND', 'message': '分享不存在'},
    });

    await expectLater(
      api.shared(_shareId),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NOT_FOUND')),
    );
    expect(tokenReads, 0);
  });
}
