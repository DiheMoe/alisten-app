import 'dart:async';

import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/application/search_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchHarness harness;
  late int now;

  setUp(() async {
    now = 1000000;
    harness = await SearchHarness.open(now: () => now);
  });

  tearDown(() => harness.dispose());

  List<String> types() => [
    for (final request in harness.requests) request['type']! as String,
  ];

  test('netease all view loads best match and the overviews', () async {
    await harness.search.submit('jazz', source: TrackSource.netease);

    expect(types(), ['search.tracks', 'search.playlists']);
    expect(harness.state.status, isA<SearchLoaded>());
    expect(harness.state.bestMatch?.track.id, 'track-0');
    expect(harness.state.overviewTracks.first.track.id, 'track-1');
    expect(harness.state.overviewTracks, hasLength(5));
    expect(harness.state.overviewPlaylists, hasLength(4));
    expect(harness.state.recentSearches.single.query, 'jazz');
  });

  test('qq has no playlists and loads further pages by appending', () async {
    await harness.search.submit('jazz');
    await harness.search.changeView(SearchView.playlists);

    expect(harness.state.view, SearchView.all);
    expect(types().where((type) => type == 'search.playlists'), isEmpty);

    await harness.search.changeView(SearchView.tracks);
    expect(harness.state.tracks, hasLength(6));
    expect(harness.state.hasMore, isTrue);

    await harness.search.loadMore();
    final request = harness.requests.last['data']! as Map<String, Object?>;
    expect(request['page'], 2);
    expect(request['pageSize'], 20);
    expect(harness.state.tracks, hasLength(12));
    expect(harness.state.page, 2);
  });

  test('playlist view requests playlists only and knows the total', () async {
    harness.transport.responses['search.playlists'] = {
      'items': List.generate(21, (index) => playlistJson('playlist-$index')),
      'total': 21,
    };

    await harness.search.submit(
      'jazz',
      source: TrackSource.netease,
      view: SearchView.playlists,
    );

    expect(types(), ['search.playlists']);
    expect(harness.state.playlists, hasLength(21));
    expect(harness.state.hasMore, isFalse);
  });

  test('a response arriving after a newer submit is dropped and never '
      'cached under the newer key', () async {
    final held = <String, Completer<Map<String, Object?>>>{};
    harness.transport.requestHandler = (type, data) {
      final answer = Completer<Map<String, Object?>>();
      held[data['keyword']! as String] = answer;
      return answer.future;
    };

    final first = harness.search.submit('first');
    final second = harness.search.submit('second');
    await pumpEventQueue();
    expect(held.keys, containsAll(['first', 'second']));

    held['first']!.complete(tracksAnswer(['from-first']));
    await pumpEventQueue();
    expect(harness.state.keyword, 'second');
    expect(harness.state.status, isA<SearchLoading>());
    expect(harness.state.tracks, isEmpty);

    held['second']!.complete(tracksAnswer(['from-second']));
    await Future.wait([first, second]);
    expect(harness.state.tracks.single.track.id, 'from-second');

    harness.transport.requestHandler = null;
    final sent = harness.requests.length;
    await harness.search.submit('second');
    expect(harness.requests, hasLength(sent));
    expect(harness.state.tracks.single.track.id, 'from-second');
  });

  test('a stale response that comes last does not replace the newer '
      'result', () async {
    final held = <String, Completer<Map<String, Object?>>>{};
    harness.transport.requestHandler = (type, data) {
      final answer = Completer<Map<String, Object?>>();
      held[data['keyword']! as String] = answer;
      return answer.future;
    };

    final first = harness.search.submit('first');
    final second = harness.search.submit('second');
    await pumpEventQueue();
    held['second']!.complete(tracksAnswer(['from-second']));
    await pumpEventQueue();
    held['first']!.complete(tracksAnswer(['from-first']));
    await Future.wait([first, second]);

    expect(harness.state.keyword, 'second');
    expect(harness.state.tracks.single.track.id, 'from-second');

    harness.transport.requestHandler = null;
    final sent = harness.requests.length;
    await harness.search.submit('second');
    expect(harness.requests, hasLength(sent));
    expect(harness.state.tracks.single.track.id, 'from-second');
    await harness.search.submit('first');
    expect(harness.requests, hasLength(sent + 1));
  });

  test('a partial failure is shown and is not cached', () async {
    harness.transport.requestHandler = (type, data) async {
      if (type == 'search.playlists') {
        throw const RoomRequestException(
          code: 'PROVIDER_ERROR',
          message: '音乐平台没有正常响应，请稍后再试。',
          outcome: RoomRequestOutcome.failed,
        );
      }
      return tracksAnswer(['track']);
    };

    await harness.search.submit('jazz', source: TrackSource.netease);
    final status = harness.state.status;
    expect(status, isA<SearchPartial>());
    expect((status as SearchPartial).code, 'PROVIDER_ERROR');
    expect(harness.state.tracks, hasLength(1));

    await harness.search.submit('jazz', source: TrackSource.netease);
    expect(types().where((type) => type == 'search.tracks'), hasLength(2));
  });

  test('an undecodable response ends in SearchFailed, not loading', () async {
    harness.transport.responses['search.tracks'] = {'items': 'oops'};

    await harness.search.submit('jazz');

    final status = harness.state.status;
    expect(status, isA<SearchFailed>());
    expect((status as SearchFailed).code, 'PROTOCOL_MISMATCH');
    expect(status.message, contains('升级'));
    expect(harness.state.loading, isFalse);
  });

  test('a keyword the server refuses as too long gets its own text', () async {
    harness.transport.requestError = const RoomRequestException(
      code: 'INVALID_ARGUMENT',
      message: 'keyword：长度不能超过 500 个字符',
      outcome: RoomRequestOutcome.failed,
    );

    await harness.search.submit('x' * 501);

    final status = harness.state.status as SearchFailed;
    expect(status.code, 'INVALID_ARGUMENT');
    expect(status.message, '关键词太长了，最多 500 个字符。');
  });

  test(
    'cache is usable while disconnected and expires at ten minutes',
    () async {
      await harness.search.submit('jazz');
      harness.transport.emit(const RoomStopped(4404));
      await pumpEventQueue();

      await harness.search.submit('jazz');
      expect(harness.requests, hasLength(1));
      expect(harness.state.status, isA<SearchLoaded>());

      harness.transport.emit(
        const RoomConnectionChanged(RoomConnectionStatus.open),
      );
      await pumpEventQueue();
      now += 600000;
      await harness.search.submit('jazz');
      expect(harness.requests, hasLength(2));
    },
  );

  test('the eleventh cached result evicts the least recently used', () async {
    for (var i = 0; i < 10; i++) {
      await harness.search.submit('k$i');
    }
    await harness.search.submit('k0');
    expect(harness.requests, hasLength(10));

    await harness.search.submit('k10');
    expect(harness.requests, hasLength(11));

    await harness.search.submit('k0');
    expect(harness.requests, hasLength(11));
    await harness.search.submit('k1');
    expect(harness.requests, hasLength(12));
  });

  test('a request in flight when the room changes never reaches the new '
      'room', () async {
    final held = Completer<Map<String, Object?>>();
    harness.transport.requestHandler = (type, data) => held.future;
    final stale = harness.search.submit('jazz');
    await pumpEventQueue();
    expect(harness.state.status, isA<SearchLoading>());

    await harness.openRoom('two');
    held.complete(tracksAnswer(['from-old-room']));
    await stale;

    expect(harness.state.status, isA<SearchIdle>());
    expect(harness.state.keyword, isEmpty);
    expect(harness.state.tracks, isEmpty);

    await harness.search.submit('jazz');
    expect(harness.state.tracks, hasLength(6));
  });

  test('recommendations refresh, and changing rooms clears them', () async {
    await harness.search.refreshRecommendations();
    await harness.search.refreshRecommendations();
    expect(harness.state.recommendations.single.track.id, 'recommended');
    expect(harness.requests, hasLength(2));

    await harness.openRoom('two');
    expect(harness.state.recommendations, isEmpty);
    expect(harness.state.keyword, isEmpty);
  });

  test('submits are recorded and the history can be cleared', () async {
    await harness.search.submit('jazz');
    await pumpEventQueue();
    expect(harness.history.records.single.query, 'jazz');
    expect(harness.state.recentSearches.single.category, SearchCategory.all);

    await harness.search.clearHistory();
    expect(harness.state.recentSearches, isEmpty);
    expect(harness.history.records, isEmpty);
  });

  test('a store that cannot be written does not break searching', () async {
    harness.history.addError = Exception('disk full');

    await harness.search.submit('jazz');
    await pumpEventQueue();

    expect(harness.state.status, isA<SearchLoaded>());
    expect(harness.state.tracks, hasLength(6));
  });

  test('nothing is recorded while search history is off', () async {
    harness.dispose();
    harness = await SearchHarness.open(
      preferences: {'alisten.search-history.enabled': false},
    );

    await harness.search.submit('jazz');
    await pumpEventQueue();

    expect(harness.history.adds, 0);
    expect(harness.state.recentSearches, isEmpty);
  });
}
