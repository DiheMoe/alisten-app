import 'package:alisten/core/api/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('the backend URL is normalized to its origin and identified by '
        'it', () {
      final config = AppConfig(
        baseUrl: 'https://Example.COM:443/',
        isRelease: true,
      );

      expect(config.baseUrl, 'https://example.com');
      expect(config.serverId, '837b2b5793a240b3');
      expect(config.linkHost, 'example.com');
    });

    test('links default to the host and its non-default port', () {
      final config = AppConfig(
        baseUrl: 'https://example.com:8443',
        isRelease: true,
      );

      expect(config.linkHost, 'example.com:8443');
      expect(config.inviteLinkFor('hall'), 'https://example.com:8443/r/hall');
    });

    test('a shared playlist link is on the same site as invites', () {
      final config = AppConfig(
        baseUrl: 'https://example.com:8443',
        isRelease: true,
      );

      expect(
        config.sharedPlaylistLinkFor('AbCdEfGhIjKlMnOpQrStUv'),
        'https://example.com:8443/s/AbCdEfGhIjKlMnOpQrStUv',
      );
      expect(
        AppConfig(
          baseUrl: 'https://api.example.com',
          isRelease: true,
          linkHost: 'listen.example.com',
        ).sharedPlaylistLinkFor('AbCdEfGhIjKlMnOpQrStUv'),
        'https://listen.example.com/s/AbCdEfGhIjKlMnOpQrStUv',
      );
    });

    test(
      'an empty link host is rejected instead of producing hostless links',
      () {
        expect(
          () =>
              AppConfig(baseUrl: 'https://a.b', isRelease: true, linkHost: ''),
          throwsArgumentError,
        );
      },
    );

    // Android 匹配清单中的主机名时区分大小写，build.gradle.kts 因此将其转为
    // 小写；Dart 必须得出完全相同的主机名。
    test('the link host is trimmed and lowercased', () {
      final config = AppConfig(
        baseUrl: 'https://a.b',
        isRelease: true,
        linkHost: ' Example.COM ',
      );

      expect(config.linkHost, 'example.com');
    });

    test(
      'the backend URL must be an origin without path, query or fragment',
      () {
        for (final baseUrl in [
          'https://a.b/api',
          'https://a.b?x=1',
          'https://a.b#top',
        ]) {
          expect(
            () => AppConfig(baseUrl: baseUrl, isRelease: true),
            throwsArgumentError,
            reason: baseUrl,
          );
        }
        expect(
          AppConfig(baseUrl: 'https://a.b/', isRelease: true).linkHost,
          'a.b',
        );
      },
    );

    test('debug accepts the local HTTP backend only with explicit opt-in', () {
      final config = AppConfig(
        baseUrl: 'http://localhost:9876',
        isRelease: false,
        allowCleartext: true,
      );

      expect(config.baseUrl, 'http://localhost:9876');
    });

    test('debug rejects HTTP when cleartext was not explicitly allowed', () {
      expect(
        () => AppConfig(baseUrl: 'http://localhost:9876', isRelease: false),
        throwsArgumentError,
      );
    });

    test('release rejects HTTP even when a cleartext override is present', () {
      expect(
        () => AppConfig(
          baseUrl: 'http://localhost:9876',
          isRelease: true,
          allowCleartext: true,
        ),
        throwsArgumentError,
      );
    });

    test('release accepts HTTPS without a cleartext override', () {
      final config = AppConfig(
        baseUrl: 'https://listen.example.com',
        isRelease: true,
      );

      expect(config.baseUrl, 'https://listen.example.com');
    });

    test('rejects non-HTTP backend schemes', () {
      expect(
        () => AppConfig(
          baseUrl: 'ws://localhost:9876',
          isRelease: false,
          allowCleartext: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a port that does not fit in an int', () {
      expect(
        () => AppConfig(
          baseUrl: 'https://a.com:99999999999999999999',
          isRelease: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('BuildEnvironment', () {
    test('fromEnvironment defaults to the secure backend in debug', () {
      final environment = BuildEnvironment.fromEnvironment();

      expect(environment.defaultOrigin, 'https://livehouse.dihe.moe');
      expect(environment.defaultLinkHost, 'livehouse.dihe.moe');
      expect(environment.isRelease, isFalse);
      expect(
        environment.configFor(environment.defaultOrigin).baseUrl,
        'https://livehouse.dihe.moe',
      );
    });

    test('the default server is identified by its origin', () {
      final environment = BuildEnvironment(
        defaultOrigin: 'https://livehouse.dihe.moe',
        isRelease: true,
      );

      expect(environment.defaultServerId, 'fcd7a878032db68b');
    });

    test('only the default server uses the configured link host', () {
      final environment = BuildEnvironment(
        defaultOrigin: 'https://api.example.com',
        defaultLinkHost: 'Example.com',
        isRelease: true,
      );

      expect(
        environment.configFor('https://api.example.com').linkHost,
        'example.com',
      );
      expect(
        environment.configFor('https://example.com:8443').linkHost,
        'example.com:8443',
      );
    });

    test('cleartext servers are allowed only in debug with the opt-in', () {
      expect(
        BuildEnvironment(
          defaultOrigin: 'https://a.b',
          isRelease: false,
          allowCleartext: true,
        ).allowsCleartextServers,
        isTrue,
      );
      expect(
        BuildEnvironment(
          defaultOrigin: 'https://a.b',
          isRelease: true,
          allowCleartext: true,
        ).allowsCleartextServers,
        isFalse,
      );
      expect(
        BuildEnvironment(
          defaultOrigin: 'https://a.b',
          isRelease: false,
        ).allowsCleartextServers,
        isFalse,
      );
    });
  });
}
