import 'dart:convert';
import 'dart:io';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 导出时间精确到秒，同一天的多次导出不会互相覆盖；与文件内的 `exportedAt`
/// 一样用 UTC。
String historyExportFileName(DateTime exportedAtUtc) {
  final time = exportedAtUtc.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${time.year.toString().padLeft(4, '0')}'
      '${two(time.month)}${two(time.day)}';
  final clock = '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  return 'alisten-history-$date-${clock}Z.json';
}

String historyExportJson(List<PlayRecord> records, DateTime exportedAtUtc) {
  return const JsonEncoder.withIndent('  ').convert({
    'exportedAt': exportedAtUtc.toUtc().toIso8601String(),
    'history': records.map((record) => record.toJson()).toList(),
  });
}

final class ShareHistoryExporter implements HistoryExporter {
  const ShareHistoryExporter({
    this._temporaryDirectory = getTemporaryDirectory,
    this._share = _shareFile,
  });

  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(String path) _share;

  @override
  Future<void> export(List<PlayRecord> records, DateTime exportedAtUtc) async {
    final directory = await _temporaryDirectory();
    final file = File(
      '${directory.path}/${historyExportFileName(exportedAtUtc)}',
    );
    await file.writeAsString(historyExportJson(records, exportedAtUtc));
    try {
      await _share(file.path);
    } finally {
      await _remove(file);
    }
  }
}

Future<void> _shareFile(String path) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)],
      text: 'Alisten 播放历史 JSON 导出',
      subject: 'Alisten 播放历史',
    ),
  );
}

Future<void> _remove(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    AppLog.warn('history', 'export file not removed');
  }
}
