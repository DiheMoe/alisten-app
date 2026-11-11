import 'dart:io';
import 'dart:ui' show Rect;

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/playlist_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final class SharePlaylistExporter implements PlaylistExporter {
  const SharePlaylistExporter({
    this._temporaryDirectory = getTemporaryDirectory,
    Future<void> Function(ShareParams params) share = _share,
  }) : _shareFile = share;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(ShareParams params) _shareFile;

  @override
  Future<void> export(
    String name,
    List<TrackSummary> items,
    int exportedAtMs, {
    Rect? origin,
  }) async {
    final directory = await _temporaryDirectory();
    final file = File('${directory.path}/${playlistExportFileName(name)}');
    try {
      // 写到一半失败时也要删掉不完整的文件。
      await file.writeAsString(playlistExportJson(name, items, exportedAtMs));
      await _shareFile(
        ShareParams(
          files: [XFile(file.path)],
          subject: name,
          text: 'Alisten 歌单 JSON 导出',
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      await _remove(file);
    }
  }
}

// 用户在系统分享面板里取消不是失败，share_plus 照常返回。
Future<void> _share(ShareParams params) async {
  await SharePlus.instance.share(params);
}

Future<void> _remove(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    AppLog.warn('playlists', 'export file not removed');
  }
}
