import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../lobby/lobby_test_doubles.dart';
import '../room/room_test_doubles.dart';

/// 不接受 http 服务器；默认服务器 id 为 `fcd7a878032db68b`。
final testEnvironment = BuildEnvironment(
  defaultOrigin: 'https://livehouse.dihe.moe',
  isRelease: false,
);

/// id 为 `f475765b53c3272e`。
final serverB = ServerProfile(
  origin: 'https://example.com:8443',
  brandName: '周末听歌会',
  addedAtMs: 1,
);

final serverC = ServerProfile(
  origin: 'https://other.example.org',
  brandName: '另一个站',
  addedAtMs: 2,
);

final class FakeServerStore implements ServerStore {
  FakeServerStore({List<ServerProfile> profiles = const [], this.currentId})
    : profiles = List.of(profiles);

  List<ServerProfile> profiles;
  String? currentId;
  bool failProfileWrites = false;
  bool failCurrentWrites = false;

  final List<String> currentIdWrites = [];

  /// 在写入生效之前调用，写入要等它完成才完成。
  FutureOr<void> Function(String id)? onSaveCurrent;

  /// 在写入生效之前调用，写入要等它完成才完成。
  FutureOr<void> Function(List<ServerProfile> profiles)? onSaveProfiles;

  @override
  List<ServerProfile> loadProfiles() => List.of(profiles);

  @override
  String? loadCurrentId() => currentId;

  @override
  Future<void> saveProfiles(List<ServerProfile> profiles) async {
    await onSaveProfiles?.call(profiles);
    if (failProfileWrites) throw StateError('server store write failed');
    this.profiles = List.of(profiles);
  }

  @override
  Future<void> saveCurrentId(String id) async {
    await onSaveCurrent?.call(id);
    if (failCurrentWrites) throw StateError('server store write failed');
    currentId = id;
    currentIdWrites.add(id);
  }
}

/// 同一个 id 总是得到同一个 [FakeCredentialStore]。
final class FakeCredentialStores {
  final Map<String, FakeCredentialStore> stores = {};

  FakeCredentialStore call(String id) {
    return stores.putIfAbsent(id, FakeCredentialStore.new);
  }
}

final class FakeServerProbe implements ServerProbe {
  final Map<String, ProbeResult> results = {};
  final Map<String, ProbeResult> siteResults = {};
  final Map<String, ProbeFailure> handshakeFailures = {};
  final Map<String, String?> brands = {};
  final List<String> probed = [];
  final List<(String origin, Duration? timeout)> siteProbed = [];

  final List<Future<void>?> siteCancels = [];
  final List<String> handshakes = [];

  final List<Future<void>?> handshakeCancels = [];
  final List<String> brandRequests = [];
  Completer<void>? gate;

  @override
  Future<ProbeResult> probe(String origin) async {
    probed.add(origin);
    await gate?.future;
    return results[origin] ?? const ProbeFailed(ProbeFailure.unreachable);
  }

  @override
  Future<ProbeResult> probeSite(
    String origin, {
    Duration? timeout,
    Future<void>? cancel,
  }) async {
    siteProbed.add((origin, timeout));
    siteCancels.add(cancel);
    await gate?.future;
    return siteResults[origin] ?? const ProbeFailed(ProbeFailure.unreachable);
  }

  @override
  Future<ProbeFailure?> probeHandshake(
    String origin, {
    Future<void>? cancel,
  }) async {
    handshakes.add(origin);
    handshakeCancels.add(cancel);
    await gate?.future;
    return handshakeFailures[origin];
  }

  @override
  Future<String?> fetchBrandName(String origin) async {
    brandRequests.add(origin);
    await gate?.future;
    return brands[origin];
  }
}

Future<List<Override>> switchingOverrides({
  required FakeServerStore store,
  required FakeCredentialStores credentials,
  FakeAlistenApi? api,
  Map<String, FakeAlistenApi> apis = const {},
  FakeRoomTransportFactory? rooms,
  List<String>? forgotten,
  Map<String, Object> preferences = const {},
  void Function()? onEndAdminSession,
  BuildEnvironment? environment,
}) async {
  final sharedApi = api ?? FakeAlistenApi();
  final transports = rooms ?? FakeRoomTransportFactory();
  String serverIdOf(Ref ref) =>
      ref.watch(appConfigProvider.select((config) => config.serverId));
  return [
    sharedPreferencesProvider.overrideWithValue(
      await loadPreferences(preferences),
    ),
    buildEnvironmentProvider.overrideWithValue(environment ?? testEnvironment),
    serverStoreProvider.overrideWithValue(store),
    ...currentServerWiring(),
    credentialStoreFactoryProvider.overrideWithValue(credentials.call),
    scheduleServerDataSweepProvider.overrideWithValue(() async {}),
    forgetServerDataProvider.overrideWithValue((id) async {
      forgotten?.add(id);
    }),
    serverHasMemberTokenProvider.overrideWithValue((id) async {
      final token = await credentials(id).readMemberToken();
      return token != null && token.isNotEmpty;
    }),
    alistenApiProvider.overrideWith(
      (ref) => apis[serverIdOf(ref)] ?? sharedApi,
    ),
    roomTransportFactoryProvider.overrideWith(
      (ref) => transports.onServer(serverIdOf(ref)),
    ),
    connectivityStatusProvider.overrideWith((ref) => const Stream.empty()),
    clearLocalEmailProvider.overrideWithValue(() async {}),
    endAdminSessionProvider.overrideWithValue(onEndAdminSession ?? () {}),
  ];
}

Future<ProviderContainer> switchingContainer({
  required FakeServerStore store,
  required FakeCredentialStores credentials,
  FakeAlistenApi? api,
  Map<String, FakeAlistenApi> apis = const {},
  FakeRoomTransportFactory? rooms,
  List<String>? forgotten,
  Map<String, Object> preferences = const {},
  void Function()? onEndAdminSession,
  BuildEnvironment? environment,
  List<Override> extra = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      ...await switchingOverrides(
        store: store,
        credentials: credentials,
        api: api,
        apis: apis,
        rooms: rooms,
        forgotten: forgotten,
        preferences: preferences,
        onEndAdminSession: onEndAdminSession,
        environment: environment,
      ),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}
