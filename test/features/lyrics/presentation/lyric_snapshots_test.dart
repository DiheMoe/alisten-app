import 'dart:ui' as ui;

import 'package:alisten/features/lyrics/presentation/lyric_snapshots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LyricSnapshot _snapshot() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  return LyricSnapshot(image, Rect.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the least recently used image goes first and is released', () {
    final cache = LyricSnapshotCache(capacity: 2);
    addTearDown(cache.clear);
    final images = [for (var i = 0; i < 3; i++) _snapshot()];

    cache.store((0, 1), images[0]);
    cache.store((1, 1), images[1]);
    expect(cache[(0, 1)], same(images[0]));
    cache.store((2, 1), images[2]);

    expect(cache[(1, 1)], isNull);
    expect(images[1].image.debugDisposed, isTrue);
    expect(cache[(0, 1)], same(images[0]));
  });

  test('storing over a key releases the old image', () {
    final cache = LyricSnapshotCache();
    addTearDown(cache.clear);
    final old = _snapshot();
    final next = _snapshot();

    cache.store((0, 1), old);
    cache.store((0, 1), next);

    expect(old.image.debugDisposed, isTrue);
    expect(cache[(0, 1)], same(next));
  });

  test('a smaller capacity releases the oldest at once', () {
    final cache = LyricSnapshotCache();
    addTearDown(cache.clear);
    final old = _snapshot();
    final kept = _snapshot();
    cache
      ..store((0, 1), old)
      ..store((1, 1), kept)
      ..capacity = 1;

    expect(old.image.debugDisposed, isTrue);
    expect(cache[(1, 1)], same(kept));
  });

  test('clear releases everything', () {
    final cache = LyricSnapshotCache();
    final image = _snapshot();
    cache.store((0, 1), image);

    cache.clear();

    expect(image.image.debugDisposed, isTrue);
    expect(cache[(0, 1)], isNull);
  });
}
