import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('a small button still takes 48 by 48 and is pressed once', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      app(
        IconCircleButton(
          icon: Icons.skip_next_rounded,
          semanticLabel: '投票切歌',
          diameter: 36,
          onPressed: () => presses++,
        ),
      ),
    );

    final size = tester.getSize(find.byType(IconCircleButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(find.bySemanticsLabel('投票切歌')),
      isSemantics(
        label: '投票切歌',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('投票切歌'));
    await tester.pumpAndSettle();
    expect(presses, 1);
  });

  testWidgets('an image fades in over the icon once loaded, in the same '
      'circle, and is not read out', (tester) async {
    final semantics = tester.ensureSemantics();
    final png = (await tester.runAsync(_png))!;
    await tester.pumpWidget(
      app(
        IconCircleButton(
          icon: Icons.settings_rounded,
          semanticLabel: '设置',
          style: IconCircleButtonStyle.plain,
          image: MemoryImage(png),
          onPressed: () {},
        ),
      ),
    );
    final button = tester.getRect(find.byType(IconCircleButton));
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);

    await _finishLoading(tester);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.getRect(find.byType(IconCircleButton)), button);

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(
      tester.getSize(find.byType(RawImage)),
      const Size.square(AlistenSizes.avatar),
    );
    expect(tester.getCenter(find.byType(RawImage)), button.center);
    expect(tester.getRect(find.byType(IconCircleButton)), button);
    final node = tester.getSemantics(find.bySemanticsLabel('设置'));
    expect(node.label, '设置');
    expect(node.childrenCount, 0);
    semantics.dispose();
  });

  testWidgets('with reduced motion the image replaces the icon at once', (
    tester,
  ) async {
    final png = (await tester.runAsync(_png))!;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: app(
          IconCircleButton(
            icon: Icons.settings_rounded,
            semanticLabel: '设置',
            image: MemoryImage(png),
            onPressed: () {},
          ),
        ),
      ),
    );

    await _finishLoading(tester);
    await tester.pump();

    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  testWidgets('an image that cannot be loaded leaves the icon', (tester) async {
    await tester.pumpWidget(
      app(
        IconCircleButton(
          icon: Icons.settings_rounded,
          semanticLabel: '设置',
          image: MemoryImage(Uint8List(0)),
          onPressed: () {},
        ),
      ),
    );

    await _finishLoading(tester);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('a button without an action is announced as disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IconCircleButton(
          icon: Icons.skip_next_rounded,
          semanticLabel: '投票切歌',
          onPressed: null,
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('投票切歌')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
  });
}

// 解码在引擎中真实异步进行：让出真实时间，直到没有加载中的图片，最多等 5 秒。
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

Future<Uint8List> _png() async {
  final image = await createTestImage(width: 8, height: 8, cache: false);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
