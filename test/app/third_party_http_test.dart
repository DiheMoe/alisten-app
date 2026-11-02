// just_audio 的流式音源 API 是实验性的。
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:alisten/app/app_version.dart';
import 'package:alisten/app/third_party_http.dart';
import 'package:alisten/features/playback/data/audio_stream_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('third-party downloads name the app instead of dart:io', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final agents = <String?>[];
    server.listen((request) {
      agents.add(request.headers.value(HttpHeaders.userAgentHeader));
      request.response
        ..statusCode = HttpStatus.ok
        ..add(const [1, 2, 3]);
      unawaited(request.response.close());
    });
    final dio = newThirdPartyDio();
    addTearDown(() => dio.close(force: true));

    await dio.get<List<int>>(
      'http://127.0.0.1:${server.port}/cover.jpg',
      options: Options(responseType: ResponseType.bytes),
    );

    expect(agents, ['Alisten/1.0.0']);
  });

  test('audio streamed through it still names the app after the redirect '
      'to the CDN', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final agents = <String, String?>{};
    server.listen((request) {
      agents[request.uri.path] = request.headers.value(
        HttpHeaders.userAgentHeader,
      );
      if (request.uri.path == '/media') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/cdn.mp3');
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..add(const [1, 2, 3]);
      }
      unawaited(request.response.close());
    });
    final streams = AudioStreamFactory(newThirdPartyDio());
    addTearDown(streams.close);

    final response = await streams
        .source(Uri.parse('http://127.0.0.1:${server.port}/media'))
        .request(0);
    await response.stream.drain<void>();

    expect(agents, {'/media': 'Alisten/1.0.0', '/cdn.mp3': 'Alisten/1.0.0'});
  });

  test('the user agent carries the version without the build number', () {
    expect(appUserAgent, 'Alisten/${appVersion.split('+').first}');
  });
}
