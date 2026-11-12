import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _cover = 'https://cover/a';

void main() {
  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  Widget app(Widget child) {
    return MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: Center(child: child),
    );
  }

  testWidgets('a cover comes from the image source above it, decoded at the '
      'size it is shown', (tester) async {
    final png = (await tester.runAsync(() => _png(200)))!;
    final asked = <String>[];
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(
        CoverImages(
          resolve: (url) {
            asked.add(url);
            return MemoryImage(png);
          },
          child: const CoverArt(url: _cover, size: 48),
        ),
      ),
    );
    await _finishLoading(tester);

    expect(asked.toSet(), {_cover});
    expect(find.byIcon(AlistenIcons.musicNote), findsNothing);
    final shown = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(shown.width, 96);
  });

  testWidgets('a cover the image source cannot load shows the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CoverImages(
          resolve: (url) => MemoryImage(Uint8List(0)),
          child: const CoverArt(url: _cover, size: 48),
        ),
      ),
    );
    await _finishLoading(tester);

    expect(find.byIcon(AlistenIcons.musicNote), findsOneWidget);
  });

  testWidgets('without an image the placeholder shows the given icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: const Row(
          children: [
            CoverArt(
              url: null,
              size: 52,
              placeholderIcon: AlistenIcons.starFill,
            ),
            CoverArt(url: '', size: 52),
          ],
        ),
      ),
    );

    expect(find.byIcon(AlistenIcons.starFill), findsOneWidget);
    expect(find.byIcon(AlistenIcons.musicNote), findsOneWidget);
  });
}

// 解码在引擎中真实异步进行：让出真实时间，直到没有加载中的封面，最多等 5 秒。
Future<void> _finishLoading(WidgetTester tester) async {
  final waited = Stopwatch()..start();
  while (imageCache.pendingImageCount > 0 &&
      waited.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pump();
}

Future<Uint8List> _png(int side) async {
  final image = await createTestImage(width: side, height: side, cache: false);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
