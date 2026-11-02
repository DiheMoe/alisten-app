import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/cover_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cover colours are read from the image source given', (
    tester,
  ) async {
    const red = Color(0xFFD02020);
    final png = (await tester.runAsync(() => _solidPng(red)))!;
    final asked = <String>[];
    final loader = ImageCoverSchemeLoader((url) {
      asked.add(url);
      return MemoryImage(png);
    });

    final scheme = (await tester.runAsync(
      () => loader.load('https://cover/a', Brightness.dark),
    ))!;

    expect(asked, ['https://cover/a']);
    expect(
      scheme.primary,
      ColorScheme.fromSeed(
        seedColor: red,
        brightness: Brightness.dark,
        dynamicSchemeVariant: AlistenColors.schemeVariant,
      ).primary,
    );
  });

  late _CountingLoader source;
  late CoverPalette palette;

  setUp(() {
    source = _CountingLoader();
    palette = CoverPalette(source);
  });

  test('a cover is read once per brightness while it is remembered', () async {
    final first = await palette.load('https://cover/a', Brightness.dark);
    final again = await palette.load('https://cover/a', Brightness.dark);
    await palette.load('https://cover/a', Brightness.light);

    expect(again, same(first));
    expect(source.reads, [
      ('https://cover/a', Brightness.dark),
      ('https://cover/a', Brightness.light),
    ]);
  });

  test('the 17th cover forgets the one used longest ago', () async {
    for (var index = 0; index < 16; index++) {
      await palette.load('https://cover/$index', Brightness.dark);
    }
    // 再次使用最旧的封面后，第二张成为最旧的。
    await palette.load('https://cover/0', Brightness.dark);
    await palette.load('https://cover/16', Brightness.dark);
    source.reads.clear();

    await palette.load('https://cover/0', Brightness.dark);
    await palette.load('https://cover/16', Brightness.dark);
    expect(source.reads, isEmpty);
    await palette.load('https://cover/1', Brightness.dark);
    expect(source.reads, [('https://cover/1', Brightness.dark)]);
  });
}

Future<Uint8List> _solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 16);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

final class _CountingLoader implements CoverSchemeLoader {
  final reads = <(String, Brightness)>[];

  @override
  Future<ColorScheme> load(String url, Brightness brightness) async {
    reads.add((url, brightness));
    return ColorScheme.fromSeed(
      seedColor: Color(url.hashCode | 0xFF000000),
      brightness: brightness,
    );
  }
}
