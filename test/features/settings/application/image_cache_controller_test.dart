import 'dart:io';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/settings/application/image_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/cache/cover_cache_test_doubles.dart';

void main() {
  late FakeCoverCache cache;
  late int measured;

  ProviderContainer open() {
    final container = ProviderContainer(
      overrides: [
        imageCacheSizeProvider.overrideWithValue(() {
          measured++;
          return cache.size();
        }),
        clearImageCacheProvider.overrideWithValue(cache.clear),
      ],
    );
    addTearDown(container.dispose);
    // 设置页显示期间会一直监听。
    container.listen(imageCacheControllerProvider, (_, _) {});
    return container;
  }

  setUp(() {
    cache = FakeCoverCache(bytes: 2048);
    measured = 0;
  });

  test('the size of the image cache is measured once it is shown', () async {
    final container = open();

    expect(container.read(imageCacheControllerProvider).isLoading, isTrue);
    expect(await container.read(imageCacheControllerProvider.future), 2048);
    expect(measured, 1);
  });

  test('an image cache that cannot be cleared says so and shows what it '
      'still takes', () async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    cache.clearError = const FileSystemException('busy');
    final container = open();
    await container.read(imageCacheControllerProvider.future);

    final cleared = await container
        .read(imageCacheControllerProvider.notifier)
        .clear();

    expect(cleared, isFalse);
    expect(await container.read(imageCacheControllerProvider.future), 2048);
    expect(records.map((record) => record.$1), contains('alisten.settings'));
  });
}
