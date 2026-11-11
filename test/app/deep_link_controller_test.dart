import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import 'app_test_harness.dart';

AppConfig _config(String baseUrl) =>
    AppConfig(baseUrl: baseUrl, isRelease: true);

void main() {
  final listen = _config('https://listen.example');

  test('validates hosts and room subroutes', () {
    final controller = DeepLinkController(config: () => listen);

    expect(
      controller.routeFor(Uri.parse('https://listen.example/r/room-id/queue')),
      '/r/room-id/queue',
    );
    expect(
      controller.routeFor(Uri.parse('https://listen.example/r/alias/chat')),
      '/r/alias/chat',
    );
    expect(
      controller.routeFor(
        Uri.parse('https://listen.example/r/alias/playlists/netease/123'),
      ),
      '/r/alias/playlists/netease/123',
    );
    expect(
      controller.routeFor(Uri.parse('https://evil.example/r/room-id')),
      isNull,
    );
    expect(
      controller.routeFor(Uri.parse('https://listen.example/admin')),
      isNull,
    );
    expect(
      controller.routeFor(
        Uri.parse('https://listen.example/r/alias/playlists/qq/123'),
      ),
      isNull,
    );
    expect(
      controller.routeFor(Uri.parse('https://user@listen.example/r/x')),
      isNull,
    );
  });

  test('a link host with a port only accepts links on that port', () {
    final controller = DeepLinkController(
      config: () => _config('https://example.com:8443'),
    );

    expect(controller.host, 'example.com:8443');
    expect(
      controller.routeFor(Uri.parse('https://example.com:8443/r/abc')),
      '/r/abc',
    );
    expect(controller.routeFor(Uri.parse('https://example.com/r/abc')), isNull);
    expect(
      controller.routeFor(Uri.parse('https://example.com:9443/r/abc')),
      isNull,
    );
  });

  test('an invite link is a link the app opens', () {
    for (final baseUrl in [
      'https://listen.example',
      'https://example.com:8443',
    ]) {
      final controller = DeepLinkController(config: () => _config(baseUrl));

      expect(
        controller.routeFor(Uri.parse(controller.inviteLinkForRef('abc'))),
        '/r/abc',
        reason: baseUrl,
      );
    }
  });

  test('the host is read from the configuration of the moment', () {
    var config = listen;
    final controller = DeepLinkController(config: () => config);

    config = _config('https://example.com:8443');

    expect(controller.host, 'example.com:8443');
    expect(
      controller.inviteLinkForRef('abc'),
      'https://example.com:8443/r/abc',
    );
    expect(
      controller.routeFor(Uri.parse('https://listen.example/r/abc')),
      isNull,
    );
  });

  test(
    'rejects malformed room references and unsafe encoded path segments',
    () {
      final controller = DeepLinkController(config: () => listen);
      final uuid = '123e4567-e89b-42d3-a456-426614174000';

      expect(
        controller.routeFor(Uri.parse('https://listen.example/r/$uuid')),
        '/r/$uuid',
      );
      for (final ref in ['bad_slug', 'bad%2Fslug', 'bad%20slug', '../secret']) {
        expect(
          controller.routeFor(Uri.parse('https://listen.example/r/$ref')),
          isNull,
        );
      }
    },
  );

  test('the link that launched the app is followed once, like later '
      'links', () async {
    // app_links 也会把启动链接投递给第一个监听者。
    final source = FakeAppLinkSource(
      initial: Uri.parse('https://listen.example/r/initial'),
    );
    final controller = DeepLinkController(config: () => listen, source: source);
    final routes = <String>[];

    final launched = await controller.start(routes.add);
    await pumpEventQueue();
    source.open(Uri.parse('https://listen.example/r/live/chat'));
    await pumpEventQueue();

    expect(routes, ['/r/initial', '/r/live/chat']);
    // 返回 true 时，启动流程不会同时进入上次的房间。
    expect(launched, isTrue);
  });

  test('a room link of another server is handed on as it is, and other '
      'links are invalid', () async {
    final source = FakeAppLinkSource();
    final controller = DeepLinkController(
      config: () => _config('https://example.com:8443'),
      source: source,
    );
    final routes = <String>[];
    final others = <Uri>[];
    var invalid = 0;

    await controller.start(
      routes.add,
      onInvalid: () => invalid++,
      onOtherServer: others.add,
    );
    source.open(Uri.parse('https://livehouse.dihe.moe/r/listen'));
    await pumpEventQueue();

    expect(others, [Uri.parse('https://livehouse.dihe.moe/r/listen')]);
    expect(invalid, 0);
    expect(routes, isEmpty);

    for (final link in [
      'https://livehouse.dihe.moe/about',
      'https://livehouse.dihe.moe/r/FlutterDev',
      'http://livehouse.dihe.moe/r/listen',
    ]) {
      source.open(Uri.parse(link));
    }
    await pumpEventQueue();

    expect(invalid, 3);
    expect(others, hasLength(1));
  });

  test('the app launched by a room link of another server is entering that '
      'room', () async {
    final source = FakeAppLinkSource(
      initial: Uri.parse('https://livehouse.dihe.moe/r/listen'),
    );
    final controller = DeepLinkController(
      config: () => _config('https://example.com:8443'),
      source: source,
    );
    final others = <Uri>[];

    final launched = await controller.start((_) {}, onOtherServer: others.add);
    await pumpEventQueue();

    expect(launched, isTrue);
    expect(others, [Uri.parse('https://livehouse.dihe.moe/r/listen')]);
  });

  test('a mixed-case configured link host still accepts its links', () {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            baseUrl: 'https://a.b',
            isRelease: true,
            linkHost: 'Example.COM',
          ),
        ),
        appLinkSourceProvider.overrideWithValue(FakeAppLinkSource()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(deepLinkControllerProvider);

    expect(controller.routeFor(Uri.parse('https://example.com/r/x')), '/r/x');
    expect(controller.routeFor(Uri.parse('https://Example.COM/r/x')), '/r/x');
    expect(controller.routeFor(Uri.parse('https://evil.example/r/x')), isNull);
  });

  test('invite link uses the alias, the id only without one, and never '
      'includes a password', () {
    final controller = DeepLinkController(config: () => listen);
    final room = roomListing(slug: 'music', hasPassword: true);

    final link = controller.inviteLink(id: room.id, slug: room.slug);

    expect(link, 'https://listen.example/r/music');
    expect(link.contains('password'), isFalse);
    expect(link.contains('secret'), isFalse);
    expect(
      controller.inviteLink(id: testRoomId, slug: null),
      'https://listen.example/r/$testRoomId',
    );
  });

  test('a pairing link is https to /pair, its fragment kept apart', () {
    final controller = DeepLinkController(config: () => listen);

    expect(controller.pairLinkFor(Uri.parse('https://listen.example/pair#X')), (
      authority: 'listen.example',
      fragment: 'X',
    ));
    expect(
      controller.pairLinkFor(Uri.parse('http://listen.example/pair#X')),
      isNull,
    );
    expect(
      controller.pairLinkFor(Uri.parse('https://listen.example/pair/x#X')),
      isNull,
    );
    expect(
      controller.pairLinkFor(Uri.parse('https://listen.example/r/pair')),
      isNull,
    );
  });

  test('a pairing link of this server hands on its fragment, and one of '
      'another server only its authority', () async {
    final source = FakeAppLinkSource();
    final controller = DeepLinkController(
      config: () => _config('https://example.com:8443'),
      source: source,
    );
    final pairs = <String>[];
    final others = <String>[];
    var invalid = 0;

    await controller.start(
      (_) {},
      onInvalid: () => invalid++,
      onPair: pairs.add,
      onOtherServerPair: others.add,
    );
    source
      ..open(Uri.parse('https://example.com:8443/pair#abcd-2345'))
      ..open(Uri.parse('https://other.example/pair#ABCD2345'))
      ..open(Uri.parse('https://example.com:8443/pair'));
    await pumpEventQueue();

    expect(pairs, ['abcd-2345', '']);
    expect(others, ['other.example']);
    expect(invalid, 0);
  });

  test('the same host on another port is another server', () async {
    final source = FakeAppLinkSource();
    final controller = DeepLinkController(
      config: () => _config('https://example.com:8443'),
      source: source,
    );
    final pairs = <String>[];
    final others = <String>[];
    await controller.start(
      (_) {},
      onPair: pairs.add,
      onOtherServerPair: others.add,
    );

    source.open(Uri.parse('https://example.com/pair#X'));
    await pumpEventQueue();

    expect(pairs, isEmpty);
    expect(others, ['example.com']);
  });

  test(
    'a pairing link with user info is no pairing link and is invalid',
    () async {
      final source = FakeAppLinkSource();
      final controller = DeepLinkController(
        config: () => listen,
        source: source,
      );
      final pairs = <String>[];
      var invalid = 0;
      await controller.start(
        (_) {},
        onInvalid: () => invalid++,
        onPair: pairs.add,
      );

      final uri = Uri.parse('https://user@listen.example/pair#ABCD2345');
      source.open(uri);
      await pumpEventQueue();

      expect(controller.pairLinkFor(uri), isNull);
      expect(pairs, isEmpty);
      expect(invalid, 1);
    },
  );

  test('the fragment is handed on as it is, decoded only by the page', () {
    final controller = DeepLinkController(config: () => listen);

    expect(
      controller
          .pairLinkFor(Uri.parse('https://listen.example/pair#ABCD%202345'))
          ?.fragment,
      'ABCD%202345',
    );
  });

  test('a pairing link that launches the app is not a room launch', () async {
    final source = FakeAppLinkSource(
      initial: Uri.parse('https://listen.example/pair#ABCD2345'),
    );
    final controller = DeepLinkController(config: () => listen, source: source);
    final pairs = <String>[];

    final launched = await controller.start((_) {}, onPair: pairs.add);
    await pumpEventQueue();

    expect(launched, isFalse);
    expect(pairs, ['ABCD2345']);
  });

  test(
    'the GitHub callback scheme is left to the auth plugin, silently',
    () async {
      final source = FakeAppLinkSource();
      final controller = DeepLinkController(
        config: () => listen,
        source: source,
      );
      var invalid = 0;
      final routes = <String>[];

      await controller.start(routes.add, onInvalid: () => invalid++);
      source.open(Uri.parse('moe.dihe.alisten:/auth/github?code=x'));
      await pumpEventQueue();

      expect(invalid, 0);
      expect(routes, isEmpty);
    },
  );
}
