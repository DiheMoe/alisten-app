import 'dart:async';

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/clipboard_link_controller.dart';
import 'package:alisten/features/search/application/invite_link.dart';
import 'package:alisten/features/search/application/pending_share_controller.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/server/index.dart';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';
import '../share_test_doubles.dart';

const _song = ResolvedShare(
  link: 'https://music.163.com/song?id=186016&userid=1',
  platform: LinkPlatform.netease,
  track: Track(source: TrackSource.netease, id: '186016'),
  title: '晴天',
);

const _webLink = ResolvedShare(
  link: 'https://example.com/a.mp3',
  platform: LinkPlatform.web,
  track: Track(source: TrackSource.link, id: 'https://example.com/a.mp3'),
);

const _bilibiliLink = ResolvedShare(
  link: 'https://b23.tv/xyz',
  platform: LinkPlatform.bilibili,
  track: Track(source: TrackSource.link, id: 'https://b23.tv/xyz'),
);

const _playlist = ResolvedShare(
  link: 'https://music.163.com/#/playlist?id=1',
  platform: LinkPlatform.netease,
  problem: LinkProblem.notSong,
);

const _unfollowed = ResolvedShare(
  link: 'https://163cn.tv/abcd',
  platform: LinkPlatform.netease,
  problem: LinkProblem.unrecognized,
);

/// 默认服务器上有临时房间 'listen' 和常驻房间 'always'，都未进入；另已保存
/// [serverB]。
final class _Harness {
  _Harness._(
    this.container,
    this.rooms,
    this.shares,
    this.links,
    this.clipboard,
    this.probe,
  );

  final ProviderContainer container;
  final FakeRoomTransportFactory rooms;
  final FakeSharedTextSource shares;
  final FakeLinkResolver links;
  final FakeClipboardSource clipboard;
  final FakeServerProbe probe;

  static Future<_Harness> create() async {
    final rooms = FakeRoomTransportFactory();
    final shares = FakeSharedTextSource();
    final links = FakeLinkResolver();
    final clipboard = FakeClipboardSource();
    final probe = FakeServerProbe();
    final credentials = FakeCredentialStores();
    credentials(testEnvironment.defaultServerId).tickets
      ..['room-id'] = 'ticket-one'
      ..['room-two'] = 'ticket-two';
    final container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: credentials,
      api: FakeAlistenApi()
        ..rooms = [
          roomListing(),
          roomListing(id: 'room-two', slug: 'always', name: '常驻'),
        ],
      rooms: rooms,
      extra: [
        serverProbeProvider.overrideWithValue(probe),
        sharedTextSourceProvider.overrideWithValue(shares),
        linkResolverProvider.overrideWithValue(links),
        clipboardSourceProvider.overrideWithValue(clipboard),
      ],
    );
    return _Harness._(container, rooms, shares, links, clipboard, probe);
  }

  PendingShare? get pending => container.read(pendingShareControllerProvider);

  InviteOffer? get invite => container.read(inviteOfferControllerProvider);

  Future<void> enter(String ref, RoomKind kind) async {
    await container.read(roomControllerProvider.notifier).openRoom(ref);
    hello(ref, kind);
    await pumpEventQueue();
  }

  void hello(String ref, RoomKind kind) {
    final id = ref == 'listen' ? 'room-id' : 'room-two';
    rooms.last.emitHello(
      testRoomSnapshot().copyWith(
        term: 1,
        seq: 1,
        room: RoomInfo(id: id, name: ref, description: '', kind: kind),
      ),
    );
  }

  /// 关闭返回的订阅即关闭点歌页。
  Future<ProviderSubscription<ResolvedShare?>> openSearch() async {
    final page = container.listen(clipboardLinkControllerProvider, (_, _) {});
    await container.read(clipboardLinkControllerProvider.notifier).check();
    return page;
  }

  Future<void> closeSearch(ProviderSubscription<ResolvedShare?> page) async {
    page.close();
    await container.pump();
  }
}

void main() {
  group('what can be picked where', () {
    test('a song of NetEase or QQ Music can be picked in any room, before '
        'the room is known too', () {
      for (final kind in [null, ...RoomKind.values]) {
        expect(unpickableReason(_song, kind), isNull);
      }
    });

    test('a temporary room refuses a website link with the reason and takes '
        'a Bilibili link', () {
      expect(unpickableReason(_webLink, RoomKind.ephemeral), '临时房间只能点 B 站链接');
      expect(unpickableReason(_bilibiliLink, RoomKind.ephemeral), isNull);
      expect(unpickableReason(_webLink, RoomKind.persistent), isNull);
      expect(unpickableReason(_webLink, null), isNull);
    });

    test('a page that is not a song, or a short link not followed, says '
        'why in any room', () {
      for (final kind in [null, ...RoomKind.values]) {
        expect(unpickableReason(_playlist, kind), '只支持单曲链接');
        expect(unpickableReason(_unfollowed, kind), '没能识别这个链接');
      }
    });
  });

  group('a shared text', () {
    test('without an active room is kept, and stays once a room is '
        'entered', () async {
      final harness = await _Harness.create();
      harness.links.answers[neteaseShareText] = _song;
      harness.container.listen(pendingShareControllerProvider, (_, _) {});

      harness.shares.share(neteaseShareText);
      await pumpEventQueue();

      final pending = harness.pending!;
      expect(pending.roomId, isNull);
      expect(pending.resolved, isTrue);
      expect(pending.share?.track?.id, '186016');

      await harness.enter('listen', RoomKind.ephemeral);
      expect(harness.pending?.id, pending.id);
      expect(harness.pending?.share, same(pending.share));
    });

    test('while a room is active names that room', () async {
      final harness = await _Harness.create();
      harness.links.answers[neteaseShareText] = _song;
      harness.container.listen(pendingShareControllerProvider, (_, _) {});
      await harness.enter('listen', RoomKind.ephemeral);

      harness.shares.share(neteaseShareText);
      await pumpEventQueue();

      expect(harness.pending?.roomId, 'room-id');
      expect(harness.pending?.share?.title, '晴天');
    });

    test('is kept before what it shares is known; only the latest is kept, '
        'and a late answer to an older one is dropped', () async {
      final harness = await _Harness.create();
      harness.links
        ..hold = true
        ..answers['first https://163cn.tv/one'] = _unfollowed
        ..answers['second'] = null;
      harness.container.listen(pendingShareControllerProvider, (_, _) {});

      harness.shares.share('first https://163cn.tv/one');
      await pumpEventQueue();
      final first = harness.pending!;
      expect(first.resolved, isFalse);
      expect(first.share, isNull);

      harness.shares.share('second');
      await pumpEventQueue();
      final second = harness.pending!;
      expect(second.id, isNot(first.id));

      harness.links.release('first https://163cn.tv/one');
      await pumpEventQueue();
      expect(harness.pending, same(second), reason: 'the older answer is late');

      harness.links.release('second');
      await pumpEventQueue();
      expect(harness.pending?.id, second.id);
      expect(harness.pending?.resolved, isTrue);
      expect(
        harness.pending?.share,
        isNull,
        reason: 'a text without a link shares nothing',
      );
    });

    test('is let go only by its own id', () async {
      final harness = await _Harness.create();
      harness.links.answers[neteaseShareText] = _song;
      final shares = harness.container.read(
        pendingShareControllerProvider.notifier,
      );

      harness.shares.share(neteaseShareText);
      await pumpEventQueue();
      final first = harness.pending!;
      harness.shares.share(neteaseShareText);
      await pumpEventQueue();
      final second = harness.pending!;

      shares.dismiss(first.id);
      expect(harness.pending, same(second));
      shares.dismiss(second.id);
      expect(harness.pending, isNull);
    });
  });

  group('a share kept without a room', () {
    test('is offered to the room entered next once it opens', () async {
      final harness = await _Harness.create();
      harness.links.answers[neteaseShareText] = _song;
      harness.container.listen(pendingShareControllerProvider, (_, _) {});
      harness.shares.share(neteaseShareText);
      await pumpEventQueue();
      final kept = harness.pending!;

      await harness.container
          .read(roomControllerProvider.notifier)
          .openRoom('listen');
      await pumpEventQueue();
      expect(harness.pending?.roomId, isNull, reason: 'still connecting');

      harness.hello('listen', RoomKind.ephemeral);
      await pumpEventQueue();
      expect(harness.pending?.id, kept.id);
      expect(harness.pending?.roomId, 'room-id');
      expect(harness.pending?.share, same(kept.share));
    });

    test('keeps the room it was offered to when what it shares is known '
        'after', () async {
      final harness = await _Harness.create();
      harness.links
        ..answers[neteaseShareText] = _song
        ..hold = true;
      harness.container.listen(pendingShareControllerProvider, (_, _) {});
      harness.shares.share(neteaseShareText);
      await pumpEventQueue();

      await harness.enter('listen', RoomKind.ephemeral);
      harness.links.release(neteaseShareText);
      await pumpEventQueue();

      expect(harness.pending?.resolved, isTrue);
      expect(harness.pending?.roomId, 'room-id');
    });
  });

  group('a shared room link', () {
    ResolvedShare webLink(String link) => ResolvedShare(
      link: link,
      platform: LinkPlatform.web,
      track: Track(source: TrackSource.link, id: link),
    );

    test('of a saved server is offered as an invite, not kept as a '
        'song', () async {
      final harness = await _Harness.create();
      const link = 'https://example.com:8443/r/abc';
      harness.links.answers[link] = webLink(link);
      harness.container.listen(pendingShareControllerProvider, (_, _) {});

      harness.shares.share(link);
      await pumpEventQueue();

      expect(
        harness.invite?.target,
        isA<InviteToSaved>()
            .having((t) => t.server, 'server', serverB)
            .having((t) => t.route, 'route', '/r/abc'),
      );
      expect(harness.pending, isNull);
      expect(harness.links.asked, isEmpty, reason: 'not resolved as a song');
    });

    test('on a website that is not Alisten is a song link like any '
        'other', () async {
      final harness = await _Harness.create();
      const link = 'https://www.reddit.com/r/flutterdev';
      harness.links.answers[link] = webLink(link);
      harness.probe.siteResults['https://www.reddit.com'] = const ProbeFailed(
        ProbeFailure.notAlisten,
      );
      harness.container.listen(pendingShareControllerProvider, (_, _) {});

      harness.shares.share(link);
      await pumpEventQueue();

      expect(harness.pending?.resolved, isTrue);
      expect(harness.pending?.share?.track?.source, TrackSource.link);
      expect(harness.invite, isNull);
      expect(harness.probe.siteProbed, [
        ('https://www.reddit.com', const Duration(seconds: 5)),
      ]);
    });

    test('replaces a share kept before it', () async {
      final harness = await _Harness.create();
      const link = 'https://example.com:8443/r/abc';
      harness.links
        ..answers[neteaseShareText] = _song
        ..answers[link] = webLink(link);
      harness.container.listen(pendingShareControllerProvider, (_, _) {});
      harness.shares.share(neteaseShareText);
      await pumpEventQueue();
      expect(harness.pending?.share, same(_song));

      harness.shares.share(link);
      await pumpEventQueue();

      expect(harness.pending, isNull);
      expect(harness.invite?.target, isA<InviteToSaved>());
    });

    test('still being checked is dropped once something newer is '
        'shared', () async {
      final harness = await _Harness.create();
      const link = 'https://new.example.org/r/party';
      harness.links
        ..answers[link] = webLink(link)
        ..answers[neteaseShareText] = _song;
      harness.probe
        ..gate = Completer()
        ..siteResults['https://new.example.org'] = const ProbeSucceeded(
          origin: 'https://new.example.org',
          brandName: '新站',
        );
      harness.container.listen(pendingShareControllerProvider, (_, _) {});

      harness.shares.share(link);
      await pumpEventQueue();
      expect(harness.probe.siteProbed, hasLength(1));
      harness.shares.share(neteaseShareText);
      await pumpEventQueue();
      harness.probe.gate!.complete();
      await pumpEventQueue();

      expect(harness.invite, isNull);
      expect(harness.pending?.share, same(_song));
    });
  });

  group('a shared playlist link', () {
    const id = 'AbCdEfGhIjKlMnOpQrStUv';

    ResolvedShare webLink(String link) => ResolvedShare(
      link: link,
      platform: LinkPlatform.web,
      track: Track(source: TrackSource.link, id: link),
    );

    test('of the current server is opened from inside a room, not kept as '
        'a song', () async {
      final harness = await _Harness.create();
      const link = 'https://livehouse.dihe.moe/s/$id';
      harness.links.answers[link] = webLink(link);
      await harness.enter('listen', RoomKind.persistent);
      harness.container.listen(pendingShareControllerProvider, (_, _) {});

      harness.shares.share(link);
      await pumpEventQueue();

      expect(
        harness.invite?.target,
        isA<InviteToCurrent>()
            .having((t) => t.route, 'route', '/s/$id')
            .having((t) => t.isActiveRoom, 'isActiveRoom', isFalse),
      );
      expect(harness.pending, isNull);
      expect(harness.links.asked, isEmpty, reason: 'not resolved as a song');
      expect(harness.probe.siteProbed, isEmpty);
    });

    test('of a saved server is offered as an invite to that server', () async {
      final harness = await _Harness.create();
      const link = 'https://example.com:8443/s/$id';
      harness.links.answers[link] = webLink(link);
      harness.container.listen(pendingShareControllerProvider, (_, _) {});

      harness.shares.share(link);
      await pumpEventQueue();

      expect(
        harness.invite?.target,
        isA<InviteToSaved>()
            .having((t) => t.server, 'server', serverB)
            .having((t) => t.route, 'route', '/s/$id'),
      );
      expect(harness.pending, isNull);
      expect(harness.links.asked, isEmpty, reason: 'not resolved as a song');
    });
  });

  group('a link typed in song search', () {
    const short = 'https://163cn.tv/abcd';
    const shorter = 'https://163cn.tv/abc';
    const unfollowed = ResolvedShare(
      link: short,
      platform: LinkPlatform.netease,
      unfollowed: true,
    );

    ProviderContainer typing(FakeLinkResolver links) {
      final container = ProviderContainer(
        overrides: [
          linkResolverProvider.overrideWithValue(links),
          buildEnvironmentProvider.overrideWithValue(testEnvironment),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is told at once without the network', () {
      final links = FakeLinkResolver()..answers[_song.link] = _song;
      final container = typing(links);

      container.listen(typedLinkProvider(_song.link), (_, _) {});

      expect(container.read(typedLinkProvider(_song.link)), same(_song));
      expect(links.asked, isEmpty);
    });

    test('is followed, when a short link, once typing pauses for 400 ms: '
        'one typed over is not', () {
      fakeAsync((async) {
        final links = FakeLinkResolver()
          ..recognitions[shorter] = unfollowed
          ..recognitions[short] = unfollowed
          ..answers[short] = _song;
        final container = typing(links);

        final first = container.listen(typedLinkProvider(shorter), (_, _) {});
        async.elapse(const Duration(milliseconds: 300));
        container.listen(typedLinkProvider(short), (_, _) {});
        first.close();
        async.elapse(const Duration(milliseconds: 399));
        expect(links.asked, isEmpty);
        expect(container.read(typedLinkProvider(short))?.unfollowed, isTrue);

        async.elapse(const Duration(milliseconds: 1));
        expect(links.asked, [short]);
        async.flushMicrotasks();
        expect(container.read(typedLinkProvider(short)), same(_song));

        async.elapse(const Duration(seconds: 1));
        expect(links.asked, [short], reason: 'the first was typed over');
      });
    });

    test('stops being followed once no longer typed', () {
      fakeAsync((async) {
        final links = FakeLinkResolver()
          ..recognitions[short] = unfollowed
          ..answers[short] = _song
          ..hold = true;
        final container = typing(links);
        final field = container.listen(typedLinkProvider(short), (_, _) {});
        async.elapse(const Duration(milliseconds: 400));
        expect(links.asked, [short]);
        var cancelled = false;
        unawaited(links.cancels.single!.then((_) => cancelled = true));

        field.close();
        async.elapse(Duration.zero);
        expect(cancelled, isTrue);
      });
    });
  });

  group('the clipboard', () {
    test('is read only once it changed, and a song link on it is offered '
        'once', () async {
      final harness = await _Harness.create();
      harness.links.answers
        ..[neteaseShareText] = _song
        ..['https://b23.tv/xyz'] = _bilibiliLink;
      harness.clipboard.copy(neteaseShareText);
      await harness.enter('listen', RoomKind.ephemeral);

      var page = await harness.openSearch();
      expect(page.read()?.track?.id, '186016');
      expect(harness.clipboard.reads, 1);

      await harness.closeSearch(page);
      page = await harness.openSearch();
      expect(page.read(), isNull);
      expect(harness.clipboard.reads, 1, reason: 'the clipboard is the same');

      harness.clipboard.copy(neteaseShareText);
      await harness.closeSearch(page);
      page = await harness.openSearch();
      expect(harness.clipboard.reads, 2);
      expect(page.read(), isNull, reason: 'the same text was offered');

      harness.clipboard.copy('https://b23.tv/xyz');
      await harness.closeSearch(page);
      page = await harness.openSearch();
      expect(page.read()?.link, 'https://b23.tv/xyz');

      harness.container
          .read(clipboardLinkControllerProvider.notifier)
          .dismiss();
      expect(page.read(), isNull);
    });

    test('is never read where it carries no stamp, as on iOS', () async {
      final harness = await _Harness.create();
      harness.links.answers[neteaseShareText] = _song;
      harness.clipboard
        ..copy(neteaseShareText)
        ..stamped = false;
      await harness.enter('listen', RoomKind.ephemeral);

      final page = await harness.openSearch();

      expect(harness.clipboard.reads, 0);
      expect(page.read(), isNull);
    });

    test('offers nothing the room cannot take, and offers what was read, '
        'without reading it again, once the room can', () async {
      final harness = await _Harness.create();
      harness.links.answers
        ..['https://example.com/a.mp3'] = _webLink
        ..['https://music.163.com/#/playlist?id=1'] = _playlist
        ..['没有链接'] = null;
      await harness.enter('listen', RoomKind.ephemeral);

      for (final text in [
        'https://music.163.com/#/playlist?id=1',
        '没有链接',
        'https://example.com/a.mp3',
      ]) {
        harness.clipboard.copy(text);
        final page = await harness.openSearch();
        expect(page.read(), isNull, reason: text);
        await harness.closeSearch(page);
      }
      final reads = harness.clipboard.reads;
      var page = await harness.openSearch();
      expect(page.read(), isNull);
      expect(
        harness.clipboard.reads,
        reads,
        reason: 'the clipboard is the same',
      );
      await harness.closeSearch(page);

      await harness.enter('always', RoomKind.persistent);
      page = await harness.openSearch();
      expect(page.read()?.link, 'https://example.com/a.mp3');
      expect(harness.clipboard.reads, reads);
      await harness.closeSearch(page);

      page = await harness.openSearch();
      expect(page.read(), isNull, reason: 'offered once');
    });

    test('holds a link while the room is not known yet, and offers a song '
        'at once', () async {
      final harness = await _Harness.create();
      harness.links.answers
        ..['https://example.com/a.mp3'] = _webLink
        ..[neteaseShareText] = _song;
      harness.clipboard.copy('https://example.com/a.mp3');
      await harness.container
          .read(roomControllerProvider.notifier)
          .openRoom('always');
      await pumpEventQueue();

      var page = await harness.openSearch();
      expect(page.read(), isNull);
      expect(harness.clipboard.reads, 1);
      await harness.closeSearch(page);

      harness.hello('always', RoomKind.persistent);
      await pumpEventQueue();
      page = await harness.openSearch();
      expect(page.read()?.link, 'https://example.com/a.mp3');
      expect(harness.clipboard.reads, 1, reason: 'judged from what was read');
      await harness.closeSearch(page);

      await harness.container.read(roomControllerProvider.notifier).leaveRoom();
      await harness.container
          .read(roomControllerProvider.notifier)
          .openRoom('listen');
      await pumpEventQueue();
      harness.clipboard.copy(neteaseShareText);
      page = await harness.openSearch();
      expect(page.read()?.track?.id, '186016');
    });

    test('is read again when song search closed before showing what it '
        'held', () async {
      final harness = await _Harness.create();
      harness.links
        ..answers[neteaseShareText] = _song
        ..hold = true;
      harness.clipboard.copy(neteaseShareText);
      await harness.enter('listen', RoomKind.ephemeral);
      final container = harness.container;

      final first = container.listen(
        clipboardLinkControllerProvider,
        (_, _) {},
      );
      final checking = container
          .read(clipboardLinkControllerProvider.notifier)
          .check();
      await pumpEventQueue();
      await harness.closeSearch(first);
      harness.links.release(neteaseShareText);
      await checking;

      harness.links.hold = false;
      final page = await harness.openSearch();
      expect(harness.clipboard.reads, 2);
      expect(page.read()?.track?.id, '186016');
    });
  });
}
