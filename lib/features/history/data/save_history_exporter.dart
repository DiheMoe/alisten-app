import 'dart:convert';
import 'dart:typed_data';

import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:alisten/features/history/data/share_history_exporter.dart';
import 'package:file_picker/file_picker.dart';

/// 桌面系统没有分享面板，导出就是让用户选个位置存下来。
final class SaveHistoryExporter implements HistoryExporter {
  const SaveHistoryExporter({this._save = _saveFile});

  final Future<void> Function(String fileName, Uint8List bytes) _save;

  @override
  Future<void> export(List<Listen> listens, DateTime exportedAt) => _save(
    historyExportFileName(exportedAt),
    utf8.encode(historyExportJson(listens, exportedAt)),
  );
}

// 用户在保存对话框里取消不是失败。
Future<void> _saveFile(String fileName, Uint8List bytes) async {
  await FilePicker.saveFile(fileName: fileName, bytes: bytes);
}
