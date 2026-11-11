import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/features/playlists/application/playlist_io.dart';
import 'package:file_picker/file_picker.dart';

const unreadableFileText = '没能读取这个文件。';

// 1000 首、每个字段都填满时约 10 MB；上限只防止选中大文件时内存溢出。
const _maxBytes = 16 * 1024 * 1024;

typedef PickedFile = ({
  Future<int?> Function() length,
  Future<Uint8List> Function() read,
});

/// 与浏览器的 `File.text()` 一致：容错，只去掉开头的一个 BOM。Dart 的 UTF-8
/// 解码已经去掉了这一个，再去一次就会多去掉文件内容里的。
String decodePlaylistFileBytes(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

final class FilePickerPlaylistFileSource implements PlaylistFileSource {
  const FilePickerPlaylistFileSource({
    this._pick = _pickJson,
    this._clear = FilePicker.clearTemporaryFiles,
  });

  final Future<PickedFile?> Function() _pick;
  final Future<void> Function() _clear;

  @override
  Future<PlaylistFileResult?> pick() async {
    try {
      final file = await _pick();
      if (file == null) return null;
      try {
        final length = await file.length();
        // 读不出大小时不整个读进内存。
        if (length == null) {
          return const PlaylistFileProblem(unreadableFileText);
        }
        if (length > _maxBytes) {
          return const PlaylistFileProblem(notPlaylistFileText);
        }
        final bytes = await file.read();
        // 文件可能有几 MB，解码和解析不放在界面所在的 isolate。
        return await Isolate.run(
          () => parsePlaylistFile(decodePlaylistFileBytes(bytes)),
        );
      } finally {
        await _clearPicked();
      }
    } on Object catch (error) {
      AppLog.warn(
        'playlists',
        'playlist file not read',
        type: '${error.runtimeType}',
      );
      return const PlaylistFileProblem(unreadableFileText);
    }
  }

  // 选择器可能把选中的文件复制到应用的临时目录；读完就删，不留下用户的歌单。
  // 删不掉不影响这次读到的结果。
  Future<void> _clearPicked() async {
    try {
      await _clear();
    } on Object catch (error) {
      AppLog.warn(
        'playlists',
        'picked file copy not removed',
        type: '${error.runtimeType}',
      );
    }
  }
}

// Android 把扩展名换成 MIME 类型交给系统选择器，不保证过滤，所以内容总要校验。
Future<PickedFile?> _pickJson() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (file == null) return null;
  return (length: file.length, read: file.readAsBytes);
}
