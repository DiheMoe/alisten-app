import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final avatarCacheProvider = Provider<AvatarCache>((ref) {
  throw UnimplementedError('avatarCache 未注入');
});

abstract interface class AvatarCache {
  /// [url] 是 Gravatar 的头像地址。没设头像时为 null；
  /// 没有存下且没有站点连得上时抛出 `AvatarUnavailable`。
  Future<Uint8List?> load(String url);

  /// 删除存下的头像，例如它不是图片时。
  Future<void> discard(String url);

  /// 占用的字节数。
  Future<int> size();

  Future<void> clear();
}
