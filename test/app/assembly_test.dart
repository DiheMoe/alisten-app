import 'dart:convert';
import 'dart:io';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/app_theme.dart';
import 'package:alisten/app/app_version.dart';
import 'package:alisten/app/assembly.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/avatar/avatar_image.dart';
import 'package:alisten/core/avatar/disk_avatar_cache.dart';
import 'package:alisten/core/cache/cached_cover_image.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/cache/disk_cover_cache.dart';
import 'package:alisten/core/realtime/websocket_room_transport.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/release/release_version.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/admin/data/dio_qr_image_loader.dart';
import 'package:alisten/features/admin/data/gal_image_gallery.dart';
import 'package:alisten/features/admin/data/platform_sensitive_clipboard.dart';
import 'package:alisten/features/admin/data/rest_admin_api.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/history/data/share_history_exporter.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/data/alisten_server_probe.dart';
import 'package:alisten/features/server/data/server_data_sweep.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/features/update/data/github_release_source.dart';
import 'package:alisten/features/update/data/platform_release_opener.dart';
import 'package:alisten/features/update/data/preferences_update_store.dart';
import 'package:alisten/features/update/index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/fake_http_adapter.dart';
import '../core/avatar/avatar_test_doubles.dart';
import '../core/cache/cover_cache_test_doubles.dart';
import '../core/realtime/fake_web_socket_channel.dart';
import '../features/admin/admin_test_doubles.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/playback/playback_test_doubles.dart' show FakeAudioEngine;
import '../features/server/server_test_doubles.dart';
import 'app_test_harness.dart' show FakeAppLinkSource, FakeNotificationGateway;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> wired([
    Map<String, Object> stored = const {},
    List<Override> adapters = const [],
  ]) async {
    final container = ProviderContainer(
      overrides: [...alistenWiring(await loadPreferences(stored)), ...adapters],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the platform adapters compose the configured API, the platform '
      'stores and WebSocket rooms', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final container = await wired(
      {},
      platformAdapters(audioEngine: FakeAudioEngine()),
    );

    expect(
      container.read(credentialStoreProvider),
      isA<SecureCredentialStore>().having(
        (store) => store.serverId,
        'serverId',
        'fcd7a878032db68b',
      ),
    );
    expect(container.read(alistenApiProvider), isA<RestAlistenApi>());
    expect(
      container.read(roomTransportFactoryProvider)('room-id', 'ticket'),
      isA<WebSocketRoomTransport>(),
    );
    expect(container.read(coverCacheProvider), isA<DiskCoverCache>());
    expect(container.read(avatarCacheProvider), isA<DiskAvatarCache>());
    expect(
      container.read(historyExporterProvider),
      isA<ShareHistoryExporter>(),
    );
    expect(container.read(serverProbeProvider), isA<AlistenServerProbe>());
    expect(container.read(adminApiProvider), isA<RestAdminApi>());
    expect(
      container.read(sensitiveClipboardProvider),
      isA<PlatformSensitiveClipboard>(),
    );
    expect(container.read(qrImageLoaderProvider), isA<DioQrImageLoader>());
    expect(container.read(imageGalleryProvider), isA<GalImageGallery>());
    expect(container.read(releaseSourceProvider), isA<GitHubReleaseSource>());
    expect(container.read(releaseOpenerProvider), isA<PlatformReleaseOpener>());
  });

  test('update checks keep their time and skipped version in the ordinary '
      'preferences, and compare releases with the version built', () async {
    final container = await wired();

    expect(container.read(updateStoreProvider), isA<PreferencesUpdateStore>());
    expect(
      container.read(installedVersionProvider),
      ReleaseVersion.fromAppVersion(appVersion),
    );
    // 发布源属于平台适配器，共用接线不得自带会联网的实现。
    expect(() => container.read(releaseSourceProvider), throwsA(anything));
  });

  test('the shared wiring ends the site admin session when asked', () async {
    final container = await wired({}, [
      adminApiProvider.overrideWithValue(FakeAdminApi()),
    ]);
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    expect(container.read(adminSessionProvider).active, isTrue);

    container.read(endAdminSessionProvider)();

    expect(container.read(adminSessionProvider).active, isFalse);
  });

  test('the last room is kept under the default server', () async {
    final container = await wired();

    await container.read(lastRoomStoreProvider).write('listen');

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('alisten.last-room@fcd7a878032db68b'),
      'listen',
    );
    expect(preferences.containsKey('alisten.last-room'), isFalse);
  });

  test('the configured build environment decides the server whose '
      'credentials are used', () async {
    final requested = <String>[];
    final credentials = FakeCredentialStore();
    final container = ProviderContainer(
      overrides: [
        ...alistenWiring(
          await loadPreferences(),
          environment: BuildEnvironment(
            defaultOrigin: 'https://Example.com/',
            isRelease: true,
          ),
        ),
        ...platformAdapters(
          audioEngine: FakeAudioEngine(),
          credentialStores: (serverId) {
            requested.add(serverId);
            return credentials;
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appConfigProvider).baseUrl, 'https://example.com');
    expect(container.read(credentialStoreProvider), same(credentials));
    expect(requested, ['837b2b5793a240b3']);
  });

  group('the current server', () {
    late FakeCredentialStores stores;

    Future<ProviderContainer> switchable([
      Map<String, Object> stored = const {},
    ]) {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      stores = FakeCredentialStores();
      return wired(
        stored,
        platformAdapters(
          audioEngine: FakeAudioEngine(),
          credentialStores: stores.call,
          appLinks: FakeAppLinkSource(),
        ),
      );
    }

    Future<void> switchToB(ProviderContainer container) async {
      final directory = container.read(serverDirectoryProvider.notifier);
      await directory.add(serverB);
      await directory.setCurrent(serverB.id);
    }

    test('decides the configuration, the stores and the API connection, '
        'while links keep being followed', () async {
      final container = await switchable();
      final transport = container.read(apiTransportProvider);
      final links = container.read(deepLinkControllerProvider);

      await switchToB(container);

      final config = container.read(appConfigProvider);
      expect(config.baseUrl, 'https://example.com:8443');
      expect(config.serverId, 'f475765b53c3272e');
      expect(config.linkHost, 'example.com:8443');
      expect(
        container.read(credentialStoreProvider),
        same(stores('f475765b53c3272e')),
      );
      await container.read(lastRoomStoreProvider).write('x');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('alisten.last-room@f475765b53c3272e'), 'x');
      expect(container.read(apiTransportProvider), isNot(same(transport)));
      expect(container.read(deepLinkControllerProvider), same(links));
      expect(links.inviteLinkForRef('abc'), 'https://example.com:8443/r/abc');
    });

    test('a new room connection factory is made for the new '
        'server', () async {
      final container = await switchable();
      final before = container.read(roomTransportFactoryProvider);

      await switchToB(container);

      expect(container.read(roomTransportFactoryProvider), isNot(same(before)));
    });

    test('credentials are sent only to the server that issued them', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final http = FakeHttpAdapter();
      final rooms = <({Uri uri, FakeWebSocketChannel channel})>[];
      final stores = FakeCredentialStores();
      stores('fcd7a878032db68b').memberToken = 'member-token-of-A';
      stores('f475765b53c3272e').memberToken = 'member-token-of-B';
      final container = await wired(
        {},
        platformAdapters(
          audioEngine: FakeAudioEngine(),
          credentialStores: stores.call,
          appLinks: FakeAppLinkSource(),
          apiHttp: http,
          roomChannels: (uri) {
            final channel = FakeWebSocketChannel();
            rooms.add((uri: uri, channel: channel));
            return channel;
          },
        ),
      );
      final session = container.read(adminSessionProvider.notifier);
      Future<void> joinRoom(String ticket) async {
        final transport = container.read(roomTransportFactoryProvider)(
          'room-1',
          ticket,
        );
        await transport.start();
        await transport.stop();
      }

      final apiOfA = container.read(alistenApiProvider);
      http.respond(200, {'member': _member, 'recordListens': true});
      await apiOfA.getMe();
      http.respond(201, {'ticket': 'ticket-of-A'});
      await joinRoom(await apiOfA.createTicket('room-1'));
      http.respond(200, {'items': <Object?>[]});
      expect(await session.signIn('admin-token-of-A'), isA<AdminSignedIn>());
      http.respondRaw(204, '', null);
      await session.run((api, t) => api.setYoutubeCookie(t, 'cookie-of-A'));
      http.respond(200, {'status': 'waiting', 'message': ''});
      await session.run(
        (api, t) => api.checkQrLogin(t, LoginSource.netease, 'qr-key-of-A'),
      );
      http.respond(201, {'key': 'api-key-of-A'});
      await session.run((api, t) => api.resetApiKey(t, 'room-1'));
      final sentToA = http.requests.length;

      final directory = container.read(serverDirectoryProvider.notifier);
      await directory.add(serverB);
      await directory.setCurrent(serverB.id);

      http.respond(200, {'member': _member, 'recordListens': true});
      await container.read(alistenApiProvider).getMe();
      await expectLater(
        apiOfA.getMe(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')),
      );
      await joinRoom('ticket-of-B');
      for (final operation in <Future<Object?> Function(AdminApi, String)>[
        (api, t) => api.listRooms(t),
        (api, t) => api.setYoutubeCookie(t, 'cookie-of-A'),
        (api, t) => api.checkQrLogin(t, LoginSource.netease, 'qr-key-of-A'),
        (api, t) => api.resetApiKey(t, 'room-1'),
      ]) {
        await expectLater(
          session.run(operation),
          throwsA(isA<AdminSessionEnded>()),
        );
      }

      final toA = http.requests.take(sentToA);
      expect(toA.map((r) => r.uri.authority).toSet(), {'livehouse.dihe.moe'});
      expect(toA.map((r) => r.authorization), [
        'Bearer member-token-of-A',
        'Bearer member-token-of-A',
        for (var i = 0; i < 4; i++) 'Bearer admin-token-of-A',
      ]);
      final toB = http.requests.skip(sentToA).single;
      expect(toB.uri.authority, 'example.com:8443');
      expect(toB.authorization, 'Bearer member-token-of-B');
      expect(
        http.requests.map((r) => '${r.headers} ${r.jsonBody}').join(),
        isNot(contains('api-key-of-A')),
      );
      expect(rooms.map((room) => '${room.uri}'), [
        'wss://livehouse.dihe.moe/ws',
        'wss://example.com:8443/ws',
      ]);
      expect(rooms.first.channel.messages.single, contains('"ticket-of-A"'));
      expect(rooms.last.channel.messages.single, contains('"ticket-of-B"'));
    });

    test('a new brand name does not rebuild the configuration', () async {
      final container = await switchable();
      final config = container.read(appConfigProvider);

      await container
          .read(serverDirectoryProvider.notifier)
          .add(container.read(currentServerProvider).withBrandName('改名'));

      expect(container.read(currentServerProvider).brandName, '改名');
      expect(container.read(appConfigProvider), same(config));
    });

    test('is kept in the preferences for the next start', () async {
      final container = await switchable();
      await switchToB(container);

      final restarted = ProviderContainer(
        overrides: alistenWiring(container.read(sharedPreferencesProvider)),
      );
      addTearDown(restarted.dispose);

      expect(restarted.read(currentServerProvider), serverB);
      expect(restarted.read(appConfigProvider).baseUrl, serverB.origin);
    });

    test('removing a server forgets only its credentials and last '
        'room', () async {
      final container = await switchable({
        'alisten.last-room@f475765b53c3272e': 'b-room',
        'alisten.last-room@fcd7a878032db68b': 'default-room',
      });
      stores('f475765b53c3272e').memberToken = 'b';
      stores('fcd7a878032db68b').memberToken = 'default';
      final directory = container.read(serverDirectoryProvider.notifier);
      await directory.add(serverB);

      expect(await directory.remove(serverB.id), isTrue);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(ServerDataSweep.pendingKey), isTrue);
      expect(stores('f475765b53c3272e').clearCalls, 1);
      expect(stores('fcd7a878032db68b').memberToken, 'default');
      expect(
        preferences.containsKey('alisten.last-room@f475765b53c3272e'),
        isFalse,
      );
      expect(
        preferences.getString('alisten.last-room@fcd7a878032db68b'),
        'default-room',
      );
    });

    test('a server whose data cannot be forgotten is removed, and its data '
        'is left to the sweep at the next start', () async {
      final container = await switchable({
        'alisten.last-room@f475765b53c3272e': 'b-room',
      });
      final directory = container.read(serverDirectoryProvider.notifier);
      await directory.add(serverB);
      stores('f475765b53c3272e')
        ..memberToken = 'b'
        ..clearError = Exception('keychain locked');

      expect(await directory.remove(serverB.id), isTrue);

      expect(container.read(serverDirectoryProvider).byId(serverB.id), isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('alisten.servers'), isNot(contains('8443')));
      expect(preferences.getBool(ServerDataSweep.pendingKey), isTrue);
      expect(stores('f475765b53c3272e').memberToken, 'b');
    });

    test('whether a server holds a member token is read from its own '
        'credentials', () async {
      final container = await switchable();
      stores('f475765b53c3272e').memberToken = 'b';
      stores('837b2b5793a240b3').memberToken = '';
      final hasToken = container.read(serverHasMemberTokenProvider);

      expect(await hasToken('f475765b53c3272e'), isTrue);
      expect(await hasToken('837b2b5793a240b3'), isFalse);
      expect(await hasToken('fcd7a878032db68b'), isFalse);
    });
  });

  test('a server removed from the list gets no more credentials written by '
      'requests that answer late', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final container = await wired(
      {},
      platformAdapters(audioEngine: FakeAudioEngine()),
    );
    final directory = container.read(serverDirectoryProvider.notifier);
    await directory.add(serverB);
    await directory.setCurrent(serverB.id);
    final credentialsOfB = container.read(credentialStoreProvider);
    await credentialsOfB.writeMemberToken('b');
    await directory.setCurrent('fcd7a878032db68b');

    await directory.remove(serverB.id);
    await credentialsOfB.writeMemberToken('late');
    await credentialsOfB.writeTicket('room-id', 'late');

    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('the sweep at start keeps the data of the default server and of the '
      'saved servers', () async {
    FlutterSecureStorage.setMockInitialValues({
      'member_token@837b2b5793a240b3': 'default',
      'member_token@f475765b53c3272e': 'saved',
      'member_token@5a9795ac2ddb76e6': 'removed',
    });
    final preferences = await loadPreferences({
      ServerDataSweep.pendingKey: true,
      'alisten.servers': jsonEncode([serverB.toJson()]),
      'alisten.last-room@f475765b53c3272e': 'saved',
      'alisten.last-room@5a9795ac2ddb76e6': 'removed',
    });

    await sweepServerData(
      preferences,
      environment: BuildEnvironment(
        defaultOrigin: 'https://example.com',
        isRelease: true,
      ),
    );

    expect(Map.of(await const FlutterSecureStorage().readAll()), {
      'member_token@837b2b5793a240b3': 'default',
      'member_token@f475765b53c3272e': 'saved',
    });
    expect(
      preferences.getString('alisten.last-room@f475765b53c3272e'),
      'saved',
    );
    expect(
      preferences.containsKey('alisten.last-room@5a9795ac2ddb76e6'),
      isFalse,
    );
    expect(preferences.containsKey(ServerDataSweep.pendingKey), isFalse);
  });

  test('the storage migration moves the old keys to the default '
      'server', () async {
    FlutterSecureStorage.setMockInitialValues({
      'member_token': 'm',
      'room_ticket.room-1': 't',
    });
    final preferences = await loadPreferences({'alisten.last-room': 'listen'});

    await migrateStorage(
      preferences,
      environment: BuildEnvironment(
        defaultOrigin: 'https://example.com',
        isRelease: true,
      ),
    );

    expect(Map.of(await const FlutterSecureStorage().readAll()), {
      'member_token@837b2b5793a240b3': 'm',
      'room_ticket@837b2b5793a240b3.room-1': 't',
    });
    expect(
      preferences.getString('alisten.last-room@837b2b5793a240b3'),
      'listen',
    );
    expect(preferences.containsKey('alisten.last-room'), isFalse);
  });

  test('the shared wiring leaves exporting history to the platform '
      'adapters', () async {
    final container = await wired();

    expect(() => container.read(historyExporterProvider), throwsA(anything));
  });

  test('the storage settings measure and clear covers and avatars '
      'together', () async {
    final covers = FakeCoverCache(bytes: 4096);
    final avatars = FakeAvatarCache(bytes: 1024);
    final container = await wired({}, [
      coverCacheProvider.overrideWithValue(covers),
      avatarCacheProvider.overrideWithValue(avatars),
    ]);

    expect(await container.read(imageCacheSizeProvider)(), 5120);
    await container.read(clearImageCacheProvider)();

    expect(covers.clears, 1);
    expect(avatars.clears, 1);
    expect(await container.read(imageCacheSizeProvider)(), 0);
  });

  test('avatars are cleared even when covers cannot be, and clearing '
      'fails', () async {
    final covers = FakeCoverCache(bytes: 4096)
      ..clearError = const FileSystemException('busy');
    final avatars = FakeAvatarCache(bytes: 1024);
    final container = await wired({}, [
      coverCacheProvider.overrideWithValue(covers),
      avatarCacheProvider.overrideWithValue(avatars),
    ]);

    await expectLater(
      container.read(clearImageCacheProvider)(),
      throwsA(isA<FileSystemException>()),
    );
    expect(avatars.clears, 1);
    expect(await container.read(imageCacheSizeProvider)(), 4096);
  });

  test('avatar images come from the avatar cache', () async {
    final cache = FakeAvatarCache();
    final container = await wired({}, [
      avatarCacheProvider.overrideWithValue(cache),
    ]);

    expect(
      container.read(avatarImageSourceProvider)('https://avatar/a'),
      AvatarImage('https://avatar/a', cache),
    );
  });

  test('cover images come from the cover cache', () async {
    final cache = FakeCoverCache();
    final container = await wired({}, [
      coverCacheProvider.overrideWithValue(cache),
    ]);

    expect(
      container.read(coverImageSourceProvider)('https://cover/a'),
      CachedCoverImage('https://cover/a', cache),
    );
  });

  test('clearing the local email empties the stored one', () async {
    final container = await wired({'alisten.email': 'old@example.com'});

    await container.read(clearLocalEmailProvider)();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('alisten.email'), isEmpty);
    expect(container.read(settingsStoreProvider).load().email, isEmpty);
  });

  test('trimming the search history keeps the newest records', () async {
    final records = [
      for (var i = 0; i < 7; i++)
        SearchRecord(
          query: 'q$i',
          source: TrackSource.qq,
          category: SearchCategory.all,
          searchedAtMs: i,
        ),
    ];
    final container = await wired({
      'alisten.search-history': jsonEncode([
        for (final record in records) record.toJson(),
      ]),
    });

    await container.read(trimSearchHistoryProvider)(5);

    final preferences = await SharedPreferences.getInstance();
    expect(
      parseSearches(
        preferences.getString('alisten.search-history'),
        50,
      ).map((record) => record.query),
      ['q6', 'q5', 'q4', 'q3', 'q2'],
    );
  });

  test('reminders, the notification permission and the app start share one '
      'notifier on the notification gateway', () async {
    final gateway = FakeNotificationGateway()..granted = true;
    final container = await wired({}, [
      notificationGatewayProvider.overrideWithValue(gateway),
    ]);

    final reminders = container.read(reminderNotifierProvider);
    expect(container.read(trackStartReminderProvider), same(reminders));
    expect(container.read(notificationAccessProvider), same(reminders));
    expect(
      await container.read(notificationAccessProvider).checkPermission(),
      isTrue,
    );
    expect(gateway.permissionChecks, 1);
  });

  test(
    'the bundled font is listed among the licenses with its OFL text',
    () async {
      addTearDown(LicenseRegistry.reset);

      registerBundledLicenses();

      final entries = await LicenseRegistry.licenses.toList();
      final font = entries.where(
        (entry) => entry.packages.contains('Plus Jakarta Sans'),
      );
      expect(font, hasLength(1));
      final text = font.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(text, contains('The Plus Jakarta Sans Project Authors'));
    },
  );

  // gal 在 Android 上带入 commons-imaging，Apache-2.0 要求随分发附上其许可证
  // 和 NOTICE。
  test('commons-imaging is listed among the licenses with its NOTICE and '
      'its Apache License', () async {
    addTearDown(LicenseRegistry.reset);

    registerBundledLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final imaging = entries.where(
      (entry) => entry.packages.contains('commons-imaging'),
    );
    expect(imaging, hasLength(1));
    final text = imaging.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Apache Commons Imaging'));
    expect(
      text,
      contains('Copyright 2007-2022 The Apache Software Foundation'),
    );
    expect(text, contains('Apache License'));
    expect(text, contains('Version 2.0, January 2004'));
  });

  test('the bundled commons-imaging notices are the ones in its jar', () {
    final license = File('assets/licenses/commons-imaging/LICENSE.txt');
    final notice = File('assets/licenses/commons-imaging/NOTICE.txt');

    expect(license.lengthSync(), 14099);
    expect(notice.lengthSync(), 177);
    expect(
      File('pubspec.yaml').readAsLinesSync(),
      containsAll([
        '    - assets/licenses/commons-imaging/LICENSE.txt',
        '    - assets/licenses/commons-imaging/NOTICE.txt',
      ]),
    );
  });
}

const _member = {'id': 'm-1', 'name': '听众', 'avatarHash': 'h'};
