import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/avatar/avatar_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

@immutable
final class AvatarImage extends ImageProvider<AvatarImage> {
  const AvatarImage(this.url, this.cache);

  final String url;
  final AvatarCache cache;

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
      final bytes = await cache.load(url);
      if (bytes == null) throw const AvatarUnavailable();
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      } on Object {
        // 存下的不是图片（如强制门户返回的网页）：删除，下次重新下载。
        await cache.discard(url);
        rethrow;
      }
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
        identical(other.cache, cache);
  }

  @override
  int get hashCode => Object.hash(url, identityHashCode(cache));

  // 不含地址：图片加载失败时 Flutter 会打印它。
  @override
  String toString() => '${objectRuntimeType(this, 'AvatarImage')}()';
}
