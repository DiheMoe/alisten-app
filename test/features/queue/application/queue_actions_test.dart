import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/queue/application/queue_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../room/room_test_doubles.dart';

void main() {
  late FakeRoomTransport transport;
  late QueueActions actions;

  setUp(() {
    transport = FakeRoomTransport()..emitHello();
    actions = QueueActions(<T>(run) async {
      return MutationSucceeded(await run(RoomCommands(transport)));
    });
  });

  T valueOf<T>(MutationResult<T> result) {
    return (result as MutationSucceeded<T>).value;
  }

  test(
    'addTrack sends only the domain track and returns the confirmed entry',
    () async {
      transport.responses['queue.add'] = {'entry': _entryJson()};

      final entry = valueOf(await actions.addTrack(testTrack));

      expect(transport.requests.single['type'], 'queue.add');
      expect(transport.requests.single['data'], {
        'track': {'source': 'netease', 'id': 'track-id'},
      });
      expect(entry.id, 'entry-id');
    },
  );

  test('remove and like target only the selected waiting entry', () async {
    transport.responses['queue.like'] = {'likes': 4};

    await actions.remove('entry-id');
    final likes = valueOf(await actions.like('entry-id'));

    expect(transport.requests[0]['type'], 'queue.remove');
    expect(transport.requests[0]['data'], {'entryId': 'entry-id'});
    expect(transport.requests[1]['type'], 'queue.like');
    expect(likes, 4);
  });

  test('vote skip preserves votes required and skipped feedback', () async {
    transport.responses['playback.voteSkip'] = {
      'votes': 2,
      'required': 3,
      'skipped': false,
    };

    final result = valueOf(await actions.voteSkip());

    expect(transport.requests.single['type'], 'playback.voteSkip');
    expect(result.votes, 2);
    expect(result.requiredVotes, 3);
    expect(result.skipped, isFalse);
  });

  test('all play modes use the protocol values', () async {
    for (final mode in RoomPlayMode.values) {
      await actions.setPlayMode(mode);
    }

    expect(
      transport.requests.map(
        (request) => (request['data']! as Map<String, Object?>)['playMode'],
      ),
      ['sequential', 'random', 'rotation'],
    );
  });
}

Map<String, Object?> _entryJson() {
  return {
    'id': 'entry-id',
    'track': {'source': 'netease', 'id': 'track-id'},
    'meta': {
      'title': '歌曲',
      'artist': '歌手',
      'album': '专辑',
      'coverUrl': '',
      'pageUrl': '',
      'durationMs': 1000,
    },
    'by': null,
    'auto': true,
    'likes': 0,
    'status': 'ready',
  };
}
