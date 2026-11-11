import 'dart:convert';
import 'dart:io';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 与 Web 一样按本地日期命名。同一天再导出会覆盖临时文件，但每次分享完都会
/// 删除。
String historyExportFileName(DateTime exportedAt) {
  final day = exportedAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final year = day.year.toString().padLeft(4, '0');
  return 'alisten-history-$year-${two(day.month)}-${two(day.day)}.json';
}

/// 每一项都是 `MyListen` 的线上格式，与 Web 导出的条目同形。
String historyExportJson(List<Listen> listens, DateTime exportedAt) {
  return const JsonEncoder.withIndent('  ').convert({
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'history': [
      for (final listen in listens) toProtocolListen(listen).toJson(),
    ],
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
  Future<void> export(List<Listen> listens, DateTime exportedAt) async {
    final directory = await _temporaryDirectory();
    final file = File('${directory.path}/${historyExportFileName(exportedAt)}');
    await file.writeAsString(historyExportJson(listens, exportedAt));
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
