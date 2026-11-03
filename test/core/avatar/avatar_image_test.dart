import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alisten/core/avatar/avatar_image.dart';
import 'package:alisten/core/avatar/avatar_loader.dart';
import 'package:alisten/core/avatar/disk_avatar_cache.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/avatar_images.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'avatar_test_doubles.dart';

void main() {
  late Directory root;

  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  Future<void> useTemporaryDirectory(WidgetTester tester) async {
    root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('alisten-avatars-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
  }

  Widget avatar(AvatarServer server) {
    final cache = DiskAvatarCache(
      AvatarLoader(Dio()..httpClientAdapter = server),
      directory: () async => root,
    );
    return MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: AvatarImages(
        resolve: (url) => AvatarImage(url, cache),
        child: MemberAvatar(name: '小明', imageUrl: avatarUrl()),
      ),
    );
  }

  testWidgets('an avatar Gravatar cannot serve is shown from a mirror and '
      'stored on this device', (tester) async {
    await useTemporaryDirectory(tester);
    final server = AvatarServer()
      ..avatars[weavatar] = (await tester.runAsync(_png))!;

    await tester.pumpWidget(avatar(server));
    await _finishLoading(tester);

    expect(server.requests, [gravatar, weavatar, cravatar]);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(await tester.runAsync(() => root.list().toList()), hasLength(1));
  });

  testWidgets('a member without an avatar shows the initial', (tester) async {
    await useTemporaryDirectory(tester);
    final server = AvatarServer()..missing.add(gravatar);

    await tester.pumpWidget(avatar(server));
    await _finishLoading(tester);

    expect(server.requests, [gravatar]);
    expect(find.byType(RawImage), findsNothing);
    expect(find.text('小'), findsOneWidget);
  });

  testWidgets('an avatar no site can serve shows the initial', (tester) async {
    await useTemporaryDirectory(tester);

    await tester.pumpWidget(avatar(AvatarServer()));
    await _finishLoading(tester);

    expect(find.byType(RawImage), findsNothing);
    expect(find.text('小'), findsOneWidget);
  });

  testWidgets('a downloaded avatar that is not an image shows the initial and '
      'is not kept on this device', (tester) async {
    await useTemporaryDirectory(tester);
    final server = AvatarServer()..avatars[gravatar] = '<html>'.codeUnits;

    await tester.pumpWidget(avatar(server));
    await _finishLoading(tester);

    expect(find.text('小'), findsOneWidget);
    expect(await tester.runAsync(() => root.list().toList()), isEmpty);
  });

  test('the address of an avatar stays out of its description', () {
    final image = AvatarImage(avatarUrl(), FakeAvatarCache());

    expect('$image', isNot(contains('abc123')));
  });
}

// 让出真实时间给解码，同时推进假时间给 dio，直到 [done]，最多等 5 秒。
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  const step = Duration(milliseconds: 5);
  final waited = Stopwatch()..start();
  while (!done() && waited.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
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
