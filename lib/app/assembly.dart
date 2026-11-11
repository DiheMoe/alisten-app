import 'package:alisten/app/app.dart';
import 'package:alisten/app/app_version.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/third_party_http.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/avatar/avatar_loader.dart';
import 'package:alisten/core/avatar/disk_avatar_cache.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/cache/disk_cover_cache.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/core/realtime/websocket_room_transport.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/release/release_version.dart';
import 'package:alisten/features/account/data/web_auth_github_authorizer.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/admin/data/dio_qr_image_loader.dart';
import 'package:alisten/features/admin/data/gal_image_gallery.dart';
import 'package:alisten/features/admin/data/platform_sensitive_clipboard.dart';
import 'package:alisten/features/admin/data/rest_admin_api.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/history/data/share_history_exporter.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/lobby/index.dart';
import 'package:alisten/features/lyrics/data/wakelock_screen_awake.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/data/reminder_notifier.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/data/preferences_last_room_store.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/data/clipboard_source.dart';
import 'package:alisten/features/search/data/link_resolver.dart';
import 'package:alisten/features/search/data/search_history_store.dart';
import 'package:alisten/features/search/data/shared_text_source.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/features/server/data/alisten_server_probe.dart';
import 'package:alisten/features/server/data/preferences_server_store.dart';
import 'package:alisten/features/server/data/server_data_sweep.dart';
import 'package:alisten/features/server/data/storage_migration.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/data/local_settings_store.dart';
import 'package:alisten/features/settings/data/platform_system_settings.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/features/update/data/github_release_source.dart';
import 'package:alisten/features/update/data/platform_release_opener.dart';
import 'package:alisten/features/update/data/preferences_update_store.dart';
import 'package:alisten/features/update/index.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final notificationGatewayProvider = Provider<NotificationGateway>((ref) {
  throw UnimplementedError('notificationGateway 未注入');
});

/// OFL 和 Apache-2.0 要求随分发附上许可证（Apache 另含 NOTICE）。
/// 内置字体和 gal 在 Android 上带入的 commons-imaging 不是 pub 包，
/// Flutter 不会替它们收集，须在此登记。
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Plus Jakarta Sans',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    const imaging = 'assets/licenses/commons-imaging';
    yield LicenseEntryWithLineBreaks(
      const ['commons-imaging'],
      '${await rootBundle.loadString('$imaging/NOTICE.txt')}\n\n'
      '${await rootBundle.loadString('$imaging/LICENSE.txt')}',
    );
  });
}

/// 不含外部 I/O 适配器：`main` 另用 [platformAdapters]，测试注入假实现。
List<Override> alistenWiring(
  SharedPreferences preferences, {
  BuildEnvironment? environment,
}) {
  return [
    buildEnvironmentProvider.overrideWith(
      (ref) => environment ?? BuildEnvironment.fromEnvironment(),
    ),
    serverStoreProvider.overrideWith(
      (ref) => PreferencesServerStore(ref.watch(sharedPreferencesProvider)),
    ),
    scheduleServerDataSweepProvider.overrideWith((ref) {
      return () =>
          ServerDataSweep.markPending(ref.read(sharedPreferencesProvider));
    }),
    forgetServerDataProvider.overrideWith((ref) {
      return (serverId) async {
        await ref.read(credentialStoreFactoryProvider)(serverId).clear();
        await PreferencesLastRoomStore(
          ref.read(sharedPreferencesProvider),
          serverId: serverId,
        ).clear();
      };
    }),
    serverHasMemberTokenProvider.overrideWith((ref) {
      return (serverId) async {
        final token = await ref
            .read(credentialStoreFactoryProvider)(serverId)
            .readMemberToken();
        return token != null && token.isNotEmpty;
      };
    }),
    endAdminSessionProvider.overrideWith(
      (ref) =>
          () => ref.read(adminSessionProvider.notifier).end(),
    ),
    ...currentServerWiring(),
    sharedPreferencesProvider.overrideWithValue(preferences),
    settingsStoreProvider.overrideWith(
      (ref) => LocalSettingsStore(ref.watch(sharedPreferencesProvider)),
    ),
    searchHistoryStoreProvider.overrideWith(
      (ref) =>
          PreferencesSearchHistoryStore(ref.watch(sharedPreferencesProvider)),
    ),
    reminderNotifierProvider.overrideWith(
      (ref) => ReminderNotifier(
        ref.watch(notificationGatewayProvider),
        serverId: () => ref.read(currentServerProvider).id,
      ),
    ),
    trackStartReminderProvider.overrideWith(
      (ref) => ref.watch(reminderNotifierProvider),
    ),
    notificationAccessProvider.overrideWith(
      (ref) => ref.watch(reminderNotifierProvider),
    ),
    lobbyBrandProvider.overrideWith(
      (ref) => ref.watch(
        currentServerProvider.select((server) => server.displayName),
      ),
    ),
    refreshLobbyBrandProvider.overrideWith(
      (ref) => ref.read(serverDirectoryProvider.notifier).refreshCurrentBrand,
    ),
    clearLocalEmailProvider.overrideWith((ref) {
      return () async {
        await ref.read(settingsStoreProvider).clearEmail();
      };
    }),
    trimSearchHistoryProvider.overrideWith((ref) {
      return (limit) async {
        await ref.read(searchHistoryStoreProvider).truncate(limit);
      };
    }),
    imageCacheSizeProvider.overrideWith((ref) {
      return () async {
        final sizes = await Future.wait([
          ref.read(coverCacheProvider).size(),
          ref.read(avatarCacheProvider).size(),
        ]);
        return sizes.fold<int>(0, (total, size) => total + size);
      };
    }),
    // 一类清除失败时另一类照样清除，再报告失败。
    clearImageCacheProvider.overrideWith((ref) {
      return () async {
        await Future.wait([
          ref.read(coverCacheProvider).clear(),
          ref.read(avatarCacheProvider).clear(),
        ]);
      };
    }),
    updateStoreProvider.overrideWith(
      (ref) => PreferencesUpdateStore(ref.watch(sharedPreferencesProvider)),
    ),
    // 版本号的格式由 app_version_test 保证。
    installedVersionProvider.overrideWithValue(
      ReleaseVersion.fromAppVersion(appVersion)!,
    ),
  ];
}

/// [alistenWiring] 已包含；测试可配合假的服务器存储单独使用。
List<Override> currentServerWiring() {
  return [
    // 只跟随地址：品牌名变化不重建配置和依赖它的连接。
    appConfigProvider.overrideWith((ref) {
      final origin = ref.watch(
        currentServerProvider.select((server) => server.origin),
      );
      return ref.watch(buildEnvironmentProvider).configFor(origin);
    }),
    credentialStoreProvider.overrideWith(
      (ref) => ref.watch(credentialStoreFactoryProvider)(
        ref.watch(appConfigProvider.select((config) => config.serverId)),
      ),
    ),
    lastRoomStoreProvider.overrideWith(
      (ref) => PreferencesLastRoomStore(
        ref.watch(sharedPreferencesProvider),
        serverId: ref.watch(
          appConfigProvider.select((config) => config.serverId),
        ),
      ),
    ),
  ];
}

List<Override> platformAdapters({
  required AudioEngine audioEngine,
  AlistenApi? api,
  HttpClientAdapter? apiHttp,
  CredentialStore Function(String serverId)? credentialStores,
  WebSocketChannelFactory? roomChannels,
  Stream<List<ConnectivityResult>>? connectivityStatus,
  AppLinkSource? appLinks,
  ServerProbe? serverProbe,
  ReleaseSource? releaseSource,
}) {
  return [
    audioEngineProvider.overrideWithValue(audioEngine),
    screenAwakeDeviceProvider.overrideWithValue(const WakelockScreenAwake()),
    credentialStoreFactoryProvider.overrideWith((ref) {
      if (credentialStores != null) return credentialStores;
      return (serverId) => SecureCredentialStore(
        const FlutterSecureStorage(),
        serverId: serverId,
        serverListed: () =>
            ref.read(serverDirectoryProvider).byId(serverId) != null,
      );
    }),
    // 每个服务器一个 Dio；换服务器时关闭旧的，在途请求一并取消。
    apiTransportProvider.overrideWith((ref) {
      final dio = Dio();
      if (apiHttp != null) dio.httpClientAdapter = apiHttp;
      ref.onDispose(() => dio.close(force: true));
      return ApiTransport(dio, ref.watch(appConfigProvider));
    }),
    alistenApiProvider.overrideWith((ref) {
      if (api != null) return api;
      return RestAlistenApi(
        ref.watch(apiTransportProvider),
        ref.watch(credentialStoreProvider).readMemberToken,
      );
    }),
    connectivityStatusProvider.overrideWith(
      (ref) => connectivityStatus ?? Connectivity().onConnectivityChanged,
    ),
    // 工厂绑定创建时的服务器：票据和连接必须来自同一个服务器。
    roomTransportFactoryProvider.overrideWith((ref) {
      final baseUri = Uri.parse(ref.watch(appConfigProvider).baseUrl);
      return (roomId, ticket) => WebSocketRoomTransport(
        baseUri: baseUri,
        roomId: roomId,
        ticket: ticket,
        channelFactory: roomChannels,
      );
    }),
    serverProbeProvider.overrideWith((ref) {
      if (serverProbe != null) return serverProbe;
      // 探测的是用户输入的服务器，不能用带当前服务器 baseUrl 的 API Dio。
      final dio = Dio();
      ref.onDispose(() => dio.close(force: true));
      return AlistenServerProbe(dio: dio);
    }),
    adminApiProvider.overrideWith(
      (ref) => RestAdminApi(ref.watch(apiTransportProvider)),
    ),
    sensitiveClipboardProvider.overrideWithValue(PlatformSensitiveClipboard()),
    qrImageLoaderProvider.overrideWith((ref) {
      final dio = newThirdPartyDio();
      ref.onDispose(() => dio.close(force: true));
      return DioQrImageLoader(dio);
    }),
    imageGalleryProvider.overrideWithValue(const GalImageGallery()),
    notificationGatewayProvider.overrideWith(
      (ref) => PluginNotificationGateway(FlutterLocalNotificationsPlugin()),
    ),
    historyExporterProvider.overrideWithValue(const ShareHistoryExporter()),
    systemSettingsProvider.overrideWithValue(PlatformSystemSettings()),
    sharedTextSourceProvider.overrideWithValue(PlatformSharedTextSource()),
    clipboardSourceProvider.overrideWithValue(PlatformClipboardSource()),
    linkResolverProvider.overrideWith((ref) {
      final dio = newThirdPartyDio();
      ref.onDispose(() => dio.close(force: true));
      return DioLinkResolver(dio);
    }),
    appLinkSourceProvider.overrideWith(
      (ref) => appLinks ?? PluginAppLinkSource(),
    ),
    coverCacheProvider.overrideWith((ref) {
      final dio = newThirdPartyDio();
      ref.onDispose(() => dio.close(force: true));
      return DiskCoverCache(dio);
    }),
    avatarCacheProvider.overrideWith((ref) {
      final dio = newThirdPartyDio();
      ref.onDispose(() => dio.close(force: true));
      return DiskAvatarCache(AvatarLoader(dio));
    }),
    // 请求发往 GitHub，不能用带当前服务器 baseUrl 和成员凭据的 API Dio。
    releaseSourceProvider.overrideWith((ref) {
      if (releaseSource != null) return releaseSource;
      final dio = newThirdPartyDio();
      ref.onDispose(() => dio.close(force: true));
      return GitHubReleaseSource(dio);
    }),
    releaseOpenerProvider.overrideWithValue(PlatformReleaseOpener()),
    githubAuthorizerProvider.overrideWithValue(const WebAuthGithubAuthorizer()),
  ];
}

/// 不抛出：失败时保留待清扫标记，下次启动再试。默认服务器和已保存的服务器都算在
/// 列表中，包括当前构建不接受的服务器。
Future<void> sweepServerData(
  SharedPreferences preferences, {
  FlutterSecureStorage storage = const FlutterSecureStorage(),
  required BuildEnvironment environment,
}) async {
  await ServerDataSweep(
    storage: storage,
    preferences: preferences,
    listedServerIds: {
      environment.defaultServerId,
      for (final profile in PreferencesServerStore(preferences).loadProfiles())
        profile.id,
    },
    lastRoomKeyPrefix: PreferencesLastRoomStore.keyPrefix,
  ).run();
}

/// 不抛出：失败时保留旧键，下次启动再试。
Future<void> migrateStorage(
  SharedPreferences preferences, {
  FlutterSecureStorage storage = const FlutterSecureStorage(),
  required BuildEnvironment environment,
}) async {
  final serverId = environment.defaultServerId;
  await StorageMigration(
    storage: storage,
    preferences: preferences,
    defaultServerId: serverId,
    preferenceMoves: {
      PreferencesLastRoomStore.legacyKey: PreferencesLastRoomStore.keyFor(
        serverId,
      ),
    },
  ).run();
}
