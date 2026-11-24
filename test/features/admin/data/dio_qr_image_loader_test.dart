import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/admin/data/dio_qr_image_loader.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/api/fake_http_adapter.dart';

const _png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const _remote = 'https://img.example/qr.png';

void main() {
  late FakeHttpAdapter adapter;
  late Dio dio;

  setUp(() {
    adapter = FakeHttpAdapter();
    dio = Dio()..httpClientAdapter = adapter;
  });

  tearDown(() => dio.close(force: true));

  test('a code inside a data URI is decoded here, without a request', () async {
    final bytes = await DioQrImageLoader(dio)
        .load('data:image/png;base64,iVBORw0KGgo=');

    expect(bytes, _png);
    expect(adapter.requests, isEmpty);
  });

  test('a data URI that cannot be decoded is unavailable', () async {
    await expectLater(
      DioQrImageLoader(dio).load('data:image/png;base64,%%%'),
      throwsA(isA<QrImageUnavailable>()),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'a code on the web is downloaded over HTTPS without a referer',
    () async {
      adapter.respondBytes(200, _png);

      final bytes = await DioQrImageLoader(dio).load(_remote);

      expect(bytes, _png);
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.toString(), _remote);
      expect(
        request.headers.keys.map((name) => name.toLowerCase()),
        isNot(contains('referer')),
      );
    },
  );

  test('a download that passes through plain HTTP at any hop is unavailable, '
      'even when it ends on HTTPS', () async {
    for (final hops in [
      ['http://img.example/qr.png'],
      ['http://img.example/hop', 'https://cdn.example/qr.png'],
    ]) {
      adapter.respondBytes(
        200,
        _png,
        redirects: [
          for (final hop in hops) RedirectRecord(302, 'GET', Uri.parse(hop)),
        ],
      );

      await expectLater(
        DioQrImageLoader(dio).load(_remote),
        throwsA(isA<QrImageUnavailable>()),
        reason: '$hops',
      );
    }
  });

  // dart:io 记录的是 Location 原文，可能是相对地址。
  test('a download redirected over HTTPS, to another address or a relative '
      'one, is the image', () async {
    for (final hops in [
      ['https://cdn.example/qr.png'],
      ['/codes/qr.png', 'qr2.png'],
    ]) {
      adapter.respondBytes(
        200,
        _png,
        redirects: [
          for (final hop in hops) RedirectRecord(302, 'GET', Uri.parse(hop)),
        ],
      );

      expect(await DioQrImageLoader(dio).load(_remote), _png, reason: '$hops');
    }
  });

  test('only a 200 answer counts as the image', () async {
    for (final status in [404, 203, 206]) {
      adapter.respondBytes(status, _png);

      await expectLater(
        DioQrImageLoader(dio).load(_remote),
        throwsA(isA<QrImageUnavailable>()),
        reason: '$status',
      );
    }
  });

  test('an empty image is unavailable', () async {
    adapter.respondBytes(200, const []);

    await expectLater(
      DioQrImageLoader(dio).load(_remote),
      throwsA(isA<QrImageUnavailable>()),
    );
  });

  test('a code anywhere but HTTPS or a data URI is never asked for', () async {
    for (final address in [
      'http://img.example/qr.png',
      'ftp://img.example/qr.png',
      'qr.png',
      '',
    ]) {
      await expectLater(
        DioQrImageLoader(dio).load(address),
        throwsA(isA<QrImageUnavailable>()),
        reason: address,
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('a code larger than allowed is unavailable', () async {
    adapter.respondBytes(200, _png);

    await expectLater(
      DioQrImageLoader(dio, maxBytes: 4).load(_remote),
      throwsA(isA<QrImageUnavailable>()),
    );
  });

  test('a download that hangs is given up after 15 seconds and '
      'cancelled', () {
    fakeAsync((async) {
      adapter.neverRespond();
      Object? failure;
      unawaited(
        DioQrImageLoader(dio)
            .load(_remote)
            .then<void>(
              (_) {},
              onError: (Object error) {
                failure = error;
              },
            ),
      );

      async.elapse(const Duration(seconds: 14));
      expect(adapter.requests, hasLength(1));
      expect(failure, isNull);

      async.elapse(const Duration(seconds: 1));
      expect(failure, isA<QrImageUnavailable>());
      expect(adapter.cancelled, isTrue);
    });
  });

  test('the address of a code never reaches the log', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add(message);
    addTearDown(() => AppLog.onRecord = null);
    adapter.respondBytes(404, const [1]);

    await expectLater(
      DioQrImageLoader(dio).load('https://img.example/qr.png?k=secret'),
      throwsA(isA<QrImageUnavailable>()),
    );
    await expectLater(
      DioQrImageLoader(dio).load('http://img.example/qr.png?k=secret'),
      throwsA(isA<QrImageUnavailable>()),
    );

    expect(records, isNotEmpty);
    expect(records.where((record) => record.contains('secret')), isEmpty);
    expect(records.where((record) => record.contains('img.example')), isEmpty);
  });
}
