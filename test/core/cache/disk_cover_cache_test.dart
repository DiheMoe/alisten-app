import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:alisten/core/cache/disk_cover_cache.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cover_cache_test_doubles.dart';

const _a = 'https://covers.example.com/a.jpg';
const _b = 'https://covers.example.com/b.jpg';
const _c = 'https://covers.example.com/c.jpg';
const _d = 'https://covers.example.com/d.jpg';

void main() {
  late Directory root;
  late Directory covers;
  late CoverServer server;
  late DateTime now;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('alisten-covers-');
    covers = Directory('${root.path}/covers');
    server = CoverServer();
    now = DateTime.utc(2026, 11, 2);
  });

  tearDown(() => root.delete(recursive: true));

  // 默认每读一次时钟前进一秒，使文件的使用先后确定。
  DiskCoverCache open({
    int maxBytes = 1 << 20,
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) {
    return DiskCoverCache(
      Dio()..httpClientAdapter = server,
      directory: directory ?? () async => covers,
      maxBytes: maxBytes,
      now: clock ?? () => now = now.add(const Duration(seconds: 1)),
    );
  }

  Future<List<String>> stored() async {
    if (!await covers.exists()) return const [];
    return [
      await for (final entity in covers.list())
        entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
    ];
  }

  test('a cover is downloaded once and read from this device after a '
      'restart', () async {
    server.covers[_a] = _bytes(100, 1);

    final downloaded = await open().load(_a);
    final cached = await open().load(_a);

    expect(downloaded, _bytes(100, 1));
    expect(cached, _bytes(100, 1));
    expect(server.requests, [_a]);
  });

  test('covers asked for at the same time are downloaded once', () async {
    server.covers[_a] = _bytes(100, 1);
    final cache = open();

    final loads = await Future.wait([cache.load(_a), cache.load(_a)]);

    expect(server.requests, [_a]);
    expect(loads, [_bytes(100, 1), _bytes(100, 1)]);
    expect(await stored(), hasLength(1));
  });

  test('a cover that fails to download is not stored, and is asked for '
      'again', () async {
    final cache = open();

    await expectLater(cache.load(_a), throwsA(anything));
    expect(await stored(), isEmpty);

    server.covers[_a] = _bytes(100, 1);
    expect(await cache.load(_a), _bytes(100, 1));
    expect(server.requests, [_a, _a]);
  });

  test('an empty answer is a failure and is not stored', () async {
    server.covers[_a] = const [];

    await expectLater(open().load(_a), throwsA(anything));
    expect(await stored(), isEmpty);
  });

  // 超时后不写缓存由 cached_cover_image_test 在真实目录上验证；这里不读写文件，
  // 整个过程才能都在假时间中进行。
  test('a download that hangs times out after 30 seconds and is '
      'cancelled', () {
    fakeAsync((async) {
      server.hang = true;
      final cache = open(
        directory: () async => throw const FileSystemException('unavailable'),
      );
      Object? failure;
      unawaited(
        cache
            .load(_a)
            .then<void>(
              (_) {},
              onError: (Object error) {
                failure = error;
              },
            ),
      );

      async.elapse(const Duration(seconds: 29));
      expect(server.requests, [_a]);
      expect(failure, isNull);

      async.elapse(const Duration(seconds: 1));
      expect(failure, isA<CoverUnavailable>());
      expect(server.cancelled, 1);
    });
  });

  test('a cover larger than 10 MB is a failure and is not stored', () async {
    server.covers[_a] = Uint8List(10 * 1024 * 1024 + 1);

    await expectLater(open().load(_a), throwsA(isA<CoverUnavailable>()));
    expect(await stored(), isEmpty);
  });

  test('a cover that arrives after the cache was cleared is shown but not '
      'stored', () async {
    server.covers[_a] = _bytes(100, 1);
    final respond = Completer<void>();
    server.responding = respond.future;
    final cache = open();
    final loading = cache.load(_a);
    await server.requested;

    await cache.clear();
    respond.complete();

    expect(await loading, _bytes(100, 1));
    expect(await stored(), isEmpty);
    expect(await cache.size(), 0);
  });

  test('covers are still trimmed when their use cannot be recorded', () async {
    for (final (index, url) in [_a, _b, _c, _d].indexed) {
      server.covers[url] = _bytes(100, index);
    }
    final cache = open(
      maxBytes: 250,
      clock: () => throw const FileSystemException('read-only'),
    );

    for (final url in [_a, _b, _c, _d]) {
      await cache.load(url);
    }
    await cache.trimming;

    expect(await cache.size(), 200);
    expect(await stored(), hasLength(2));
  });

  test('a cover is stored under a name that does not reveal its '
      'address', () async {
    server.covers[_a] = _bytes(100, 1);

    await open().load(_a);

    final name = (await stored()).single;
    expect(name, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(name, isNot(contains('example')));
  });

  test('beyond the limit the covers used longest ago are removed', () async {
    for (final (index, url) in [_a, _b, _c].indexed) {
      server.covers[url] = _bytes(100, index);
    }
    final cache = open(maxBytes: 250);
    await cache.load(_a);
    await cache.load(_b);
    // 再用一次 a 之后，b 成为最久未用的。
    await cache.load(_a);
    await cache.load(_c);
    await cache.trimming;

    expect(await cache.size(), 200);
    server.requests.clear();
    await cache.load(_a);
    await cache.load(_c);
    expect(server.requests, isEmpty);
    await cache.load(_b);
    expect(server.requests, [_b]);
  });

  test('the total is checked again only once enough has been written since '
      'the last check', () async {
    server.covers
      ..[_a] = _bytes(990, 1)
      ..[_b] = _bytes(40, 2)
      ..[_c] = _bytes(40, 3);
    final cache = open(maxBytes: 1000);
    await cache.load(_a);
    await cache.trimming;

    await cache.load(_b);
    await cache.trimming;
    expect(await cache.size(), 1030);

    await cache.load(_c);
    await cache.trimming;
    expect(await cache.size(), 80);
  });

  test('clearing removes every cover', () async {
    server.covers
      ..[_a] = _bytes(100, 1)
      ..[_b] = _bytes(50, 2);
    final cache = open();
    await cache.load(_a);
    await cache.load(_b);
    expect(await cache.size(), 150);

    await cache.clear();

    expect(await stored(), isEmpty);
    expect(await cache.size(), 0);
    await cache.load(_a);
    expect(server.requests, [_a, _b, _a]);
  });

  test('a cache that has stored nothing is empty', () async {
    final cache = open();

    expect(await cache.size(), 0);
    await cache.clear();
    expect(await cache.size(), 0);
  });

  test('a discarded cover is downloaded again', () async {
    server.covers[_a] = _bytes(100, 1);
    final cache = open();
    await cache.load(_a);

    await cache.discard(_a);

    expect(await stored(), isEmpty);
    await cache.load(_a);
    expect(server.requests, [_a, _a]);
  });

  test('the file of a cover is the one stored on this device, downloaded '
      'first when missing, and none when it cannot be stored', () async {
    server.covers[_a] = _bytes(100, 1);
    final cache = open();

    final file = await cache.localFile(_a);
    expect(file, isNotNull);
    expect(file!.scheme, 'file');
    expect(await File.fromUri(file).readAsBytes(), _bytes(100, 1));
    expect(await stored(), [file.pathSegments.last]);
    expect(await cache.localFile(_a), file);
    expect(server.requests, [_a]);

    await expectLater(cache.localFile(_b), throwsA(isA<CoverUnavailable>()));
    final nowhere = open(
      directory: () async => throw const FileSystemException('unavailable'),
    );
    expect(await nowhere.localFile(_a), isNull);
  });

  test(
    'covers are still downloaded when there is no cache directory',
    () async {
      server.covers[_a] = _bytes(100, 1);
      final cache = open(
        directory: () async => throw const FileSystemException('unavailable'),
      );

      expect(await cache.load(_a), _bytes(100, 1));
      expect(await cache.load(_a), _bytes(100, 1));
      expect(server.requests, [_a, _a]);
    },
  );
}

Uint8List _bytes(int length, int value) =>
    Uint8List.fromList(List.filled(length, value));
