import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/core/cache/cover_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

@immutable
final class CachedCoverImage extends ImageProvider<CachedCoverImage> {
  const CachedCoverImage(this.url, this.cache);

  final String url;
  final CoverCache cache;

  @override
  Future<CachedCoverImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedCoverImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1,
      debugLabel: 'cover',
    );
  }

  Future<ui.Codec> _load(
    CachedCoverImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await cache.load(url);
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      } on Object {
        // 存下的不是图片（如强制门户返回的网页）：删除，下次重新下载。
        await cache.discard(url);
        rethrow;
      }
    } on Object {
      // 与 NetworkImage 一致，失败的封面不留在内存图片缓存中。此时缓存可能尚未
      // 登记这个键，因此在微任务中移除。
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is CachedCoverImage &&
        other.url == url &&
        identical(other.cache, cache);
  }

  @override
  int get hashCode => Object.hash(url, identityHashCode(cache));

  // 不含地址：图片加载失败时 Flutter 会打印它。
  @override
  String toString() => '${objectRuntimeType(this, 'CachedCoverImage')}()';
}
