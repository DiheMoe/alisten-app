import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 返回封面和头像缓存共占用的字节数。
final imageCacheSizeProvider = Provider<Future<int> Function()>((ref) {
  throw UnimplementedError('imageCacheSize 未注入');
});

final clearImageCacheProvider = Provider<Future<void> Function()>((ref) {
  throw UnimplementedError('clearImageCache 未注入');
});

final imageCacheControllerProvider =
    AsyncNotifierProvider.autoDispose<ImageCacheController, int>(
      ImageCacheController.new,
      retry: (_, _) => null,
    );

/// 只清除磁盘文件，不清内存缓存，已显示的图片不会闪烁。
final class ImageCacheController extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.read(imageCacheSizeProvider)();

  Future<bool> clear() async {
    var cleared = true;
    try {
      await ref.read(clearImageCacheProvider)();
    } on Object catch (error) {
      AppLog.warn(
        'settings',
        'image cache not cleared',
        type: '${error.runtimeType}',
      );
      cleared = false;
    }
    if (ref.mounted) ref.invalidateSelf();
    return cleared;
  }
}
