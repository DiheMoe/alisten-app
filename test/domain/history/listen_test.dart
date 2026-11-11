import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_test/flutter_test.dart';

Listen _listen(TrackSource source, String id, {int heardAtMs = 0}) {
  return Listen(
    track: Track(source: source, id: id),
    meta: const TrackMeta(
      title: '歌曲',
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
      pageUrl: '',
      durationMs: 180000,
    ),
    heardAtMs: heardAtMs,
  );
}

void main() {
  test('the same source and id is the same track, whenever it was heard', () {
    expect(
      _listen(
        TrackSource.netease,
        '1',
        heardAtMs: 1,
      ).isSameTrackAs(_listen(TrackSource.netease, '1', heardAtMs: 2)),
      isTrue,
    );
  });

  test('the same id from another source is another track', () {
    expect(
      _listen(
        TrackSource.netease,
        '1',
      ).isSameTrackAs(_listen(TrackSource.qq, '1')),
      isFalse,
    );
  });
}
