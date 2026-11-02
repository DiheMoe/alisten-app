import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alisten/core/cache/cached_cover_image.dart';
import 'package:alisten/core/cache/disk_cover_cache.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cover_cache_test_doubles.dart';

const _cover = 'https://covers.example.com/a.jpg';

void main() {
  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  Widget covers(ImageProvider Function(String url) resolve, {int count = 1}) {
    return MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: CoverImages(
        resolve: resolve,
        child: Column(
          children: [
            for (var index = 0; index < count; index++)
              const CoverArt(url: _cover, size: 48),
          ],
        ),
      ),
    );
  }

  Finder placeholder() => find.byIcon(Icons.music_note_rounded);

  testWidgets('a cover shown twice is read from the cache once', (
    tester,
  ) async {
    final cache = FakeCoverCache(
      covers: {_cover: (await tester.runAsync(_png))!},
    );

    await tester.pumpWidget(
      covers((url) => CachedCoverImage(url, cache), count: 2),
    );
    await _finishLoading(tester);

    expect(cache.loads, [_cover]);
    expect(placeholder(), findsNothing);
    expect(
      tester.widgetList<RawImage>(find.byType(RawImage)).map((r) => r.image),
      everyElement(isNotNull),
    );
  });

  testWidgets('a cover whose download hangs shows the placeholder once the '
      'download times out, and is not stored', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('alisten-covers-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final server = CoverServer()..hang = true;
    final cache = DiskCoverCache(
      Dio()..httpClientAdapter = server,
      directory: () async => root,
    );
    await tester.pumpWidget(covers((url) => CachedCoverImage(url, cache)));
    await _pumpUntil(tester, () => server.requests.isNotEmpty);
    expect(placeholder(), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await _finishLoading(tester);

    expect(placeholder(), findsOneWidget);
    expect(server.cancelled, 1);
    expect(await tester.runAsync(() => root.list().toList()), isEmpty);
  });

  testWidgets('a stored cover that cannot be decoded is discarded', (
    tester,
  ) async {
    final cache = FakeCoverCache(
      covers: {_cover: Uint8List.fromList('<html>login</html>'.codeUnits)},
    );

    await tester.pumpWidget(covers((url) => CachedCoverImage(url, cache)));
    await _finishLoading(tester);

    expect(placeholder(), findsOneWidget);
    expect(cache.discarded, [_cover]);
  });

  test('the address of a cover stays out of its description', () {
    final image = CachedCoverImage(_cover, FakeCoverCache());

    expect('$image', isNot(contains('example')));
  });
}

// 让出真实时间给文件读写和解码，同时推进假时间，直到 [done]，最多等 5 秒。
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  final waited = Stopwatch()..start();
  while (!done() && waited.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

Future<void> _finishLoading(WidgetTester tester) async {
  await _pumpUntil(tester, () => imageCache.pendingImageCount == 0);
  await tester.pump();
}

Future<Uint8List> _png() async {
  final image = await createTestImage(width: 8, height: 8, cache: false);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
