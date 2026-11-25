import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/playlist_io.dart';
import 'package:file_picker/file_picker.dart';

/// 桌面系统没有分享面板，导出就是让用户选个位置存下来。
final class SavePlaylistExporter implements PlaylistExporter {
  const SavePlaylistExporter({this._save = _saveFile});

  final Future<void> Function(String fileName, Uint8List bytes) _save;

  @override
  Future<void> export(
    String name,
    List<TrackSummary> items,
    int exportedAtMs, {
    Rect? origin,
  }) => _save(
    playlistExportFileName(name),
    utf8.encode(playlistExportJson(name, items, exportedAtMs)),
  );
}

// 用户在保存对话框里取消不是失败。
Future<void> _saveFile(String fileName, Uint8List bytes) async {
  await FilePicker.saveFile(fileName: fileName, bytes: bytes);
}
