import 'dart:convert';
import 'dart:io';

import 'package:alisten/features/history/data/share_history_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/history/records_test.dart' show playRecord;

void main() {
  final exportedAt = DateTime.utc(2026, 11, 1, 9, 5, 7);

  test('the export names the second it was made in UTC', () {
    final decoded =
        jsonDecode(historyExportJson([playRecord('track')], exportedAt))!
            as Map<String, Object?>;

    expect(decoded['exportedAt'], endsWith('Z'));
    expect(DateTime.parse(decoded['exportedAt']! as String), exportedAt);
    expect(decoded['history'], hasLength(1));
  });

  test('every exported record names the server it was played on', () {
    final decoded =
        jsonDecode(
              historyExportJson([
                playRecord('a'),
                playRecord('b', serverOrigin: 'https://example.com:8443'),
              ], exportedAt),
            )!
            as Map<String, Object?>;

    expect(
      (decoded['history']! as List<Object?>).map(
        (record) => (record! as Map<String, Object?>)['serverOrigin'],
      ),
      ['https://livehouse.dihe.moe', 'https://example.com:8443'],
    );
  });

  test('the file name includes the time, so exports do not overwrite '
      'each other', () {
    expect(
      historyExportFileName(exportedAt),
      'alisten-history-20261101-090507Z.json',
    );
    expect(
      historyExportFileName(exportedAt.add(const Duration(seconds: 1))),
      isNot(historyExportFileName(exportedAt)),
    );
  });

  group('export file', () {
    late Directory temporary;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('alisten_export_');
      addTearDown(() => temporary.delete(recursive: true));
    });

    ShareHistoryExporter exporter(Future<void> Function(String path) share) {
      return ShareHistoryExporter(
        temporaryDirectory: () async => temporary,
        share: share,
      );
    }

    test('is shared from the temporary directory and removed once the share '
        'sheet returns', () async {
      String? sharedPath;
      String? sharedContent;

      await exporter((path) async {
        sharedPath = path;
        sharedContent = await File(path).readAsString();
      }).export([playRecord('track')], exportedAt);

      expect(
        sharedPath,
        '${temporary.path}/${historyExportFileName(exportedAt)}',
      );
      expect(
        sharedContent,
        historyExportJson([playRecord('track')], exportedAt),
      );
      expect(File(sharedPath!).existsSync(), isFalse);
      expect(temporary.listSync(), isEmpty);
    });

    test(
      'is removed when sharing fails, and the failure still surfaces',
      () async {
        late String sharedPath;

        await expectLater(
          exporter((path) async {
            sharedPath = path;
            throw const FileSystemException('no share target');
          }).export([playRecord('track')], exportedAt),
          throwsA(isA<FileSystemException>()),
        );

        expect(File(sharedPath).existsSync(), isFalse);
      },
    );
  });
}
