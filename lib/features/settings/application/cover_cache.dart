import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 返回封面缓存占用的字节数。
final coverCacheSizeProvider = Provider<Future<int> Function()>((ref) {
  throw UnimplementedError('coverCacheSize 未注入');
});

final clearCoverCacheProvider = Provider<Future<void> Function()>((ref) {
  throw UnimplementedError('clearCoverCache 未注入');
});

final coverCacheControllerProvider =
    AsyncNotifierProvider.autoDispose<CoverCacheController, int>(
      CoverCacheController.new,
      retry: (_, _) => null,
    );

/// 只清除磁盘文件，不清内存缓存，已显示的封面不会闪烁。
final class CoverCacheController extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.read(coverCacheSizeProvider)();

  Future<bool> clear() async {
    var cleared = true;
    try {
      await ref.read(clearCoverCacheProvider)();
    } on Object catch (error) {
      AppLog.warn(
        'settings',
        'cover cache not cleared',
        type: '${error.runtimeType}',
      );
      cleared = false;
    }
    if (ref.mounted) ref.invalidateSelf();
    return cleared;
  }
}
