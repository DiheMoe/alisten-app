import 'dart:ui' show Rect;

import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class PlaylistFileSource {
  /// 选出一个文件并解析；用户取消时返回 null。不抛出：读取失败也作为
  /// [PlaylistFileProblem] 返回。
  Future<PlaylistFileResult?> pick();
}

abstract interface class PlaylistExporter {
  /// [origin] 是触发导出的控件在屏幕上的位置，iPad 上的分享弹窗指向它。
  Future<void> export(
    String name,
    List<TrackSummary> items,
    int exportedAtMs, {
    Rect? origin,
  });
}

final playlistFileSourceProvider = Provider<PlaylistFileSource>((ref) {
  throw UnimplementedError('playlistFileSource 未注入');
});

final playlistExporterProvider = Provider<PlaylistExporter>((ref) {
  throw UnimplementedError('playlistExporter 未注入');
});

final playlistsNowProvider = Provider<int Function()>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch;
});
