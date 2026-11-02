import 'dart:async';
import 'dart:io';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/settings/application/cover_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/cache/cover_cache_test_doubles.dart';

void main() {
  late FakeCoverCache cache;
  late int measured;

  ProviderContainer open() {
    final container = ProviderContainer(
      overrides: [
        coverCacheSizeProvider.overrideWithValue(() {
          measured++;
          return cache.size();
        }),
        clearCoverCacheProvider.overrideWithValue(cache.clear),
      ],
    );
    addTearDown(container.dispose);
    // 设置页显示期间会一直监听。
    container.listen(coverCacheControllerProvider, (_, _) {});
    return container;
  }

  setUp(() {
    cache = FakeCoverCache(bytes: 2048);
    measured = 0;
  });

  test('the size of the cover cache is measured once it is shown', () async {
    final container = open();

    expect(container.read(coverCacheControllerProvider).isLoading, isTrue);
    expect(await container.read(coverCacheControllerProvider.future), 2048);
    expect(measured, 1);
  });

  test('clearing empties the cover cache and measures it again', () async {
    final container = open();
    await container.read(coverCacheControllerProvider.future);

    final cleared = await container
        .read(coverCacheControllerProvider.notifier)
        .clear();

    expect(cleared, isTrue);
    expect(cache.clears, 1);
    expect(await container.read(coverCacheControllerProvider.future), 0);
    expect(measured, 2);
  });

  test('a cover cache that cannot be cleared says so and shows what it still '
      'takes', () async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    cache.clearError = const FileSystemException('busy');
    final container = open();
    await container.read(coverCacheControllerProvider.future);

    final cleared = await container
        .read(coverCacheControllerProvider.notifier)
        .clear();

    expect(cleared, isFalse);
    expect(await container.read(coverCacheControllerProvider.future), 2048);
    expect(records.map((record) => record.$1), contains('alisten.settings'));
  });

  test('a size that cannot be measured is an error', () async {
    cache.measuring = Completer<void>()
      ..completeError(const FileSystemException('unreadable'));
    final container = open();

    await expectLater(
      container.read(coverCacheControllerProvider.future),
      throwsA(isA<FileSystemException>()),
    );
    expect(container.read(coverCacheControllerProvider).hasError, isTrue);
  });
}
