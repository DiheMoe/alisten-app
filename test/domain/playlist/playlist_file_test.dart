import 'dart:convert';

import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_test/flutter_test.dart';

String _file(
  Object? tracks, {
  Object? name = '旧歌单',
  Object? format = 'alisten.playlist',
}) {
  return jsonEncode({'format': format, 'name': name, 'tracks': tracks});
}

Map<String, Object?> _entry(String id, {Object? source = 'netease'}) {
  return {'source': source, 'id': id, 'title': '晴天'};
}

PlaylistFile _parsed(String content) =>
    parsePlaylistFile(content) as PlaylistFile;

String? _problem(String content) => switch (parsePlaylistFile(content)) {
  PlaylistFileProblem(:final message) => message,
  PlaylistFile() => null,
};

const _song = TrackSummary(
  track: Track(source: TrackSource.qq, id: '001'),
  meta: TrackMeta(
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    coverUrl: 'https://y.gtimg.cn/a.jpg',
    pageUrl: 'https://y.qq.com/n/ryqq/songDetail/001',
    durationMs: 269000,
  ),
);

void main() {
  group('parsePlaylistFile', () {
    test('what is not an exported playlist says so', () {
      for (final content in [
        '{',
        '[]',
        '"alisten.playlist"',
        jsonEncode({'name': '缺少格式', 'tracks': <Object?>[]}),
        _file(<Object?>[], format: 'other'),
        _file('not a list'),
        _file(null),
      ]) {
        expect(_problem(content), notPlaylistFileText, reason: content);
      }
      expect(notPlaylistFileText, '这个文件不是导出的歌单。');
    });

    test('a file without songs says so', () {
      expect(_problem(_file(<Object?>[])), '这个歌单文件里没有歌。');
    });

    test('the first song without a source or an id is named, counted '
        'from 1', () {
      expect(
        _problem(_file([_entry('1'), _entry('2', source: 'spotify')])),
        '文件里的第 2 首歌缺少音源或 ID，没有导入。',
      );
      expect(_problem(_file(['x'])), badTrackText(1));
      expect(_problem(_file([_entry('')])), badTrackText(1));
      expect(
        _problem(
          _file([
            {'source': 'qq', 'id': 5},
          ]),
        ),
        badTrackText(1),
      );
      expect(
        _problem(
          _file([
            {'id': '1'},
          ]),
        ),
        badTrackText(1),
      );
    });

    test('every source the server knows is accepted', () {
      final file = _parsed(
        _file([
          for (final source in ['netease', 'qq', 'bilibili', 'link'])
            _entry('1', source: source),
        ]),
      );

      expect([
        for (final track in file.tracks) track.track.source,
      ], TrackSource.values);
    });

    test('metadata of the wrong type is left out or emptied', () {
      final file = _parsed(
        _file([
          {
            'source': 'qq',
            'id': '1',
            'title': 5,
            'artist': 5,
            'album': null,
            'coverUrl': 'https://example.com/a.jpg',
            'pageUrl': 'https://example.com/a',
            'durationMs': '3',
          },
        ]),
      );
      final track = file.tracks.single;

      expect(track.track.id, '1');
      expect(track.title, '');
      expect(track.artist, isNull);
      expect(track.album, isNull);
      expect(track.coverUrl, 'https://example.com/a.jpg');
      expect(track.pageUrl, 'https://example.com/a');
      expect(track.durationMs, 0);
    });

    test('a duration counts only as a whole number from 0 to a day', () {
      int duration(Object? value) => _parsed(
        _file([
          {'source': 'qq', 'id': '1', 'title': 'a', 'durationMs': value},
        ]),
      ).tracks.single.durationMs;

      expect(duration(180000), 180000);
      expect(duration(1.0), 1);
      expect(duration(86400000), 86400000);
      expect(duration(86400001), 0);
      expect(duration(-1), 0);
      expect(duration(2.5), 0);
      expect(duration(null), 0);
    });

    test('a duration too large for a number is none', () {
      final file = _parsed(
        '{"format":"alisten.playlist","name":"a","tracks":'
        '[{"source":"qq","id":"1","title":"a","durationMs":1e400}]}',
      );

      expect(file.tracks.single.durationMs, 0);
    });

    test('a name that is not text is empty', () {
      expect(_parsed(_file([_entry('1')], name: 5)).name, '');
      expect(_parsed(_file([_entry('1')], name: '夜跑')).name, '夜跑');
    });

    test('only the first 1000 songs are taken, and the rest are not '
        'checked', () {
      final full = _parsed(
        _file([for (var i = 0; i < 1000; i++) _entry('$i')]),
      );
      expect(full.tracks, hasLength(1000));
      expect(full.truncated, isFalse);

      final over = _parsed(
        _file([
          for (var i = 0; i < 1000; i++) _entry('$i'),
          _entry('', source: 'spotify'),
        ]),
      );
      expect(over.tracks, hasLength(1000));
      expect(over.truncated, isTrue);

      final notObject = _parsed(
        _file([for (var i = 0; i < 1000; i++) _entry('$i'), 'x']),
      );
      expect(notObject.tracks, hasLength(1000));
      expect(notObject.truncated, isTrue);
    });
  });

  group('playlistExportJson', () {
    final exportedAt = DateTime.utc(
      2026,
      11,
      11,
      1,
      2,
      3,
      4,
    ).millisecondsSinceEpoch;

    test('writes the keys and values of Web, indented by two spaces', () {
      expect(playlistExportJson('夜跑', [_song], exportedAt), '''
{
  "format": "alisten.playlist",
  "name": "夜跑",
  "exportedAt": "2026-11-11T01:02:03.004Z",
  "tracks": [
    {
      "source": "qq",
      "id": "001",
      "title": "晴天",
      "artist": "周杰伦",
      "album": "叶惠美",
      "durationMs": 269000,
      "coverUrl": "https://y.gtimg.cn/a.jpg",
      "pageUrl": "https://y.qq.com/n/ryqq/songDetail/001"
    }
  ]
}''');
    });

    test('an empty playlist has an empty list of songs', () {
      expect(
        playlistExportJson('夜跑', const [], exportedAt),
        contains('"tracks": []'),
      );
    });

    test('a title outside the basic plane reads back the same', () {
      const emoji = TrackSummary(
        track: Track(source: TrackSource.qq, id: '002'),
        meta: TrackMeta(
          title: '😀🎵',
          artist: '',
          album: '',
          coverUrl: '',
          pageUrl: '',
          durationMs: 0,
        ),
      );

      final file = _parsed(playlistExportJson('😀🎵', [emoji], exportedAt));

      expect(file.name, '😀🎵');
      expect(file.tracks.single.title, '😀🎵');
    });

    test('reads back as the same songs', () {
      final file = _parsed(playlistExportJson('夜跑', [_song], exportedAt));
      final track = file.tracks.single;

      expect(file.name, '夜跑');
      expect(file.truncated, isFalse);
      expect(track.track.source, TrackSource.qq);
      expect(track.track.id, '001');
      expect(track.title, '晴天');
      expect(track.artist, '周杰伦');
      expect(track.album, '叶惠美');
      expect(track.durationMs, 269000);
      expect(track.coverUrl, 'https://y.gtimg.cn/a.jpg');
      expect(track.pageUrl, 'https://y.qq.com/n/ryqq/songDetail/001');
    });
  });

  test('a file name replaces what file systems refuse', () {
    for (final unsafe in [
      r'\',
      '/',
      ':',
      '*',
      '?',
      '"',
      '<',
      '>',
      '|',
      '\u0000',
      '\u001f',
      '\u007f',
      '\u0080',
      '\u009f',
    ]) {
      expect(playlistExportFileName('a${unsafe}b'), 'a_b.json', reason: unsafe);
    }
    expect(playlistExportFileName('夜跑 2026'), '夜跑 2026.json');
    expect(playlistExportFileName(''), '.json');
  });
}
