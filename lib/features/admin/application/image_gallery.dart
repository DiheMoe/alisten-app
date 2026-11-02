import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final class GalleryAccessDenied implements Exception {
  const GalleryAccessDenied();
}

/// 没有相册权限、请求后仍被拒绝时抛 [GalleryAccessDenied]。[name] 不带扩展名。
abstract interface class ImageGallery {
  Future<void> saveImage(Uint8List bytes, String name);
}

final imageGalleryProvider = Provider<ImageGallery>((ref) {
  throw UnimplementedError('imageGallery 未注入');
});
