import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alisten/features/update/data/github_release_source.dart';
import 'package:alisten/features/update/index.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/api/fake_http_adapter.dart';

const _latest =
    'https://api.github.com/repos/DiheMoe/alisten-app/releases/latest';
const _page = 'https://github.com/DiheMoe/alisten-app/releases/tag/v1.2.0';
const _download =
    'https://github.com/DiheMoe/alisten-app/releases/download/v1.2.0';

// 按 GitHub 以 `application/vnd.github.text+json` 返回的格式脱敏、删减。
Map<String, Object?> _release({
  Object? tag = 'v1.2.0',
  Object? page = _page,
  Object? notes = '- 修复了切歌时的卡顿\n- 新增检查更新',
  Object? assets,
}) {
  return {
    'url': 'https://api.github.com/repos/DiheMoe/alisten-app/releases/1',
    'html_url': page,
    'id': 1,
    'tag_name': tag,
    'name': 'Alisten 1.2.0',
    'draft': false,
    'prerelease': false,
    'published_at': '2026-11-01T08:00:00Z',
    'author': {'login': 'github-actions[bot]', 'id': 41898282},
    'assets':
        assets ??
        [
          _asset('Alisten-1.2.0-arm64-v8a.apk'),
          _asset('Alisten-1.2.0-armeabi-v7a.apk'),
          _asset('Alisten-1.2.0-ios-unsigned.ipa'),
        ],
    'body_text': notes,
  };
}

Map<String, Object?> _asset(String name, {String? url}) {
  return {
    'name': name,
    'size': 32000000,
    'content_type': 'application/vnd.android.package-archive',
    'state': 'uploaded',
    'browser_download_url': url ?? '$_download/$name',
  };
}

void main() {
  late FakeHttpAdapter adapter;
  late Dio dio;

  setUp(() {
    adapter = FakeHttpAdapter();
    dio = Dio()..httpClientAdapter = adapter;
  });

  tearDown(() => dio.close(force: true));

  Future<void> expectUnavailable(GitHubReleaseSource source, {String? reason}) {
    return expectLater(
      source.latest(),
      throwsA(isA<ReleaseUnavailable>()),
      reason: reason,
    );
  }

  test('the latest release is asked of GitHub as plain text, without '
      'credentials, and read with its notes, page and downloads', () async {
    adapter.respond(200, _release());

    final release = await GitHubReleaseSource(dio).latest();

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(), _latest);
    final headers = {
      for (final MapEntry(:key, :value) in request.headers.entries)
        key.toLowerCase(): value,
    };
    expect(headers['accept'], 'application/vnd.github.text+json');
    expect(headers['x-github-api-version'], '2022-11-28');
    expect(headers.keys, isNot(contains('authorization')));
    expect(headers.keys, isNot(contains('cookie')));
    expect(request.uri.userInfo, isEmpty);
    expect(release.tag, 'v1.2.0');
    expect(release.notes, '- 修复了切歌时的卡顿\n- 新增检查更新');
    expect(release.page, Uri.parse(_page));
    expect(
      [
        for (final asset in release.assets)
          (asset.name, '${asset.downloadUrl}'),
      ],
      [
        (
          'Alisten-1.2.0-arm64-v8a.apk',
          '$_download/Alisten-1.2.0-arm64-v8a.apk',
        ),
        (
          'Alisten-1.2.0-armeabi-v7a.apk',
          '$_download/Alisten-1.2.0-armeabi-v7a.apk',
        ),
        (
          'Alisten-1.2.0-ios-unsigned.ipa',
          '$_download/Alisten-1.2.0-ios-unsigned.ipa',
        ),
      ],
    );
  });

  test('a release without notes has empty notes', () async {
    adapter.respond(200, _release(notes: null));

    expect((await GitHubReleaseSource(dio).latest()).notes, isEmpty);
  });

  test('a release without downloads has none', () async {
    adapter.respond(200, _release(assets: const []));

    expect((await GitHubReleaseSource(dio).latest()).assets, isEmpty);
  });

  test('an answer other than 200 is unavailable, and a redirect is not '
      'followed', () async {
    for (final status in [201, 204, 301, 302, 304, 403, 404, 429, 500, 503]) {
      adapter.respondRaw(
        status,
        jsonEncode(_release()),
        null,
        headers: {
          'location': ['https://api.github.com/repositories/1/releases/latest'],
        },
      );

      await expectUnavailable(GitHubReleaseSource(dio), reason: '$status');
    }
    expect(adapter.requests, hasLength(10));
    expect(
      adapter.requests.map((request) => request.followRedirects),
      everyElement(isFalse),
    );
  });

  test('a request that cannot be sent is unavailable', () async {
    adapter.fail();

    await expectUnavailable(GitHubReleaseSource(dio));
  });

  test('a request that hangs is given up after 10 seconds and cancelled', () {
    fakeAsync((async) {
      adapter.neverRespond();
      Object? failure;
      unawaited(
        GitHubReleaseSource(dio)
            .latest()
            .then<void>((_) {}, onError: (Object error) => failure = error),
      );

      async.elapse(const Duration(seconds: 9));
      expect(adapter.requests, hasLength(1));
      expect(failure, isNull);

      async.elapse(const Duration(seconds: 1));
      expect(failure, isA<ReleaseUnavailable>());
      expect(adapter.cancelled, isTrue);
    });
  });

  test('an answer up to the size limit is read, a larger one is '
      'unavailable', () async {
    String padded(int bytes) {
      final head = jsonEncode(_release(notes: ''));
      final used = utf8.encode(head).length;
      return head.replaceFirst(
        '"body_text":""',
        '"body_text":"${'x' * (bytes - used)}"',
      );
    }

    const limit = GitHubReleaseSource.maxBodyBytes;
    adapter.respondRaw(200, padded(limit), null);
    expect(
      (await GitHubReleaseSource(dio).latest()).notes,
      hasLength(greaterThan(0)),
    );

    adapter.respondRaw(200, padded(limit + 1), null);
    await expectUnavailable(GitHubReleaseSource(dio));
  });

  test('an answer that does not end stops being read at the size '
      'limit', () async {
    final streaming = _StreamingAdapter();
    addTearDown(streaming.close);
    final dio = Dio()..httpClientAdapter = streaming;
    addTearDown(() => dio.close(force: true));
    streaming.body
      ..add(Uint8List(GitHubReleaseSource.maxBodyBytes))
      ..add(Uint8List(1));

    await expectUnavailable(GitHubReleaseSource(dio));
    expect(streaming.cancelled, isTrue);
  });

  test('an answer broken off midway is unavailable', () async {
    final streaming = _StreamingAdapter();
    addTearDown(streaming.close);
    final dio = Dio()..httpClientAdapter = streaming;
    addTearDown(() => dio.close(force: true));
    streaming.body
      ..add(Uint8List.fromList(utf8.encode('{"tag_name":')))
      ..addError(const SocketException('Connection reset by peer'));

    await expectUnavailable(GitHubReleaseSource(dio));
  });

  test('an answer that is not a release is unavailable', () async {
    for (final body in [
      'not json',
      '[]',
      '"v1.2.0"',
      jsonEncode(_release(tag: null)),
      jsonEncode(_release(tag: 120)),
      jsonEncode(_release(page: null)),
      jsonEncode(_release(notes: 12)),
      jsonEncode(_release(assets: 'none')),
    ]) {
      adapter.respondRaw(200, body, null);

      await expectUnavailable(GitHubReleaseSource(dio), reason: body);
    }
  });

  test('an answer that is not UTF-8 is unavailable', () async {
    adapter.respondBytes(200, const [0x7b, 0xff, 0xfe, 0x7d]);

    await expectUnavailable(GitHubReleaseSource(dio));
  });

  test('a release page that is not this repository\'s releases on '
      'https://github.com is unavailable', () async {
    for (final page in [
      'http://github.com/DiheMoe/alisten-app/releases/tag/v1.2.0',
      'https://github.com.evil.example/DiheMoe/alisten-app/releases/tag/v1.2.0',
      'https://evil.example/DiheMoe/alisten-app/releases/tag/v1.2.0',
      'https://gist.github.com/DiheMoe/alisten-app/releases/tag/v1.2.0',
      'https://github.com:8443/DiheMoe/alisten-app/releases/tag/v1.2.0',
      'https://someone@github.com/DiheMoe/alisten-app/releases/tag/v1.2.0',
      'https://github.com/Other/alisten-app/releases/tag/v1.2.0',
      'https://github.com/DiheMoe/other-app/releases/tag/v1.2.0',
      'https://github.com/DiheMoe/alisten-app/tags/v1.2.0',
      'https://github.com/DiheMoe/alisten-app/releases',
      'https://github.com/DiheMoe/alisten-app/releases/',
      'https://github.com/DiheMoe/alisten-app/releases/../../evil/releases/x',
      'https://github.com/DiheMoe%2Falisten-app/releases/tag/v1.2.0',
      'javascript:alert(1)',
      '',
      '$_page?after=1',
      '$_page#notes',
      '$_page?',
      '$_page/extra',
      'https://github.com/DiheMoe/alisten-app/releases/v1.2.0',
      'https://github.com/DiheMoe/alisten-app/releases/latest',
      'https://github.com/DiheMoe/alisten-app/releases/tag/v9.9.9',
      'https://github.com/DiheMoe/alisten-app/releases/tag/v1.2.0%2F..',
      'https://github.com/DiheMoe/alisten-app/releases/tag/v1.2.0%5Cx',
      'https://github.com/DiheMoe/alisten-app/releases/tag/v1.2.0%25',
      'https://github.com/DiheMoe/alisten-app/Releases/tag/v1.2.0',
      'https://github.com/DiheMoe/alisten-app/releases/Tag/v1.2.0',
    ]) {
      adapter.respond(200, _release(page: page));

      await expectUnavailable(GitHubReleaseSource(dio), reason: page);
    }
  });

  test('the owner and the repository are matched regardless of case, as '
      'GitHub does', () async {
    adapter.respond(
      200,
      _release(
        page: 'https://github.com/dihemoe/Alisten-App/releases/tag/v1.2.0',
        assets: [
          _asset(
            'Alisten-1.2.0-arm64-v8a.apk',
            url:
                'https://github.com/DIHEMOE/ALISTEN-APP/releases/download/'
                'v1.2.0/Alisten-1.2.0-arm64-v8a.apk',
          ),
        ],
      ),
    );

    final release = await GitHubReleaseSource(dio).latest();

    expect(
      release.page,
      Uri.parse('https://github.com/dihemoe/Alisten-App/releases/tag/v1.2.0'),
    );
    expect(
      [for (final asset in release.assets) asset.name],
      ['Alisten-1.2.0-arm64-v8a.apk'],
    );
  });

  test('downloads not under this repository\'s releases/download on '
      'https://github.com are left out', () async {
    adapter.respond(
      200,
      _release(
        assets: [
          _asset(
            'http.apk',
            url: 'http://github.com/DiheMoe/alisten-app/releases/download/v1/a.apk',
          ),
          _asset(
            'cdn.apk',
            url: 'https://objects.githubusercontent.com/DiheMoe/alisten-app/releases/download/v1/a.apk',
          ),
          _asset(
            'page.apk',
            url: 'https://github.com/DiheMoe/alisten-app/releases/tag/v1.2.0',
          ),
          _asset(
            'other.apk',
            url: 'https://github.com/Other/alisten-app/releases/download/v1/a.apk',
          ),
          _asset(
            'dots.apk',
            url: 'https://github.com/DiheMoe/alisten-app/releases/download/../../../evil/a.apk',
          ),
          _asset(
            'bare.apk',
            url: 'https://github.com/DiheMoe/alisten-app/releases/download/',
          ),
          _asset('query.apk', url: '$_download/a.apk?raw=1'),
          _asset('fragment.apk', url: '$_download/a.apk#x'),
          _asset(
            'no-tag.apk',
            url: 'https://github.com/DiheMoe/alisten-app/releases/download/a.apk',
          ),
          _asset('deeper.apk', url: '$_download/sub/a.apk'),
          _asset(
            'other-tag.apk',
            url: 'https://github.com/DiheMoe/alisten-app/releases/download/v9.9.9/a.apk',
          ),
          _asset(
            'encoded-slash-tag.apk',
            url:
                'https://github.com/DiheMoe/alisten-app/releases/download/'
                '..%2F..%2F..%2F..%2Fevil%2Frepo%2Freleases%2Fdownload%2Fv1/a.apk',
          ),
          _asset(
            'encoded-slash-name.apk',
            url: '$_download/..%2F..%2F..%2F..%2F..%2Fevil%2Fa.apk',
          ),
          _asset('backslash.apk', url: '$_download/..%5Cevil.apk'),
          _asset('percent.apk', url: '$_download/a%252F.apk'),
          _asset(
            'case.apk',
            url: 'https://github.com/DiheMoe/alisten-app/Releases/download/v1.2.0/a.apk',
          ),
          {'name': 'no-url.apk'},
          {'browser_download_url': '$_download/no-name.apk'},
          'not an asset',
          _asset('Alisten-1.2.0-arm64-v8a.apk'),
        ],
      ),
    );

    final release = await GitHubReleaseSource(dio).latest();

    expect(
      [for (final asset in release.assets) asset.name],
      ['Alisten-1.2.0-arm64-v8a.apk'],
    );
  });
}

final class _StreamingAdapter implements HttpClientAdapter {
  final body = StreamController<Uint8List>();
  bool cancelled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    unawaited(cancelFuture?.then((_) => cancelled = true));
    return ResponseBody(body.stream, 200);
  }

  @override
  void close({bool force = false}) => unawaited(body.close());
}
