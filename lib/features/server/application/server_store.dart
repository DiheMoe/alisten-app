import 'package:alisten/domain/server/server_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ServerStore {
  List<ServerProfile> loadProfiles();
  String? loadCurrentId();

  /// 写入失败时抛出。
  Future<void> saveProfiles(List<ServerProfile> profiles);

  /// 写入失败时抛出。
  Future<void> saveCurrentId(String id);
}

final serverStoreProvider = Provider<ServerStore>((ref) {
  throw UnimplementedError('serverStore 未注入');
});

/// 标记下次启动时清扫已删除服务器的残留数据；标记失败时抛出。
final scheduleServerDataSweepProvider = Provider<Future<void> Function()>((
  ref,
) {
  throw UnimplementedError('scheduleServerDataSweep 未注入');
});

final forgetServerDataProvider =
    Provider<Future<void> Function(String serverId)>((ref) {
      throw UnimplementedError('forgetServerData 未注入');
    });

final serverNowProvider = Provider<int Function()>(
  (ref) =>
      () => DateTime.now().millisecondsSinceEpoch,
);
