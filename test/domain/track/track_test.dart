import 'package:alisten/domain/track/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a track key is the source name and the id', () {
    expect(
      trackKey(const Track(source: TrackSource.bilibili, id: 'BV1xx')),
      'bilibili:BV1xx',
    );
  });

  test('the same id from another source has another key', () {
    expect(
      trackKey(const Track(source: TrackSource.netease, id: '1')),
      isNot(trackKey(const Track(source: TrackSource.qq, id: '1'))),
    );
  });
}
