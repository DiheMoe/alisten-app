import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/core/avatar/avatar_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

@immutable
final class AvatarImage extends ImageProvider<AvatarImage> {
  const AvatarImage(this.url, this.loader);

  final String url;
  final AvatarLoader loader;

  @override
  Future<AvatarImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(AvatarImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1,
      debugLabel: 'avatar',
    );
  }

  // 没设头像也按加载失败处理，界面显示首字。
  Future<ui.Codec> _load(AvatarImage key, ImageDecoderCallback decode) async {
    try {
      final bytes = await loader.load(url);
      if (bytes == null) throw const AvatarUnavailable();
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } on Object {
      // 与 NetworkImage 一致，失败的头像不留在内存图片缓存中。此时缓存可能尚未
      // 登记这个键，因此在微任务中移除。
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is AvatarImage &&
        other.url == url &&
        identical(other.loader, loader);
  }

  @override
  int get hashCode => Object.hash(url, identityHashCode(loader));

  // 不含地址：图片加载失败时 Flutter 会打印它。
  @override
  String toString() => '${objectRuntimeType(this, 'AvatarImage')}()';
}
