import 'dart:async';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/assembly.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/data/reminder_notifier.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/clipboard_link_controller.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/search/data/link_resolver.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/features/update/index.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../core/avatar/avatar_test_doubles.dart';
import '../core/cache/cover_cache_test_doubles.dart';
import '../domain/room/room_fixtures.dart';
import '../features/admin/admin_test_doubles.dart';
import '../features/history/history_test_doubles.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/lyrics/lyrics_test_doubles.dart';
import '../features/playback/playback_test_doubles.dart' show FakeAudioEngine;
import '../features/room/room_test_doubles.dart';
import '../features/search/share_test_doubles.dart';
import '../features/server/server_test_doubles.dart'
    show FakeCredentialStores, FakeServerProbe;
import '../features/settings/settings_test_doubles.dart';
import '../features/update/update_test_doubles.dart';

const emptyLobbyText = '还没有可加入的房间';

/// 与 `main` 共用同一份接线，只把外部 I/O 适配器换成假实现。
Future<List<Override>> alistenAppOverrides({
  FakeAlistenApi? api,
  FakeCredentialStore? credentials,
  FakeCredentialStores? credentialStores,
  FakeRoomTransportFactory? rooms,
  FakeAudioEngine? engine,
  FakeNotificationGateway? notifications,
  AppLinkSource? links,
  SharedTextSource? shares,
  FakeClipboardSource? clipboard,
  FakeSystemSettings? systemSettings,
  FakeCoverCache? coverCache,
  FakeAvatarCache? avatarCache,
  FakeHistoryExporter? exporter,
  FakeServerProbe? probe,
  FakeAdminApi? admin,
  FakeSensitiveClipboard? sensitiveClipboard,
  FakeQrImageLoader? qrImages,
  FakeImageGallery? gallery,
  FakeReleaseSource? releases,
  FakeReleaseOpener? releaseOpener,
  Map<String, Object> preferences = const {},
}) async {
  final stores = credentialStores ?? FakeCredentialStores();
  if (credentials != null) {
    final defaultId = BuildEnvironment.fromEnvironment().defaultServerId;
    final given = stores.stores[defaultId];
    if (given != null && !identical(given, credentials)) {
      throw ArgumentError.value(
        credentials,
        'credentials',
        'credentialStores 已有默认服务器的另一份凭据',
      );
    }
    stores.stores[defaultId] = credentials;
  }
  return [
    ...alistenWiring(await loadPreferences(preferences)),
    alistenApiProvider.overrideWithValue(api ?? FakeAlistenApi()),
    credentialStoreFactoryProvider.overrideWithValue(stores.call),
    connectivityStatusProvider.overrideWith((ref) => const Stream.empty()),
    roomTransportFactoryProvider.overrideWithValue(
      (rooms ?? FakeRoomTransportFactory()).call,
    ),
    audioEngineProvider.overrideWithValue(engine ?? FakeAudioEngine()),
    notificationGatewayProvider.overrideWithValue(
      notifications ?? FakeNotificationGateway(),
    ),
    appLinkSourceProvider.overrideWithValue(links ?? FakeAppLinkSource()),
    sharedTextSourceProvider.overrideWithValue(
      shares ?? FakeSharedTextSource(),
    ),
    clipboardSourceProvider.overrideWithValue(
      clipboard ?? FakeClipboardSource(),
    ),
    systemSettingsProvider.overrideWithValue(
      systemSettings ?? FakeSystemSettings(),
    ),
    linkResolverProvider.overrideWithValue(
      DioLinkResolver(Dio()..httpClientAdapter = FakeUrlHttpAdapter()),
    ),
    coverCacheProvider.overrideWithValue(coverCache ?? FakeCoverCache()),
    avatarCacheProvider.overrideWithValue(avatarCache ?? FakeAvatarCache()),
    historyExporterProvider.overrideWithValue(
      exporter ?? FakeHistoryExporter(),
    ),
    serverProbeProvider.overrideWithValue(probe ?? FakeServerProbe()),
    adminApiProvider.overrideWithValue(admin ?? FakeAdminApi()),
    sensitiveClipboardProvider.overrideWithValue(
      sensitiveClipboard ?? FakeSensitiveClipboard(),
    ),
    qrImageLoaderProvider.overrideWithValue(qrImages ?? FakeQrImageLoader()),
    imageGalleryProvider.overrideWithValue(gallery ?? FakeImageGallery()),
    screenAwakeDeviceProvider.overrideWithValue(FakeScreenAwakeDevice()),
    releaseSourceProvider.overrideWithValue(releases ?? FakeReleaseSource()),
    releaseOpenerProvider.overrideWithValue(
      releaseOpener ?? FakeReleaseOpener(),
    ),
  ];
}

/// [overrides] 排在假实现之后，可再替换任何 provider。
Future<void> pumpAlistenApp(
  WidgetTester tester, {
  MediaQueryData system = const MediaQueryData(),
  FakeAlistenApi? api,
  FakeCredentialStore? credentials,
  FakeCredentialStores? credentialStores,
  FakeRoomTransportFactory? rooms,
  FakeAudioEngine? engine,
  FakeNotificationGateway? notifications,
  AppLinkSource? links,
  FakeSharedTextSource? shares,
  FakeClipboardSource? clipboard,
  FakeSystemSettings? systemSettings,
  FakeCoverCache? coverCache,
  FakeAvatarCache? avatarCache,
  FakeHistoryExporter? exporter,
  FakeServerProbe? probe,
  FakeAdminApi? admin,
  FakeSensitiveClipboard? sensitiveClipboard,
  FakeQrImageLoader? qrImages,
  FakeImageGallery? gallery,
  FakeReleaseSource? releases,
  FakeReleaseOpener? releaseOpener,
  Map<String, Object> preferences = const {},
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await alistenAppOverrides(
          api: api,
          credentials: credentials,
          credentialStores: credentialStores,
          rooms: rooms,
          engine: engine,
          notifications: notifications,
          links: links,
          shares: shares,
          clipboard: clipboard,
          systemSettings: systemSettings,
          coverCache: coverCache,
          avatarCache: avatarCache,
          exporter: exporter,
          probe: probe,
          admin: admin,
          sensitiveClipboard: sensitiveClipboard,
          qrImages: qrImages,
          gallery: gallery,
          releases: releases,
          releaseOpener: releaseOpener,
          preferences: preferences,
        ),
        ...overrides,
      ],
      child: MediaQuery(data: system, child: const AlistenApp()),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

/// 别名 `listen` 对应的房间 UUID。
const testRoomId = '123e4567-e89b-42d3-a456-426614174000';

typedef EnteredRoom = ({
  FakeRoomTransportFactory rooms,
  GoRouter router,
  Future<void> Function() settle,
});

/// [serverNow] 是握手时的服务端时间，决定曲目播放到的位置。
Future<EnteredRoom> enterRoom(
  WidgetTester tester, {
  Size size = const Size(360, 780),
  MediaQueryData system = const MediaQueryData(),
  NowPlaying nowPlaying = testNowPlaying,
  FakeAudioEngine? engine,
  int? serverNow,
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final rooms = FakeRoomTransportFactory();
  await pumpAlistenApp(
    tester,
    system: system,
    api: FakeAlistenApi()
      ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
    credentials: FakeCredentialStore()..tickets[testRoomId] = 'saved-ticket',
    rooms: rooms,
    engine: engine,
    overrides: overrides,
  );
  final router = appContainer(tester).read(routerProvider);
  // 房间页的极光动画不会停止，只能逐步推进时间，不能等待画面稳定。
  Future<void> settle() async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  router.go('/r/listen');
  await settle();
  rooms.last.emitHello(
    testRoomSnapshot().copyWith(
      term: 1,
      seq: 1,
      room: const RoomInfo(
        id: testRoomId,
        name: '一起听',
        description: '',
        kind: RoomKind.ephemeral,
      ),
      nowPlaying: nowPlaying,
    ),
    serverNow,
  );
  await settle();
  return (rooms: rooms, router: router, settle: settle);
}

/// [control] 完整显示在屏幕内，位于 [above] 与 [below] 之间且不被两者遮挡。
void expectBetween(
  WidgetTester tester,
  Finder control, {
  required Finder above,
  required Finder below,
}) {
  final rect = tester.getRect(control);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.left, greaterThanOrEqualTo(0), reason: '$rect');
  expect(rect.right, lessThanOrEqualTo(screen.width), reason: '$rect');
  expect(rect.top, greaterThanOrEqualTo(tester.getRect(above).bottom));
  expect(rect.bottom, lessThanOrEqualTo(tester.getRect(below).top));
}

ProviderContainer appContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AlistenApp)));

/// 与 app_links 插件一致：启动应用的链接也会投递给第一个监听者。
final class FakeAppLinkSource implements AppLinkSource {
  FakeAppLinkSource({this.initial});

  final Uri? initial;
  late final _links = StreamController<Uri>.broadcast(onListen: _replay);
  bool _replayed = false;

  @override
  Future<Uri?> getInitialLink() async => initial;

  @override
  Stream<Uri> get uriLinkStream => _links.stream;

  void open(Uri uri) => _links.add(uri);

  void _replay() {
    final initial = this.initial;
    if (_replayed || initial == null) return;
    _replayed = true;
    scheduleMicrotask(() => _links.add(initial));
  }
}

/// [launchPayload] 是启动应用的通知，与真实插件一样在初始化时立即投递。
final class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({this.launchPayload});

  final String? launchPayload;
  final List<String> shown = [];
  int permissionChecks = 0;
  bool granted = false;
  void Function(String payload)? _onPayload;

  void tap(String payload) => _onPayload!(payload);

  @override
  Future<void> initialize(void Function(String payload) onPayload) async {
    _onPayload = onPayload;
    if (launchPayload case final payload?) onPayload(payload);
  }

  @override
  Future<bool> checkPermission() async {
    permissionChecks++;
    return granted;
  }

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    shown.add(payload);
  }
}
