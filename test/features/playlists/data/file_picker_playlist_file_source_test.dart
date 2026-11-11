import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/features/playlists/data/file_picker_playlist_file_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _valid =
    '{"format":"alisten.playlist","name":"夜跑",'
    '"tracks":[{"source":"qq","id":"1","title":"晴天"}]}';

void main() {
  late int reads;
  late int clears;

  PickedFile file(List<int> bytes, {int? length, Exception? readError}) {
    return (
      length: () async => length ?? bytes.length,
      read: () async {
        reads++;
        if (readError != null) throw readError;
        return Uint8List.fromList(bytes);
      },
    );
  }

  Future<PlaylistFileResult?> pick(PickedFile? picked) {
    return FilePickerPlaylistFileSource(
      pick: () async => picked,
      clear: () async => clears++,
    ).pick();
  }

  setUp(() {
    reads = 0;
    clears = 0;
  });

  test('a cancelled pick is nothing, and says nothing', () async {
    expect(await pick(null), isNull);
    expect(clears, 0);
  });

  test(
    'the copy of a picked file is cleared however reading it ends',
    () async {
      expect(await pick(file(utf8.encode(_valid))), isA<PlaylistFile>());
      expect(clears, 1);

      await pick(file(const [], length: 16 * 1024 * 1024 + 1));
      expect(clears, 2);

      await pick(file(const [1], readError: const FileSystemException('gone')));
      expect(clears, 3);
    },
  );

  test('a copy that cannot be cleared still gives the file', () async {
    final result = await FilePickerPlaylistFileSource(
      pick: () async => file(utf8.encode(_valid)),
      clear: () async => throw const FileSystemException('busy'),
    ).pick();

    expect((result! as PlaylistFile).name, '夜跑');
  });

  test('a file over 16 MB is not read and is not a playlist file', () async {
    final result = await pick(file(const [], length: 16 * 1024 * 1024 + 1));

    expect(result, isA<PlaylistFileProblem>());
    expect((result! as PlaylistFileProblem).message, notPlaylistFileText);
    expect(reads, 0);
  });

  test('a file whose size is unknown is not read', () async {
    final result = await pick((
      length: () async => null,
      read: () async {
        reads++;
        return Uint8List(0);
      },
    ));

    expect((result! as PlaylistFileProblem).message, unreadableFileText);
    expect(reads, 0);
  });

  test('a byte order mark is dropped before parsing', () async {
    final result = await pick(file([0xEF, 0xBB, 0xBF, ...utf8.encode(_valid)]));

    expect(result, isA<PlaylistFile>());
    expect((result! as PlaylistFile).name, '夜跑');
  });

  test('bytes that are not UTF-8 are parsed rather than refused', () async {
    final bytes = [
      ...utf8.encode('{"format":"alisten.playlist","name":"'),
      0xFF,
      ...utf8.encode('","tracks":[{"source":"qq","id":"1","title":"a"}]}'),
    ];

    final result = await pick(file(bytes));

    expect((result! as PlaylistFile).name, '\u{FFFD}');
  });

  test('a file that cannot be read says so', () async {
    final result = await pick(
      file(const [1], readError: const FileSystemException('gone')),
    );

    expect((result! as PlaylistFileProblem).message, unreadableFileText);
  });

  test('a picker that fails says the file cannot be read', () async {
    final result = await FilePickerPlaylistFileSource(
      pick: () async => throw const FileSystemException('picker'),
    ).pick();

    expect((result! as PlaylistFileProblem).message, '没能读取这个文件。');
  });

  test('decoding drops only a leading byte order mark', () {
    expect(
      decodePlaylistFileBytes(utf8.encode('\u{FEFF}a\u{FEFF}')),
      'a\u{FEFF}',
    );
    expect(decodePlaylistFileBytes(utf8.encode('a')), 'a');
    expect(
      decodePlaylistFileBytes(utf8.encode('\u{FEFF}\u{FEFF}a')),
      '\u{FEFF}a',
    );
  });
}
