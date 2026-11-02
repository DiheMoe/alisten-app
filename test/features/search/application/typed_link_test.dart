import 'dart:async';

import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/application/invite_link.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/search/data/link_resolver.dart';
import 'package:alisten/features/server/index.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../share_test_doubles.dart';

const _saved = 'https://example.com:8443/r/abc';
const _party = 'https://new.example.org/r/party';

void main() {
  late FakeServerProbe probe;
  late List<Override> overrides;

  setUp(() async {
    probe = FakeServerProbe()
      ..siteResults['https://new.example.org'] = const ProbeSucceeded(
        origin: 'https://new.example.org',
        brandName: '新站',
      );
    overrides = [
      ...await switchingOverrides(
        store: FakeServerStore(profiles: [serverB]),
        credentials: FakeCredentialStores(),
      ),
      serverProbeProvider.overrideWithValue(probe),
      linkResolverProvider.overrideWithValue(
        DioLinkResolver(Dio()..httpClientAdapter = FakeUrlHttpAdapter()),
      ),
    ];
  });

  ProviderContainer typing() {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  test('a room link typed is still being told, not a link to pick, until '
      'typing pauses and it turns out a room link and an invite', () {
    fakeAsync((async) {
      final container = typing();
      ResolvedShare? typed() => container.read(typedLinkProvider(_saved));

      container.listen(typedLinkProvider(_saved), (_, _) {});
      expect(typed()?.link, _saved);
      expect(typed()?.platform, LinkPlatform.web);
      expect(typed()?.unfollowed, isTrue);
      expect(typed()?.track, isNull);

      async.elapse(const Duration(milliseconds: 399));
      async.flushMicrotasks();
      expect(container.read(inviteOfferControllerProvider), isNull);
      expect(typed()?.unfollowed, isTrue);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(
        container.read(inviteOfferControllerProvider)?.target,
        isA<InviteToSaved>()
            .having((t) => t.server, 'server', serverB)
            .having((t) => t.route, 'route', '/r/abc'),
      );
      expect(typed()?.link, _saved);
      expect(typed()?.unfollowed, isFalse);
      expect(typed()?.problem, LinkProblem.roomLink);
      expect(typed()?.track, isNull);
      expect(typed()?.otherRoom, isNull);
      expect(unpickableReason(typed()!, null), '这是房间链接，不能用来点歌。');
    });
  });

  test('a room link typed over before typing pauses is no invite', () {
    fakeAsync((async) {
      final container = typing();

      final field = container.listen(typedLinkProvider(_saved), (_, _) {});
      async.elapse(const Duration(milliseconds: 399));
      field.close();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(container.read(inviteOfferControllerProvider), isNull);
    });
  });

  test('a server still being asked when the link is typed over is not '
      'offered', () {
    fakeAsync((async) {
      final container = typing();
      probe.gate = Completer();

      final field = container.listen(typedLinkProvider(_party), (_, _) {});
      async.elapse(const Duration(milliseconds: 400));
      async.flushMicrotasks();
      expect(probe.siteProbed, [
        ('https://new.example.org', const Duration(seconds: 5)),
      ]);
      var stopped = false;
      unawaited(probe.siteCancels.single!.then((_) => stopped = true));
      async.flushMicrotasks();
      expect(stopped, isFalse);

      field.close();
      async.elapse(Duration.zero);
      expect(stopped, isTrue, reason: 'the request to the site is cancelled');
      probe.gate!.complete();
      async.flushMicrotasks();

      expect(container.read(inviteOfferControllerProvider), isNull);
    });
  });

  test('a room link on a website that is not Alisten stays a link', () {
    fakeAsync((async) {
      final container = typing();
      const reddit = 'https://www.reddit.com/r/flutterdev';
      probe.siteResults['https://www.reddit.com'] = const ProbeFailed(
        ProbeFailure.notAlisten,
      );

      container.listen(typedLinkProvider(reddit), (_, _) {});
      expect(container.read(typedLinkProvider(reddit))?.unfollowed, isTrue);
      async.elapse(const Duration(milliseconds: 400));
      async.flushMicrotasks();

      expect(probe.siteProbed, hasLength(1));
      expect(container.read(inviteOfferControllerProvider), isNull);
      final typed = container.read(typedLinkProvider(reddit));
      expect(typed?.link, reddit);
      expect(typed?.unfollowed, isFalse);
      expect(typed?.track?.source, TrackSource.link);
    });
  });

  test('a link that cannot be a room asks no server', () {
    fakeAsync((async) {
      final container = typing();
      const song = 'https://music.163.com/song?id=186016';

      container.listen(typedLinkProvider(song), (_, _) {});
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(probe.siteProbed, isEmpty);
      expect(container.read(typedLinkProvider(song))?.track?.id, '186016');
    });
  });
}
