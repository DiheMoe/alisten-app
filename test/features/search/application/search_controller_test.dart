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

  test('qq searches playlists too, and a page of songs replaces the one '
      'before it', () async {
    await harness.search.submit('jazz');
    expect(harness.state.source, TrackSource.qq);
    expect(types(), ['search.tracks', 'search.playlists']);
    expect(harness.state.overviewPlaylists, isNotEmpty);

    await harness.search.changeView(SearchView.playlists);
    expect(harness.state.view, SearchView.playlists);
    final playlists = harness.requests.last;
    expect(playlists['type'], 'search.playlists');
    expect((playlists['data']! as Map<String, Object?>)['source'], 'qq');

    await harness.search.changeView(SearchView.tracks);
    expect(harness.state.tracks, hasLength(6));
    expect(harness.state.pageCount, 3);

    expect(await harness.search.turnTo(2), PageTurnOutcome.turned);
    final request = harness.requests.last['data']! as Map<String, Object?>;
    expect(request['page'], 2);
    expect(request['pageSize'], 20);
    expect(harness.state.tracks, hasLength(6));
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
    expect(harness.state.pageCount, 2);
  });

  test('a response arriving after a newer submit is dropped and never '
      'cached under the newer key', () async {
    final held = <String, Completer<Map<String, Object?>>>{};
    harness.transport.requestHandler = (type, data) {
      final answer = Completer<Map<String, Object?>>();
      held[data['keyword']! as String] = answer;
      return answer.future;
    };

    final first = harness.search.submit('first', view: SearchView.tracks);
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

    final first = harness.search.submit('first', view: SearchView.tracks);
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

  test('the songs and playlists of a search open without asking '
      'again', () async {
    await harness.search.submit('jazz');
    expect(types(), ['search.tracks', 'search.playlists']);

    await harness.search.changeView(SearchView.tracks);
    expect(harness.state.status, isA<SearchLoaded>());
    expect(harness.state.tracks, hasLength(6));
    expect(harness.state.pageCount, 3);

    await harness.search.changeView(SearchView.playlists);
    expect(harness.state.playlists, hasLength(7));

    await harness.search.changeView(SearchView.all);
    expect(harness.state.bestMatch?.track.id, 'track-0');
    expect(types(), ['search.tracks', 'search.playlists']);
  });

  test('when only the playlists of a search fail, the songs are shown and '
      'retrying asks for the playlists alone', () async {
    var playlistsFail = true;
    harness.transport.requestHandler = (type, data) async {
      if (type == 'search.playlists' && playlistsFail) {
        throw const RoomRequestException(
          code: 'SOURCE_ERROR',
          message: '音乐平台没有正常响应，请稍后再试。',
          outcome: RoomRequestOutcome.failed,
        );
      }
      return harness.transport.responses[type]!;
    };

    await harness.search.submit('jazz', source: TrackSource.netease);
    final status = harness.state.status;
    expect(status, isA<SearchPartial>());
    expect((status as SearchPartial).code, 'SOURCE_ERROR');
    expect(harness.state.tracks, hasLength(6));

    await harness.search.retry();
    expect(harness.state.status, isA<SearchPartial>());
    expect(types(), ['search.tracks', 'search.playlists', 'search.playlists']);

    playlistsFail = false;
    await harness.search.submit('jazz', source: TrackSource.netease);
    expect(harness.state.status, isA<SearchLoaded>());
    expect(harness.state.tracks, hasLength(6));
    expect(harness.state.playlists, hasLength(7));
    expect(types().where((type) => type == 'search.tracks'), hasLength(1));
  });

  // 第 [gone] 页起平台不再给结果；其余每页 20 首，第 2 页只有 1 首。
  void serve({int total = 4321, int? gone}) {
    harness.transport.requestHandler = (type, data) async {
      final page = data['page']! as int;
      final count = gone != null && page >= gone ? 0 : (page == 2 ? 1 : 20);
      return tracksAnswer([
        for (var i = 0; i < count; i++) 'p$page-$i',
      ], total: total);
    };
  }

  List<String> shown() => [
    for (final song in harness.state.tracks) song.track.id,
  ];

  test('the pages are counted from the total, however short a page '
      'is', () async {
    serve();
    await harness.search.submit('jazz', view: SearchView.tracks);
    expect(harness.state.pageCount, 217);

    expect(await harness.search.turnTo(2), PageTurnOutcome.turned);
    expect(shown(), ['p2-0']);
    expect(harness.state.page, 2);
    expect(harness.state.pageCount, 217);

    expect(await harness.search.turnTo(3), PageTurnOutcome.turned);
    expect(shown().first, 'p3-0');
    expect(shown(), hasLength(20));

    serve(total: 40);
    await harness.search.submit('rock', view: SearchView.tracks);
    expect(harness.state.pageCount, 2);
  });

  test('a page seen before comes back without asking, and no page is asked '
      'for before the first or past the last', () async {
    serve(total: 40);
    await harness.search.submit('jazz', view: SearchView.tracks);
    await harness.search.turnTo(2);
    final sent = harness.requests.length;

    expect(await harness.search.turnTo(1), PageTurnOutcome.turned);
    expect(shown().first, 'p1-0');
    expect(await harness.search.turnTo(2), PageTurnOutcome.turned);
    expect(shown(), ['p2-0']);

    expect(await harness.search.turnTo(3), PageTurnOutcome.ignored);
    expect(await harness.search.turnTo(2), PageTurnOutcome.ignored);
    await harness.search.turnTo(1);
    expect(await harness.search.turnTo(0), PageTurnOutcome.ignored);
    expect(harness.requests, hasLength(sent));
    expect(harness.state.page, 1);
  });

  test('a page the platform does not give is not shown, and the page before '
      'it stays the last', () async {
    serve(gone: 3);
    await harness.search.submit('jazz', view: SearchView.tracks);
    await harness.search.turnTo(2);
    expect(harness.state.pageCount, 217);

    expect(await harness.search.turnTo(3), PageTurnOutcome.pastEnd);
    expect(harness.state.status, isA<SearchLoaded>());
    expect(harness.state.page, 2);
    expect(shown(), ['p2-0']);
    expect(harness.state.pageCount, 2);

    await harness.search.turnTo(1);
    expect(harness.state.pageCount, 2);
    await harness.search.submit('jazz', view: SearchView.tracks);
    expect(harness.state.pageCount, 2);

    now += 600000;
    serve();
    await harness.search.submit('jazz', view: SearchView.tracks);
    expect(harness.state.pageCount, 217);
  });

  test('a page refused for searching too often leaves the page shown, and '
      'asking again is for that page', () async {
    serve();
    await harness.search.submit('jazz', view: SearchView.tracks);

    harness.transport.requestHandler = (type, data) async {
      throw const RoomRequestException(
        code: 'RATE_LIMITED',
        message: '搜索过于频繁，请稍后再试。',
        outcome: RoomRequestOutcome.failed,
      );
    };
    expect(await harness.search.turnTo(2), PageTurnOutcome.failed);
    final status = harness.state.status;
    expect(status, isA<SearchPartial>());
    expect((status as SearchPartial).code, 'RATE_LIMITED');
    expect(status.message, '搜索过于频繁，请稍后再试。');
    expect(harness.state.turningTo, 2);
    expect(harness.state.page, 1);
    expect(shown(), hasLength(20));

    serve();
    expect(
      await harness.search.turnTo(harness.state.turningTo!),
      PageTurnOutcome.turned,
    );
    expect(harness.state.status, isA<SearchLoaded>());
    expect(harness.state.turningTo, isNull);
    expect(shown(), ['p2-0']);
  });

  test('while a page is on its way the page shown stays, and no other page '
      'is asked for', () async {
    serve();
    await harness.search.submit('jazz', view: SearchView.tracks);
    final held = Completer<Map<String, Object?>>();
    harness.transport.requestHandler = (type, data) => held.future;

    final turning = harness.search.turnTo(2);
    await pumpEventQueue();
    expect(harness.state.status, isA<SearchLoading>());
    expect(harness.state.turningTo, 2);
    expect(shown().first, 'p1-0');
    final sent = harness.requests.length;
    expect(await harness.search.turnTo(2), PageTurnOutcome.ignored);
    expect(harness.requests, hasLength(sent));

    held.complete(tracksAnswer(['p2-0'], total: 4321));
    expect(await turning, PageTurnOutcome.turned);
    expect(shown(), ['p2-0']);
  });

  test('an undecodable response ends in SearchFailed, not loading', () async {
    harness.transport.responses['search.tracks'] = {'items': 'oops'};

    await harness.search.submit('jazz', view: SearchView.tracks);

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
      await harness.search.submit('jazz', view: SearchView.tracks);
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

  test('songs reused for the overview are not kept longer for it', () async {
    await harness.search.submit('jazz', view: SearchView.tracks);

    now += 540000;
    await harness.search.submit('jazz', view: SearchView.all);
    expect(types(), ['search.tracks', 'search.playlists']);

    now += 60001;
    await harness.search.submit('jazz', view: SearchView.tracks);
    expect(types().where((type) => type == 'search.tracks'), hasLength(2));
  });

  test('the eleventh cached result evicts the least recently used', () async {
    for (var i = 0; i < 10; i++) {
      await harness.search.submit('k$i', view: SearchView.tracks);
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
