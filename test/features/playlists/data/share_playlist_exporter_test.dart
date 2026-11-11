import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/data/share_playlist_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

const _song = TrackSummary(
  track: Track(source: TrackSource.netease, id: '1'),
  meta: TrackMeta(
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    coverUrl: '',
    pageUrl: '',
    durationMs: 269000,
  ),
);

/// 写到一半就失败，留下不完整的文件。
final class _PartialWrite extends Fake implements File {
  _PartialWrite(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await _file.writeAsString(contents.substring(0, 10));
    throw const FileSystemException('disk full');
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);
}

void main() {
  late Directory directory;
  const exportedAt = 1762822923004;
  const origin = Rect.fromLTWH(1, 2, 3, 4);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('alisten-playlist-');
  });

  tearDown(() => directory.delete(recursive: true));

  test('writes the file under the playlist name, shares it from the given '
      'place, then removes it', () async {
    ShareParams? shared;
    String? content;
    final exporter = SharePlaylistExporter(
      temporaryDirectory: () async => directory,
      share: (params) async {
        shared = params;
        content = await File(params.files!.single.path).readAsString();
      },
    );

    await exporter.export('夜跑/晨跑', [_song], exportedAt, origin: origin);

    expect(shared!.files!.single.path, '${directory.path}/夜跑_晨跑.json');
    expect(shared!.subject, '夜跑/晨跑');
    expect(shared!.text, 'Alisten 歌单 JSON 导出');
    expect(shared!.sharePositionOrigin, origin);
    expect(content, playlistExportJson('夜跑/晨跑', [_song], exportedAt));
    expect(directory.listSync(), isEmpty);
  });

  test('a share that fails still removes the file, and fails', () async {
    final exporter = SharePlaylistExporter(
      temporaryDirectory: () async => directory,
      share: (_) async => throw const FileSystemException('no share'),
    );

    await expectLater(
      exporter.export('夜跑', [_song], exportedAt),
      throwsA(isA<FileSystemException>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('a file only partly written is removed, and nothing is '
      'shared', () async {
    var shares = 0;
    final exporter = SharePlaylistExporter(
      temporaryDirectory: () async => directory,
      share: (_) async => shares++,
    );
    // 在替换 File 之前建好真实的文件对象，替身才能把写入和删除交给它。
    final file = File('${directory.path}/夜跑.json');

    await expectLater(
      IOOverrides.runZoned(
        () => exporter.export('夜跑', [_song], exportedAt),
        createFile: (_) => _PartialWrite(file),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(shares, 0);
    expect(directory.listSync(), isEmpty);
  });
}
