// just_audio 的流式音源 API 是实验性的。
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:io';

import 'package:alisten/features/playback/data/audio_stream_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/controlled_media_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controlled WAV backend serves a complete stream', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final backend = ControlledMediaBackend();
    final uri = await backend.start();
    final factory = AudioStreamFactory(Dio());
    try {
      final response = await factory.source(uri).request();
      final bytes = await response.stream.fold<List<int>>(
        [],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      expect(bytes.length, greaterThan(44));
      expect(const Latin1Decoder().convert(bytes.sublist(0, 4)), 'RIFF');
    } finally {
      factory.close();
      await backend.close();
    }
  });
}
