import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a page of 20 is cut from the server pages of 50 it spans', () {
    for (final (page, window, why) in [
      (1, (first: 1, last: 1, offset: 0), 'starts the first server page'),
      (3, (first: 1, last: 2, offset: 40), 'spans the first two'),
      (6, (first: 3, last: 3, offset: 0), 'starts the third'),
    ]) {
      expect(mediaWindow(page), window, reason: 'page $page $why');
    }
  });

  late FakeAdminApi api;
  late ProviderContainer container;
  late List<void Function()> timers;
  late ProviderSubscription<AdminMediaState> pageListener;

  Future<AdminMediaController> signedIn() async {
    container = ProviderContainer(
      overrides: [
        ...await switchingOverrides(
          store: FakeServerStore(profiles: [serverB]),
          credentials: FakeCredentialStores(),
        ),
        adminApiProvider.overrideWithValue(api),
        // 回调记下来由测试触发；返回已取消的 Timer，widget 测试里不留挂起的计时器。
        adminTimerProvider.overrideWithValue((duration, callback) {
          timers.add(callback);
          return Timer(Duration.zero, () {})..cancel();
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    pageListener = container.listen(adminMediaControllerProvider, (_, _) {});
    return container.read(adminMediaControllerProvider.notifier);
  }

  AdminMediaState state() => container.read(adminMediaControllerProvider);

  setUp(() {
    api = FakeAdminApi()
      ..media = [for (var n = 1; n <= 120; n++) storedTrack(n)];
    timers = [];
  });

  test('pages within a server page are cut from the same answer', () async {
    final media = await signedIn();
    await media.load();
    await media.goTo(2);
    expect(state().items.first.title, '歌曲 100');
    expect(api.mediaQueries.map((q) => q.page), [1]);
  });

  test('a page across two server pages reads both and joins them', () async {
    final media = await signedIn();
    await media.load();
    await media.goTo(3);
    expect(state().items.first.title, '歌曲 80');
    expect(state().items.last.title, '歌曲 61');
    expect(api.mediaQueries.map((q) => q.page), [1, 2]);
  });

  test('a song seen at the seam of two server pages shows once', () async {
    final media = await signedIn();
    await media.load();
    // 第 2 段读回之前又存了一首，第 1 段的最后一首被挤到第 2 段开头。
    api.media = [...api.media, storedTrack(121)];
    await media.goTo(3);
    final keys = state().items.map((t) => t.key).toList();
    expect(keys.toSet().length, keys.length);
  });

  test('a search applies 0.3 s after typing stops, back on page 1 with the '
      'cache and selection cleared', () async {
    final media = await signedIn();
    await media.load();
    await media.goTo(2);
    media
      ..toggle(state().items.first)
      ..setQuery('歌曲 11');
    expect(api.mediaQueries.length, 1);
    expect(timers, hasLength(1));
    timers.single();
    await pumpEventQueue();
    expect(state().query, '歌曲 11');
    expect(state().page, 1);
    expect(state().selected, isEmpty);
    expect(api.mediaQueries.last.query, '歌曲 11');
    expect(state().items.map((t) => t.title), contains('歌曲 110'));
  });

  test('a new order starts again on page 1', () async {
    final media = await signedIn();
    await media.load();
    await media.goTo(2);
    await media.setOrder(MediaOrder.size);
    expect(state().page, 1);
    expect(api.mediaQueries.last.order, MediaOrder.size);
  });

  test('the selection is kept across pages, and the page can be selected '
      'and unselected at once', () async {
    final media = await signedIn();
    await media.load();
    media.toggle(state().items.first);
    await media.goTo(2);
    media.togglePage();
    expect(state().selected.length, 21);
    expect(state().pageSelected, isTrue);
    media.togglePage();
    expect(state().selected.length, 1);
  });

  test('removing 120 songs goes in batches of 50, then the list is read '
      'again from the server', () async {
    final media = await signedIn();
    await media.load();
    final outcome = await media.remove(List.of(api.media));
    expect(api.removals.map((keys) => keys.length), [50, 50, 20]);
    expect(
      outcome,
      isA<MediaRemoved>().having((o) => o.deleted, 'deleted', 120),
    );
    expect(state().total, 0);
    expect(state().selected, isEmpty);
  });

  test('a failed batch stops the rest and counts what was deleted', () async {
    final media = await signedIn();
    await media.load();
    final all = List.of(api.media);
    var batches = 0;
    api.onRemoveMedia = () {
      // 第二批失败。
      if (++batches == 2) {
        throw const ApiException(
          code: 'INVALID_ARGUMENT',
          message: '有歌曲的 key 不对',
          status: 400,
        );
      }
    };
    final outcome = await media.remove(all);
    expect(api.removals.length, 2);
    expect(
      outcome,
      isA<MediaRemovalFailed>()
          .having((o) => o.message, 'message', '有歌曲的 key 不对')
          .having((o) => o.deleted, 'deleted', 50),
    );
  });

  test(
    'a lost answer is reported as unknown and the list is read again',
    () async {
      final media = await signedIn();
      await media.load();
      final reads = api.mediaQueries.length;
      api.removeMediaError = const ApiException(
        code: 'UNAVAILABLE',
        message: 'gone',
        status: 503,
      );
      final outcome = await media.remove([state().items.first]);
      expect(outcome, isA<MediaRemovalUnknown>());
      expect(api.mediaQueries.length, greaterThan(reads));
    },
  );

  test('after a delete leaves the page past the end, it falls back to the '
      'last page', () async {
    api.media = [for (var n = 1; n <= 41; n++) storedTrack(n)];
    final media = await signedIn();
    await media.load();
    await media.goTo(3);
    expect(state().items.single.title, '歌曲 1');
    await media.remove([state().items.single]);
    expect(state().page, 2);
    expect(state().items.length, 20);
  });

  group('the home summary', () {
    const unavailable = ApiException(
      code: 'UNAVAILABLE',
      message: 'gone',
      status: 503,
    );

    Future<AsyncValue<({int total, int totalBytes})>> summary() async {
      await pumpEventQueue();
      return container.read(adminMediaSummaryProvider);
    }

    test('a search result is not taken for the whole library; pulling to '
        'refresh reads the summary again', () async {
      api.listMediaError = unavailable;
      final media = await signedIn();
      container.listen(adminMediaSummaryProvider, (_, _) {});
      expect((await summary()).hasError, isTrue);

      api.listMediaError = null;
      media.setQuery('歌曲 11');
      timers.single();
      await pumpEventQueue();
      expect(state().total, 11);
      expect((await summary()).hasError, isTrue);

      await media.refresh();
      expect((await summary()).value?.total, 120);
    });

    test('a summary that already matches is not read again', () async {
      final media = await signedIn();
      container.listen(adminMediaSummaryProvider, (_, _) {});
      expect((await summary()).value?.total, 120);
      await media.load();
      await media.goTo(2);
      expect(api.mediaQueries, hasLength(2));
    });
  });

  test(
    'leaving the page during a removal still refreshes the summary',
    () async {
      final media = await signedIn();
      await media.load();
      container.listen(adminMediaSummaryProvider, (_, _) {});
      await container.read(adminMediaSummaryProvider.future);
      api.removeMediaGate = Completer<void>();
      final removal = media.remove([state().items.first]);
      await pumpEventQueue();
      // 页面唯一的监听者离开：没有 keepAlive 的话控制器此时被释放。
      pageListener.close();
      await pumpEventQueue();
      final reads = api.mediaQueries.length;
      api.removeMediaGate!.complete();
      await removal;
      await pumpEventQueue();
      final after = api.mediaQueries.skip(reads).toList();
      expect(after.where((q) => q.query.isEmpty && q.page == 1), hasLength(2));
      final summary = await container.read(adminMediaSummaryProvider.future);
      expect(summary.total, 119);
    },
  );

  test('an ended session leaves the list quiet and nothing is sent', () async {
    final media = await signedIn();
    container.read(adminSessionProvider.notifier).end();
    await media.load();
    await media.goTo(2);
    expect(state().loading, isFalse);
    expect(state().error, isNull);
    expect(api.mediaQueries, isEmpty);
    final outcome = await media.remove([storedTrack(1)]);
    expect(
      outcome,
      isA<MediaRemovalNotSent>().having(
        (o) => o.message,
        'message',
        '后台已退出，歌曲没有删除。',
      ),
    );
    expect(api.removals, isEmpty);
  });

  test(
    'songs already gone are deselected, songs in use stay selected',
    () async {
      final media = await signedIn();
      await media.load();
      final gone = state().items[0];
      final playing = state().items[1];
      media
        ..toggle(gone)
        ..toggle(playing);
      api.media = [
        for (final t in api.media)
          if (t.key != gone.key) t,
      ];
      api.mediaInUse = {playing.key};
      await media.remove(state().selected.values.toList());
      expect(state().selected.keys, [playing.key]);
    },
  );

  test(
    'a session that ends after some batches says the rest was kept',
    () async {
      final media = await signedIn();
      await media.load();
      var batches = 0;
      api.onRemoveMedia = () {
        if (++batches != 1) return;
        // 依赖第一批的结果在第二批开始前已被消费：微任务在两者之间运行。
        scheduleMicrotask(
          () => container.read(adminSessionProvider.notifier).end(),
        );
      };
      final outcome = await media.remove(List.of(api.media));
      expect(api.removals.length, 1);
      expect(
        outcome,
        isA<MediaRemovalFailed>()
            .having((o) => o.message, 'message', '后台已退出，余下的歌曲没有删除。')
            .having((o) => o.deleted, 'deleted', 50),
      );
    },
  );
}
