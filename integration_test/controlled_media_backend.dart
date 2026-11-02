import 'dart:io';

import 'fixtures/short_audio.dart';

final class ControlledMediaBackend {
  HttpServer? _server;

  Future<Uri> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final audio = shortWav();
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.headers.set(
        HttpHeaders.contentLengthHeader,
        audio.length,
      );
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.add(audio);
      await request.response.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/audio.wav');
  }

  Future<void> close() => _server!.close(force: true);
}
