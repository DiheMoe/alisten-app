import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/server/server_origin.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/server/application/server_probe.dart';
import 'package:alisten/features/server/application/server_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class ServerDirectoryState {
  const ServerDirectoryState({
    required this.profiles,
    required this.currentId,
    required this.defaultId,
    required this.defaultLinkHost,
  });

  /// 默认服务器在最前，其余按添加的先后。
  final List<ServerProfile> profiles;
  final String currentId;
  final String defaultId;
  final String defaultLinkHost;

  ServerProfile get current => byId(currentId)!;

  ServerProfile? byId(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  bool isDefault(ServerProfile profile) => profile.id == defaultId;

  // 只有默认服务器的网站主机可以与 API 主机不同（`ALISTEN_LINK_HOST`）。
  String linkAuthorityOf(ServerProfile profile) {
    return isDefault(profile) ? defaultLinkHost : profile.authority;
  }

  ServerProfile? byLinkAuthority(String authority) {
    for (final profile in profiles) {
      if (linkAuthorityOf(profile) == authority) return profile;
    }
    return null;
  }

  ServerDirectoryState _copyWith({
    List<ServerProfile>? profiles,
    String? currentId,
  }) {
    return ServerDirectoryState(
      profiles: profiles == null
          ? this.profiles
          : _ordered(profiles, defaultId),
      currentId: currentId ?? this.currentId,
      defaultId: defaultId,
      defaultLinkHost: defaultLinkHost,
    );
  }
}

final serverDirectoryProvider =
    NotifierProvider<ServerDirectory, ServerDirectoryState>(
      ServerDirectory.new,
    );

final currentServerProvider = Provider<ServerProfile>(
  (ref) => ref.watch(serverDirectoryProvider.select((state) => state.current)),
);

/// 变更先写存储再改状态；写入失败时抛出，状态不变。
final class ServerDirectory extends Notifier<ServerDirectoryState> {
  // 每次变更都整表写回存储，必须串行执行，否则并发的变更会互相覆盖。
  Future<void> _writes = Future.value();

  @override
  ServerDirectoryState build() {
    final environment = ref.watch(buildEnvironmentProvider);
    final store = ref.watch(serverStoreProvider);
    final defaultId = environment.defaultServerId;
    final profiles = <String, ServerProfile>{};
    for (final profile in store.loadProfiles()) {
      if (_permits(environment, profile)) {
        profiles.putIfAbsent(profile.id, () => profile);
      }
    }
    profiles.putIfAbsent(
      defaultId,
      () => ServerProfile(
        origin: environment.defaultOrigin,
        brandName: defaultBrandName,
        addedAtMs: 0,
      ),
    );
    final currentId = store.loadCurrentId();
    return ServerDirectoryState(
      profiles: _ordered(profiles.values, defaultId),
      currentId: profiles.containsKey(currentId) ? currentId! : defaultId,
      defaultId: defaultId,
      defaultLinkHost: environment.defaultLinkHost,
    );
  }

  /// 已保存同一服务器时只更新品牌名，返回保存后的档案。当前构建不允许的地址
  /// （如 release 中的 http）抛出 [ArgumentError]。
  Future<ServerProfile> add(ServerProfile profile) async {
    if (!_permits(ref.read(buildEnvironmentProvider), profile)) {
      throw ArgumentError.value(profile.origin, 'profile', 'Not allowed here');
    }
    return _serially(() async {
      final saved = state.byId(profile.id);
      if (saved != null && saved.brandName == profile.brandName) return saved;
      final added = saved?.withBrandName(profile.brandName) ?? profile;
      final profiles = [
        for (final other in state.profiles)
          if (other.id != added.id) other,
        added,
      ];
      await ref.read(serverStoreProvider).saveProfiles(profiles);
      if (ref.mounted) state = state._copyWith(profiles: profiles);
      return added;
    });
  }

  /// 默认、当前或不存在的服务器返回 false。标记待清扫或写入列表失败时抛出并
  /// 保留服务器；数据删除失败不影响删除服务器。
  Future<bool> remove(String id) {
    return _serially(() async {
      if (id == state.defaultId ||
          id == state.currentId ||
          state.byId(id) == null) {
        return false;
      }
      // 先标记待清扫，再删档案，最后删数据：档案删除后，迟到的请求结果不再写入
      // 这个服务器的凭据；没删掉的数据下次启动时清扫。
      await ref.read(scheduleServerDataSweepProvider)();
      final profiles = [
        for (final profile in state.profiles)
          if (profile.id != id) profile,
      ];
      await ref.read(serverStoreProvider).saveProfiles(profiles);
      if (ref.mounted) state = state._copyWith(profiles: profiles);
      try {
        await ref.read(forgetServerDataProvider)(id);
      } on Object catch (error) {
        // 异常消息可能含带服务器 id 的键名，只记录类型。
        AppLog.warn(
          'server',
          'server data not forgotten',
          type: '${error.runtimeType}',
        );
      }
      return true;
    });
  }

  Future<void> updateBrandName(String id, String brandName) {
    return _serially(() async {
      final saved = state.byId(id);
      if (saved == null || saved.brandName == brandName) return;
      await _saveProfiles([
        for (final profile in state.profiles)
          profile.id == id ? profile.withBrandName(brandName) : profile,
      ]);
    });
  }

  /// 并发获取各服务器的品牌名，取不到的保持原名。不抛出。
  Future<void> refreshBrands() => _refreshBrands(state.profiles);

  /// 只获取当前服务器的品牌名，规则同 [refreshBrands]。
  Future<void> refreshCurrentBrand() => _refreshBrands([state.current]);

  Future<void> _refreshBrands(List<ServerProfile> profiles) async {
    try {
      final probe = ref.read(serverProbeProvider);
      final asked = {
        for (final profile in profiles) profile.id: profile.brandName,
      };
      final fetched = Map.fromEntries(
        await Future.wait([
          for (final profile in profiles)
            probe
                .fetchBrandName(profile.origin)
                .then((name) => MapEntry(profile.id, name)),
        ]),
      );
      await _serially(() async {
        if (!ref.mounted) return;
        // 取名要等最慢的服务器：期间删除的服务器不写回，期间在别处改过的名字
        // （如站点管理刚保存的）也不被覆盖。
        final renamed = {
          for (final profile in state.profiles)
            if (fetched[profile.id] case final name?
                when name != profile.brandName &&
                    profile.brandName == asked[profile.id])
              profile.id: name,
        };
        if (renamed.isEmpty) return;
        await _saveProfiles([
          for (final profile in state.profiles)
            profile.withBrandName(renamed[profile.id] ?? profile.brandName),
        ]);
      });
    } on Object catch (error) {
      AppLog.warn(
        'server',
        'brand names not refreshed',
        type: '${error.runtimeType}',
      );
    }
  }

  /// 只由 `ServerSwitcher` 调用：房间、播放和身份都假定当前服务器就是房间所在
  /// 的服务器，所以要先离开房间，改写后再重置大厅和身份。没有这个服务器时抛出
  /// [ArgumentError]。
  Future<void> setCurrent(String id) {
    return _serially(() async {
      if (state.byId(id) == null) {
        throw ArgumentError.value(id, 'id', 'Unknown server');
      }
      if (id == state.currentId) return;
      await ref.read(serverStoreProvider).saveCurrentId(id);
      if (ref.mounted) state = state._copyWith(currentId: id);
    });
  }

  Future<void> _saveProfiles(List<ServerProfile> profiles) async {
    await ref.read(serverStoreProvider).saveProfiles(profiles);
    if (ref.mounted) state = state._copyWith(profiles: profiles);
  }

  Future<T> _serially<T>(Future<T> Function() change) {
    final result = _writes.then((_) => change());
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

bool _permits(BuildEnvironment environment, ServerProfile profile) {
  if (profile.id == environment.defaultServerId) return true;
  return parseServerOrigin(
    profile.origin,
    allowCleartext: environment.allowsCleartextServers,
  ) is ValidOrigin;
}

List<ServerProfile> _ordered(
  Iterable<ServerProfile> profiles,
  String defaultId,
) {
  int rank(ServerProfile profile) => profile.id == defaultId ? 0 : 1;
  return List.unmodifiable(
    profiles.toList()..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byAdded = a.addedAtMs.compareTo(b.addedAtMs);
      return byAdded != 0 ? byAdded : a.origin.compareTo(b.origin);
    }),
  );
}
