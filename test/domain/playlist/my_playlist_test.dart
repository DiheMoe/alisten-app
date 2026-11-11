import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_test/flutter_test.dart';

TrackSummary _song(String id, String coverUrl) {
  return TrackSummary(
    track: Track(source: TrackSource.netease, id: id),
    meta: TrackMeta(
      title: '歌$id',
      artist: '歌手',
      album: '',
      coverUrl: coverUrl,
      pageUrl: '',
      durationMs: 0,
    ),
  );
}

SharedPlaylist _shared(List<TrackSummary> items) {
  return SharedPlaylist(
    name: '夜跑',
    favorites: false,
    ownerName: '阿柚',
    ownerAvatarHash: '',
    items: items,
  );
}

void main() {
  test('a shared playlist takes the cover of its first song that has one', () {
    expect(
      _shared([
        _song('1', ''),
        _song('2', 'https://example.com/2.jpg'),
        _song('3', 'https://example.com/3.jpg'),
      ]).coverUrl,
      'https://example.com/2.jpg',
    );
    expect(_shared([_song('1', '')]).coverUrl, isNull);
    expect(_shared(const []).coverUrl, isNull);
  });

  test('copyWith changes the name or the share, and clears the share when '
      'given null', () {
    const playlist = MyPlaylist(
      id: 'pl-1',
      name: '夜跑',
      favorites: false,
      trackCount: 3,
      createdAtMs: 1,
      updatedAtMs: 2,
      coverUrl: 'https://example.com/a.jpg',
      shareId: 'AbCdEfGhIjKlMnOpQrStUv',
    );

    final renamed = playlist.copyWith(name: '晨跑');
    expect(renamed.name, '晨跑');
    expect(renamed.shareId, 'AbCdEfGhIjKlMnOpQrStUv');
    expect(renamed.coverUrl, 'https://example.com/a.jpg');
    expect(renamed.trackCount, 3);

    expect(playlist.copyWith(shareId: null).shareId, isNull);
    expect(playlist.copyWith(shareId: 'x').shareId, 'x');
  });
}
