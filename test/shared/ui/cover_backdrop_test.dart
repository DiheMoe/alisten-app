import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/cover_backdrop.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  late _CoverServer server;

  void testCovers(
    String description,
    Future<void> Function(WidgetTester tester, _CoverServer server) body,
  ) {
    testWidgets(description, (tester) async {
      server = _CoverServer((await tester.runAsync(_png))!);
      await body(tester, server);
    });
  }

  Widget backdrop(String? url, {Widget? child}) {
    return MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: CoverImages(
        resolve: server.cover,
        child: CoverBackdrop(url: url, child: child),
      ),
    );
  }

  List<ui.Image> shownCovers(WidgetTester tester) => [
    for (final image in tester.widgetList<RawImage>(find.byType(RawImage)))
      ?image.image,
  ];

  testCovers('a cover is blurred once into a still picture', (
    tester,
    server,
  ) async {
    await tester.pumpWidget(backdrop('https://cover/a'));
    await _finishLoading(tester);
    final blurred = shownCovers(tester).single;

    await tester.pumpWidget(
      backdrop('https://cover/a', child: const ColoredBox(color: Colors.black)),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(shownCovers(tester).single, same(blurred));
    // 之后的帧只拉伸铺满这张图，不再有逐帧重算模糊的图层。
    expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
    expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
    expect(server.requests, hasLength(1));
    // 取得第一帧后不再监听，动图封面也不会逐帧重新模糊。
    expect(imageCache.liveImageCount, 0);
  });

  testCovers('a cover already decoded shows on the first frame', (
    tester,
    server,
  ) async {
    await tester.pumpWidget(backdrop('https://cover/a'));
    await _finishLoading(tester);
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(backdrop('https://cover/a'));

    expect(shownCovers(tester), hasLength(1));
    expect(server.requests, hasLength(1));
  });

  testCovers('a new cover fades in over the old one, which is then released', (
    tester,
    _,
  ) async {
    await tester.pumpWidget(backdrop('https://cover/a'));
    await _finishLoading(tester);
    final first = shownCovers(tester).single;

    await tester.pumpWidget(backdrop('https://cover/b'));
    await _finishLoading(tester);
    expect(shownCovers(tester), hasLength(2));
    expect(first.debugDisposed, isFalse);

    await tester.pumpAndSettle();
    final shown = shownCovers(tester);
    expect(shown, hasLength(1));
    expect(shown.single, isNot(same(first)));
    expect(first.debugDisposed, isTrue);
  });

  testCovers('leaving the page releases the blurred cover', (tester, _) async {
    await tester.pumpWidget(backdrop('https://cover/a'));
    await _finishLoading(tester);
    final blurred = shownCovers(tester).single;

    await tester.pumpWidget(const SizedBox.shrink());

    expect(blurred.debugDisposed, isTrue);
  });

  testCovers('a cover that arrives after the page has gone is not kept', (
    tester,
    server,
  ) async {
    final respond = Completer<void>();
    server.responding = respond.future;
    await tester.pumpWidget(backdrop('https://cover/a'));
    await tester.pumpWidget(const SizedBox.shrink());

    respond.complete();
    await _finishLoading(tester);

    expect(server.requests, hasLength(1));
    expect(imageCache.liveImageCount, 0);
  });

  testCovers('a cover that fails to load leaves the backdrop bare', (
    tester,
    server,
  ) async {
    await tester.pumpWidget(backdrop('https://cover/missing'));

    await _finishLoading(tester);

    expect(server.requests, hasLength(1));
    expect(find.byType(RawImage), findsNothing);
  });

  testCovers('a cover that fails after the page has gone leaves nothing', (
    tester,
    server,
  ) async {
    final respond = Completer<void>();
    server.responding = respond.future;
    await tester.pumpWidget(backdrop('https://cover/missing'));
    await tester.pumpWidget(const SizedBox.shrink());

    respond.complete();
    await _finishLoading(tester);

    expect(server.requests, hasLength(1));
    expect(tester.takeException(), isNull);
    expect(find.byType(RawImage), findsNothing);
    expect(imageCache.liveImageCount, 0);
    expect(imageCache.pendingImageCount, 0);
  });
}

// 封面来源是假的，解码却在引擎中真实异步进行：让出真实时间，直到没有加载中的
// 封面，最多等 5 秒。
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

// 地址含 missing 的封面读不到。
final class _CoverServer {
  _CoverServer(this._png);

  final Uint8List _png;
  final requests = <String>[];

  Future<void>? responding;

  ImageProvider cover(String url) => _ServedCover(url, this);

  Future<Uint8List> _fetch(String url) async {
    requests.add(url);
    await responding;
    if (url.contains('missing')) throw StateError('cover not found');
    return _png;
  }
}

final class _ServedCover extends ImageProvider<_ServedCover> {
  const _ServedCover(this.url, this.server);

  final String url;
  final _CoverServer server;

  @override
  Future<_ServedCover> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ServedCover key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await server._fetch(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _ServedCover && other.url == url && other.server == server;

  @override
  int get hashCode => Object.hash(url, server);
}
