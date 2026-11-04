import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';

NowPlaying _track({String lyric = '', String? words, String? translation}) {
  return NowPlaying(
    entry: testNowPlaying.entry,
    mediaUrl: testNowPlaying.mediaUrl,
    startedAtMs: testNowPlaying.startedAtMs,
    durationMs: testNowPlaying.durationMs,
    gain: 1,
    lyric: lyric,
    lyricWords: words,
    lyricTrans: translation,
  );
}

RoomState _roomWith(NowPlaying nowPlaying) {
  return RoomState(
    snapshot: testRoomSnapshot().copyWith(
      term: 1,
      seq: 1,
      nowPlaying: nowPlaying,
    ),
  );
}

final class _Room extends Notifier<RoomState> {
  @override
  RoomState build() => const RoomState();

  void show(RoomState room) => state = room;
}

final _roomFixture = NotifierProvider<_Room, RoomState>(_Room.new);

void main() {
  ProviderContainer containerWith(RoomState room) {
    final container = ProviderContainer(
      overrides: [
        roomControllerProvider.overrideWithBuild(
          (ref, _) => ref.watch(_roomFixture),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(_roomFixture.notifier).show(room);
    return container;
  }

  test('word lyrics and translations both reach the lines', () {
    final container = containerWith(
      _roomWith(
        _track(
          lyric: '[00:01.00]行级',
          words: '[1000,500](1000,500,0)逐字',
          translation: '[00:01.00]Words',
        ),
      ),
    );

    final line = container.read(lyricsProvider).first;

    expect(line.text, '逐字');
    expect(line.translation, 'Words');
  });

  test('no track means no lines', () {
    expect(containerWith(const RoomState()).read(lyricsProvider), isEmpty);
  });

  test('an unrelated room change keeps the parsed lines', () {
    final container = containerWith(_roomWith(_track(lyric: '[00:01.00]行级')));
    final before = container.read(lyricsProvider);

    container
        .read(_roomFixture.notifier)
        .show(_roomWith(_track(lyric: '[00:01.00]行级')));

    expect(container.read(lyricsProvider), same(before));
  });

  test('a new translation parses the lines again', () {
    final container = containerWith(_roomWith(_track(lyric: '[00:01.00]行级')));

    container
        .read(_roomFixture.notifier)
        .show(
          _roomWith(
            _track(lyric: '[00:01.00]行级', translation: '[00:01.00]Line'),
          ),
        );

    expect(container.read(lyricsProvider).single.translation, 'Line');
  });
}
