import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final coverCacheProvider = Provider<CoverCache>((ref) {
  throw UnimplementedError('coverCache 未注入');
});

abstract interface class CoverCache {
  /// 下载失败时抛出，不存储任何内容。
  Future<Uint8List> load(String url);

  /// 供只能读文件的系统组件使用。下载失败时抛出；下载成功但未能存储时为 null。
  Future<Uri?> localFile(String url);

  Future<void> discard(String url);

  /// 占用的字节数。
  Future<int> size();

  Future<void> clear();
}
