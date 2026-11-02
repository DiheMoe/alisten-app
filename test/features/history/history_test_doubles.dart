import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/features/history/index.dart';

final class FakeHistoryExporter implements HistoryExporter {
  List<PlayRecord> records = [];
  DateTime? exportedAt;

  @override
  Future<void> export(List<PlayRecord> records, DateTime exportedAtUtc) async {
    this.records = records;
    exportedAt = exportedAtUtc;
  }
}
