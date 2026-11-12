import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/aurora_background.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:alisten/shared/ui/flowing_cover_backdrop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _second = Duration(seconds: 1);

void main() {
  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  group('flowPhase', () {
    test('angles stay small however long the room plays', () {
      final phase = flowPhase(10 * 24 * 3600 + 0.5);

      for (final angle in [phase.a, phase.b, phase.c]) {
        expect(angle, inInclusiveRange(0, 2 * math.pi));
      }
      expect(phase.warp, inInclusiveRange(0, 1));
    });

    test('each layer turns once in its own period', () {
      expect(flowPhase(30).a, closeTo(math.pi / 2, 1e-9));
      expect(flowPhase(35).b, closeTo(math.pi, 1e-9));
      expect(flowPhase(45).c, closeTo(math.pi, 1e-9));
    });
  });

  Widget backdrop(
    Uint8List png,
    String? url, {
    bool disableAnimations = false,
    bool tickers = true,
    Set<String> missing = const {},
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: TickerMode(
          enabled: tickers,
          child: CoverImages(
            resolve: (url) =>
                _ServedCover(url, missing.contains(url) ? null : png),
            child: FlowingCoverBackdrop(url: url),
          ),
        ),
      ),
    );
  }

  testWidgets('without a cover the aurora shows', (tester) async {
    final png = (await tester.runAsync(_png))!;

    await tester.pumpWidget(backdrop(png, null));
    await _finishLoading(tester);

    expect(find.byType(AuroraBackground), findsOneWidget);
    expect(_flow(), findsNothing);
  });

  testWidgets('a cover that cannot load leaves the aurora', (tester) async {
    final png = (await tester.runAsync(_png))!;

    await tester.pumpWidget(
      backdrop(png, 'https://cover/a', missing: {'https://cover/a'}),
    );
    await _finishLoading(tester);

    expect(find.byType(AuroraBackground), findsOneWidget);
    expect(_flow(), findsNothing);
  });

  testWidgets('a cover flows at about 30 frames a second, and replaces the '
      'aurora once it has faded in', (tester) async {
    final png = (await tester.runAsync(_png))!;

    await tester.pumpWidget(backdrop(png, 'https://cover/a'));
    await _finishLoading(tester);
    expect(_flow(), findsOneWidget);

    await tester.pump(_second);
    expect(find.byType(AuroraBackground), findsNothing);
    expect(await _framesIn(tester, _second), inInclusiveRange(25, 31));
  });

  testWidgets('the shader renders at half the screen resolution and the '
      'result is stretched over the page', (tester) async {
    final png = (await tester.runAsync(_png))!;

    await tester.pumpWidget(backdrop(png, 'https://cover/a'));
    await _finishLoading(tester);

    final size = tester.getSize(_flow());
    final pixels =
        size * MediaQuery.devicePixelRatioOf(tester.element(_flow())) / 2;
    expect(
      _flow(),
      paints..drawImageRect(
        source:
            Offset.zero &
            Size(pixels.width.ceilToDouble(), pixels.height.ceilToDouble()),
        destination: Offset.zero & size,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the flow stands still when animations are removed', (
    tester,
  ) async {
    final png = (await tester.runAsync(_png))!;

    await tester.pumpWidget(
      backdrop(png, 'https://cover/a', disableAnimations: true),
    );
    await _finishLoading(tester);

    expect(_flow(), findsOneWidget);
    expect(find.byType(AuroraBackground), findsNothing);
    expect(await _framesIn(tester, _second), 0);
  });

  testWidgets('the flow stands still while tickers are off', (tester) async {
    final png = (await tester.runAsync(_png))!;

    await tester.pumpWidget(backdrop(png, 'https://cover/a', tickers: false));
    await _finishLoading(tester);

    expect(await _framesIn(tester, _second), 0);
  });

  testWidgets('the flow stands still while the keyboard is up', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    final png = (await tester.runAsync(_png))!;
    await tester.pumpWidget(backdrop(png, 'https://cover/a'));
    await _finishLoading(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    expect(await _framesIn(tester, _second), 0);
  });

  testWidgets('a new cover crossfades, and the old one stays until it is '
      'ready', (tester) async {
    final png = (await tester.runAsync(_png))!;
    await tester.pumpWidget(backdrop(png, 'https://cover/a'));
    await _finishLoading(tester);
    await tester.pump(_second);

    await tester.pumpWidget(backdrop(png, 'https://cover/b'));
    expect(_flow(), findsOneWidget);
    expect(find.byType(AuroraBackground), findsNothing);

    await _finishLoading(tester);
    await tester.pump(_second);

    expect(_flow(), findsOneWidget);
    expect(find.byType(AuroraBackground), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cover overtaken by the next is dropped', (tester) async {
    final png = (await tester.runAsync(_png))!;
    await tester.pumpWidget(backdrop(png, 'https://cover/a'));

    await tester.pumpWidget(backdrop(png, 'https://cover/b'));
    await _finishLoading(tester);
    await tester.pump(_second);

    expect(_flow(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a room that stops playing goes back to the aurora', (
    tester,
  ) async {
    final png = (await tester.runAsync(_png))!;
    await tester.pumpWidget(backdrop(png, 'https://cover/a'));
    await _finishLoading(tester);
    await tester.pump(_second);

    await tester.pumpWidget(backdrop(png, null));
    await tester.pump(_second);
    await tester.pump(_second);

    expect(_flow(), findsNothing);
    expect(find.byType(AuroraBackground), findsOneWidget);
  });
}

Finder _flow() {
  return find.descendant(
    of: find.byType(FlowingCoverBackdrop),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_FlowPainter',
    ),
  );
}

Future<void> _finishLoading(WidgetTester tester) async {
  for (var turn = 0; turn < 6; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<int> _framesIn(WidgetTester tester, Duration span) async {
  await tester.pump();
  const vsync = Duration(microseconds: 8333);
  var frames = 0;
  var counting = true;
  void count(Duration _) {
    if (!counting) return;
    frames++;
    tester.binding.addPostFrameCallback(count);
  }

  tester.binding.addPostFrameCallback(count);
  for (var elapsed = Duration.zero; elapsed < span; elapsed += vsync) {
    await tester.pump(vsync);
  }
  counting = false;
  return frames;
}

Future<Uint8List> _png() async {
  final image = await createTestImage(width: 8, height: 8, cache: false);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

final class _ServedCover extends ImageProvider<_ServedCover> {
  const _ServedCover(this.url, this.png);

  final String url;
  final Uint8List? png;

  @override
  Future<_ServedCover> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ServedCover key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = png;
    if (bytes == null) throw StateError('cover not found');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is _ServedCover && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
