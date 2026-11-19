import 'dart:typed_data';

import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';

const _ada = Member(id: 'ada', name: '阿柚', avatarHash: '');

QueueEntry _entry(String id) => QueueEntry(
  id: id,
  track: testTrack,
  meta: TrackMeta(
    title: '歌$id',
    artist: '歌手',
    album: '专辑',
    coverUrl: 'https://example.com/$id.jpg',
    pageUrl: 'https://example.com/$id',
    durationMs: 180000,
  ),
  requestedBy: _ada,
  auto: false,
  likes: 0,
  status: QueueEntryStatus.ready,
);

void main() {
  testWidgets('the covers of the pending song and the first ten waiting are '
      'fetched before the queue is shown, each once, and so are new ones', (
    tester,
  ) async {
    var snapshot = testRoomSnapshot().copyWith(
      term: 1,
      seq: 1,
      pending: _entry('p'),
      items: [for (var i = 1; i <= 12; i++) _entry('$i')],
    );
    final container = ProviderContainer(
      overrides: [
        roomControllerProvider.overrideWithBuild(
          (ref, _) => RoomState(
            status: RoomConnectionStatus.open,
            activeRoomId: 'room-id',
            snapshot: snapshot,
            member: _ada,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final asked = <String>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: CoverImages(
            resolve: (url) {
              asked.add(url);
              return MemoryImage(Uint8List(0));
            },
            child: const QueueCoverWarmup(child: SizedBox()),
          ),
        ),
      ),
    );

    expect(asked, [
      'https://example.com/p.jpg',
      for (var i = 1; i <= 10; i++) 'https://example.com/$i.jpg',
    ]);

    asked.clear();
    snapshot = snapshot.copyWith(
      term: 1,
      seq: 2,
      pending: _entry('1'),
      items: [for (var i = 2; i <= 13; i++) _entry('$i')],
    );
    container.invalidate(roomControllerProvider);
    await tester.pump();
    expect(asked, ['https://example.com/11.jpg']);
  });
}
