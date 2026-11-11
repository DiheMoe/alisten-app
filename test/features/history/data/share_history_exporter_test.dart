import 'dart:convert';
import 'dart:io';

import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/data/share_history_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../history_test_doubles.dart';

void main() {
  final exportedAt = DateTime.utc(2026, 11, 1, 9, 5, 7);

  test('the file is named after the local date of the export, like the '
      'web', () {
    final local = exportedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');

    expect(
      historyExportFileName(exportedAt),
      'alisten-history-${local.year}-${two(local.month)}-${two(local.day)}'
      '.json',
    );
  });

  test('the export holds the time in UTC and every listen the way the '
      'server sends it', () {
    final decoded =
        jsonDecode(
              historyExportJson([
                heard(
                  '晴天',
                  at: 1782864000000,
                  source: TrackSource.bilibili,
                  coverUrl: 'https://i0.hdslb.com/cover.jpg',
                ),
              ], exportedAt),
            )!
            as Map<String, Object?>;

    expect(decoded.keys, unorderedEquals(['exportedAt', 'history']));
    expect(decoded['exportedAt'], '2026-11-01T09:05:07.000Z');
    expect(decoded['history'], [
      {
        'track': {'source': 'bilibili', 'id': '晴天'},
        'meta': {
          'title': '晴天',
          'artist': '歌手',
          'album': '专辑',
          'coverUrl': 'https://i0.hdslb.com/cover.jpg',
          'pageUrl': '',
          'durationMs': 180000,
        },
        'heardAtMs': 1782864000000,
      },
    ]);
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
      }).export([heard('track')], exportedAt);

      expect(
        sharedPath,
        '${temporary.path}/${historyExportFileName(exportedAt)}',
      );
      expect(sharedContent, historyExportJson([heard('track')], exportedAt));
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
          }).export([heard('track')], exportedAt),
          throwsA(isA<FileSystemException>()),
        );

        expect(File(sharedPath).existsSync(), isFalse);
      },
    );
  });
}
