import 'dart:async';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/assembly.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/avatar/avatar_image.dart';
import 'package:alisten/core/avatar/disk_avatar_cache.dart';
import 'package:alisten/core/cache/cached_cover_image.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/cache/disk_cover_cache.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/features/history/data/share_history_exporter.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/data/reminder_notifier.dart';
import 'package:alisten/features/playback/data/unavailable_audio_engine.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/data/preferences_last_room_store.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/data/clipboard_source.dart';
import 'package:alisten/features/search/data/link_resolver.dart';
import 'package:alisten/features/search/data/search_history_store.dart';
import 'package:alisten/features/search/data/shared_text_source.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/features/settings/data/local_settings_store.dart';
import 'package:alisten/features/settings/data/platform_system_settings.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/features/update/data/platform_release_opener.dart';
import 'package:alisten/features/update/data/preferences_update_store.dart';
import 'package:alisten/features/update/index.dart';
import 'package:alisten/main.dart' as entrypoint;
import 'package:alisten/shared/ui/avatar_images.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_test_harness.dart';
import 'features/lobby/lobby_test_doubles.dart';
import 'features/playback/playback_test_doubles.dart' show FakeAudioEngine;
import 'features/server/server_test_doubles.dart' show FakeServerProbe;
import 'features/update/update_test_doubles.dart';

void main() {
  testWidgets('a cold start opens the lobby under its title', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: const AlistenApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Alisten')),
      isSemantics(isHeader: true),
      reason: 'the lobby title is announced as the heading of the page',
    );
    expect(find.text('创建房间'), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the stored theme is in effect on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(
          preferences: {'alisten.theme': 'dark'},
        ),
        child: const AlistenApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('app start restores a stored member once and creates none', (
    tester,
  ) async {
    final api = FakeAlistenApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(
          api: api,
          credentials: FakeCredentialStore()..memberToken = 'stored-token',
        ),
        child: const AlistenApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.getMeCalls, 1);
    expect(api.createMemberCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('main installs the Riverpod dependency scope', (tester) async {
    addTearDown(LicenseRegistry.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final engine = FakeAudioEngine();
    final api = FakeAlistenApi();
    final credentials = FakeCredentialStore();
    final links = FakeAppLinkSource();
    final releases = FakeReleaseSource();
    await entrypoint.main(
      startAudio: () async => engine,
      api: api,
      credentialStores: (_) => credentials,
      connectivityStatus: const Stream<List<ConnectivityResult>>.empty(),
      appLinks: links,
      serverProbe: FakeServerProbe(),
      releaseSource: releases,
    );
    await tester.pump();

    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.text('Alisten'), findsOneWidget);
    // 端口的默认实现只会抛出“未注入”，main 必须逐个注入。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AlistenApp)),
    );
    expect(container.read(appConfigProvider), isA<AppConfig>());
    expect(container.read(sharedPreferencesProvider), isA<SharedPreferences>());
    expect(container.read(alistenApiProvider), same(api));
    expect(container.read(credentialStoreProvider), same(credentials));
    expect(container.read(connectivityStatusProvider).hasError, isFalse);
    expect(
      container.read(roomTransportFactoryProvider),
      isA<RoomTransportFactory>(),
    );
    expect(container.read(audioEngineProvider), same(engine));
    expect(
      container.read(lastRoomStoreProvider),
      isA<PreferencesLastRoomStore>(),
    );
    expect(
      container.read(notificationGatewayProvider),
      isA<PluginNotificationGateway>(),
    );
    final reminders = container.read(reminderNotifierProvider);
    expect(container.read(trackStartReminderProvider), same(reminders));
    expect(container.read(notificationAccessProvider), same(reminders));
    expect(
      container.read(historyExporterProvider),
      isA<ShareHistoryExporter>(),
    );
    expect(
      container.read(searchHistoryStoreProvider),
      isA<PreferencesSearchHistoryStore>(),
    );
    expect(container.read(settingsStoreProvider), isA<LocalSettingsStore>());
    expect(
      container.read(clearLocalEmailProvider),
      isA<Future<void> Function()>(),
    );
    expect(
      container.read(trimSearchHistoryProvider),
      isA<Future<void> Function(int)>(),
    );
    expect(
      container.read(sharedTextSourceProvider),
      isA<PlatformSharedTextSource>(),
    );
    expect(container.read(linkResolverProvider), isA<DioLinkResolver>());
    expect(
      container.read(clipboardSourceProvider),
      isA<PlatformClipboardSource>(),
    );
    expect(
      container.read(systemSettingsProvider),
      isA<PlatformSystemSettings>(),
    );
    expect(container.read(appLinkSourceProvider), same(links));
    final covers = container.read(coverCacheProvider);
    expect(covers, isA<DiskCoverCache>());
    final avatars = container.read(avatarCacheProvider);
    expect(avatars, isA<DiskAvatarCache>());
    expect(
      container.read(imageCacheSizeProvider),
      isA<Future<int> Function()>(),
    );
    expect(
      container.read(clearImageCacheProvider),
      isA<Future<void> Function()>(),
    );
    // 每一页的封面都经同一个缓存读取。
    expect(
      tester.widget<CoverImages>(find.byType(CoverImages)).resolve('https://c'),
      CachedCoverImage('https://c', covers),
    );
    // 每个头像都经同一个缓存和其中的下载器，它记住的可用站点才对所有头像生效。
    expect(
      tester
          .widget<AvatarImages>(find.byType(AvatarImages))
          .resolve('https://a'),
      AvatarImage('https://a', avatars),
    );
    expect(container.read(releaseSourceProvider), same(releases));
    expect(container.read(releaseOpenerProvider), isA<PlatformReleaseOpener>());
    expect(container.read(updateStoreProvider), isA<PreferencesUpdateStore>());
    expect(releases.calls, 1);
    // 内置字体和 gal 带入的 commons-imaging 的许可证须随应用列出。
    final licenses = await tester.runAsync(
      () => LicenseRegistry.licenses.toList(),
    );
    expect(
      licenses!.where((entry) => entry.packages.contains('Plus Jakarta Sans')),
      hasLength(1),
    );
    expect(
      licenses.where((entry) => entry.packages.contains('commons-imaging')),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('main moves the credentials of an earlier version to the '
      'default server before it returns', (tester) async {
    addTearDown(LicenseRegistry.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'member_token': 'stored'});

    await entrypoint.main(
      startAudio: () async => FakeAudioEngine(),
      api: FakeAlistenApi(),
      credentialStores: (_) => FakeCredentialStore(),
      connectivityStatus: const Stream<List<ConnectivityResult>>.empty(),
      appLinks: FakeAppLinkSource(),
      serverProbe: FakeServerProbe(),
      releaseSource: FakeReleaseSource(),
    );
    await tester.pump();

    expect(Map.of(await const FlutterSecureStorage().readAll()), {
      'member_token@fcd7a878032db68b': 'stored',
    });
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('alisten.storage-version'), 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an audio service that cannot start leaves the rest of the app '
      'running and logs only the error type', (tester) async {
    addTearDown(LicenseRegistry.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final logs = <String>[];
    AppLog.onRecord = (name, level, message) {
      if (name == 'alisten.audio') logs.add(message);
    };
    addTearDown(() => AppLog.onRecord = null);

    await entrypoint.main(
      startAudio: () async =>
          throw PlatformException(code: 'session', message: 'secret detail'),
      api: FakeAlistenApi(),
      credentialStores: (_) => FakeCredentialStore(),
      connectivityStatus: const Stream<List<ConnectivityResult>>.empty(),
      appLinks: FakeAppLinkSource(),
      serverProbe: FakeServerProbe(),
      releaseSource: FakeReleaseSource(),
    );
    await tester.pump();

    expect(find.text('创建房间'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AlistenApp)),
    );
    expect(container.read(audioEngineProvider), isA<UnavailableAudioEngine>());
    expect(logs, [
      allOf(
        contains('audio service not started'),
        contains('type=PlatformException'),
      ),
    ]);
    expect(logs.single, isNot(contains('secret detail')));
    await tester.pumpWidget(const SizedBox());
  });
}
