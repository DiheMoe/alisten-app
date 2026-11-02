import 'dart:async';

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/server/invite_link.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/invite_link.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/search/data/link_resolver.dart';
import 'package:alisten/features/server/index.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';
import '../share_test_doubles.dart';

const _fiveSeconds = Duration(seconds: 5);

InviteLink _link(String link) => parseInviteLink(link, allowCleartext: false)!;

void main() {
  late FakeServerProbe probe;
  late FakeRoomTransportFactory rooms;
  late ProviderContainer container;

  setUp(() {
    probe = FakeServerProbe();
    rooms = FakeRoomTransportFactory();
  });

  /// 默认服务器为当前服务器，另已保存 [serverB]；房间 `listen` 在默认服务器上。
  Future<void> open({BuildEnvironment? environment}) async {
    final credentials = FakeCredentialStores();
    credentials((environment ?? testEnvironment).defaultServerId)
            .tickets['room-id'] =
        'ticket';
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: credentials,
      api: FakeAlistenApi()..rooms = [roomListing()],
      rooms: rooms,
      environment: environment,
      extra: [
        serverProbeProvider.overrideWithValue(probe),
        linkResolverProvider.overrideWithValue(
          DioLinkResolver(Dio()..httpClientAdapter = FakeUrlHttpAdapter()),
        ),
        serverNowProvider.overrideWithValue(() => 42),
      ],
    );
  }

  Future<InviteTarget?> recognize(String text) =>
      container.read(inviteRecognizerProvider).recognize(text);

  test('a room on the current server is opened as it is, without asking '
      'any server', () async {
    await open();

    final target = await recognize('https://livehouse.dihe.moe/r/listen');

    expect(
      target,
      isA<InviteToCurrent>()
          .having((t) => t.route, 'route', '/r/listen')
          .having((t) => t.isActiveRoom, 'isActiveRoom', isFalse),
    );
    expect(probe.siteProbed, isEmpty);
    expect(probe.probed, isEmpty);
  });

  test('the room already entered is told apart', () async {
    await open();
    await container.read(roomControllerProvider.notifier).openRoom('listen');
    rooms.last.emitHello();
    await pumpEventQueue();

    final target = await recognize('https://livehouse.dihe.moe/r/listen');

    expect(
      target,
      isA<InviteToCurrent>().having(
        (t) => t.isActiveRoom,
        'isActiveRoom',
        isTrue,
      ),
    );
  });

  test('a room on a saved server, found anywhere in the text, is offered '
      'with that server and not probed', () async {
    await open();

    final target = await recognize(
      '分享房间 https://example.com:8443/r/abc/chat 快来',
    );

    expect(
      target,
      isA<InviteToSaved>()
          .having((t) => t.server, 'server', serverB)
          .having((t) => t.route, 'route', '/r/abc/chat'),
    );
    expect(probe.siteProbed, isEmpty);
  });

  test('a room on a server not saved is offered once its site says it is '
      'Alisten, asking the site alone for five seconds at most', () async {
    await open();
    probe.siteResults['https://new.example.org'] = const ProbeSucceeded(
      origin: 'https://new.example.org',
      brandName: '新站',
    );

    final target = await recognize('https://new.example.org/r/party');

    expect(target, isA<InviteToNew>());
    final server = (target! as InviteToNew).server;
    expect(server.origin, 'https://new.example.org');
    expect(server.brandName, '新站');
    expect(server.addedAtMs, 42);
    expect(target.route, '/r/party');
    expect(probe.siteProbed, [('https://new.example.org', _fiveSeconds)]);
    expect(probe.handshakes, isEmpty, reason: 'only once the user agrees');
    expect(probe.probed, isEmpty);
    expect(
      container.read(serverDirectoryProvider).byId(server.id),
      isNull,
      reason: 'nothing is saved before the user agrees',
    );
  });

  test('a website that is not Alisten is no room', () async {
    await open();
    probe.siteResults['https://www.reddit.com'] = const ProbeFailed(
      ProbeFailure.notAlisten,
    );

    final target = await recognize('https://www.reddit.com/r/flutterdev');

    expect(target, isNull);
    expect(probe.siteProbed, [('https://www.reddit.com', _fiveSeconds)]);
  });

  test('a site that cannot be reached is no room', () async {
    await open();

    expect(await recognize('https://down.example.org/r/party'), isNull);
    expect(probe.siteProbed, [('https://down.example.org', _fiveSeconds)]);
  });

  test('links that cannot be a room are not probed', () async {
    await open();

    for (final text in [
      'https://www.reddit.com/r/FlutterDev',
      'https://music.163.com/song?id=186016',
      'http://new.example.org/r/party',
      '没有链接',
    ]) {
      expect(await recognize(text), isNull, reason: text);
    }
    expect(probe.siteProbed, isEmpty);
  });

  test('the current server is told by the host of its website', () async {
    await open(
      environment: BuildEnvironment(
        defaultOrigin: 'https://api.example.com',
        defaultLinkHost: 'example.com',
        isRelease: false,
      ),
    );

    final target = await recognize('https://example.com/r/x');

    expect(
      target,
      isA<InviteToCurrent>().having((t) => t.route, 'route', '/r/x'),
    );
    expect(probe.siteProbed, isEmpty);
  });

  group('the website host of the default server', () {
    final split = BuildEnvironment(
      defaultOrigin: 'https://api.example.com',
      defaultLinkHost: 'example.com',
      isRelease: false,
    );

    test('and its API host both name the default server', () async {
      await open(environment: split);

      for (final link in [
        'https://example.com/r/x',
        'https://api.example.com/r/x',
      ]) {
        expect(
          await recognize(link),
          isA<InviteToCurrent>().having((t) => t.route, 'route', '/r/x'),
          reason: link,
        );
      }
      expect(probe.siteProbed, isEmpty);
    });

    test('name the default server while another is current', () async {
      await open(environment: split);
      await container
          .read(serverDirectoryProvider.notifier)
          .setCurrent(serverB.id);
      final defaultId = split.defaultServerId;

      for (final link in [
        'https://example.com/r/x',
        'https://api.example.com/r/x',
      ]) {
        expect(
          await recognize(link),
          isA<InviteToSaved>().having((t) => t.server.id, 'server', defaultId),
          reason: link,
        );
      }
      expect(probe.siteProbed, isEmpty);
    });
  });

  group('an invite told again', () {
    Future<InviteTarget?> refresh(InviteTarget target) =>
        container.read(inviteRecognizerProvider).refresh(target);

    test(
      'after the current server changed is on the server it was on',
      () async {
        await open();
        final found = await recognize('https://livehouse.dihe.moe/r/listen');
        expect(found, isA<InviteToCurrent>());

        await container
            .read(serverDirectoryProvider.notifier)
            .setCurrent(serverB.id);

        expect(
          await refresh(found!),
          isA<InviteToSaved>()
              .having(
                (t) => t.server.id,
                'server',
                testEnvironment.defaultServerId,
              )
              .having((t) => t.route, 'route', '/r/listen'),
        );
      },
    );

    test('of a server saved since is a saved one, or the current one once '
        'switched to', () async {
      await open();
      probe.siteResults['https://new.example.org'] = const ProbeSucceeded(
        origin: 'https://new.example.org',
        brandName: '新站',
      );
      final found = (await recognize('https://new.example.org/r/party'))!;
      expect(await refresh(found), same(found), reason: 'still not saved');
      final directory = container.read(serverDirectoryProvider.notifier);

      final saved = await directory.add((found as InviteToNew).server);
      expect(
        await refresh(found),
        isA<InviteToSaved>().having((t) => t.server, 'server', saved),
      );

      await directory.setCurrent(saved.id);
      expect(
        await refresh(found),
        isA<InviteToCurrent>().having((t) => t.route, 'route', '/r/party'),
      );
      expect(probe.siteProbed, hasLength(1), reason: 'asked only once');
    });

    test('of a saved server deleted since is a server to add', () async {
      await open();
      final found = (await recognize('https://example.com:8443/r/abc'))!;
      expect(found, isA<InviteToSaved>());

      await container.read(serverDirectoryProvider.notifier).remove(serverB.id);

      expect(
        await refresh(found),
        isA<InviteToNew>()
            .having((t) => t.server.origin, 'origin', serverB.origin)
            .having((t) => t.route, 'route', '/r/abc'),
      );
    });
  });

  test('asking a site stops when told to', () async {
    await open();
    final stop = Completer<void>();

    await container
        .read(inviteRecognizerProvider)
        .recognize('https://down.example.org/r/party', cancel: stop.future);

    expect(probe.siteCancels, [same(stop.future)]);
  });

  group('an offer', () {
    test('of the room already entered is not made', () async {
      await open();
      final offers = container.read(inviteOfferControllerProvider.notifier);

      offers.offer(
        InviteToCurrent(
          link: _link('https://livehouse.dihe.moe/r/x'),
          isActiveRoom: true,
        ),
      );

      expect(container.read(inviteOfferControllerProvider), isNull);
    });

    test('is a new one each time, and is let go only by its own id', () async {
      await open();
      final offers = container.read(inviteOfferControllerProvider.notifier);
      final target = InviteToCurrent(
        link: _link('https://livehouse.dihe.moe/r/x'),
        isActiveRoom: false,
      );

      offers.offer(target);
      final first = container.read(inviteOfferControllerProvider)!;
      expect(first.target, same(target));
      offers.offer(target);
      final second = container.read(inviteOfferControllerProvider)!;
      expect(second.id, isNot(first.id));

      offers.dismiss(first.id);
      expect(container.read(inviteOfferControllerProvider), same(second));
      offers.dismiss(second.id);
      expect(container.read(inviteOfferControllerProvider), isNull);
    });
  });
}
