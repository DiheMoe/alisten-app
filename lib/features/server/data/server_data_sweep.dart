import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 删除服务器时钥匙串可能删不掉，之后也可能有该服务器的请求结果写回，所以
/// 删除时先标记待清扫，下次启动、发出任何请求前再按服务器列表清扫。
final class ServerDataSweep {
  const ServerDataSweep({
    required this._storage,
    required this._preferences,
    required this._listedServerIds,
    required this._lastRoomKeyPrefix,
  });

  static const pendingKey = 'alisten.server-data-sweep';

  final FlutterSecureStorage _storage;
  final SharedPreferences _preferences;
  final Set<String> _listedServerIds;
  final String _lastRoomKeyPrefix;

  /// 写入失败时抛出。
  static Future<void> markPending(SharedPreferences preferences) async {
    if (!await preferences.setBool(pendingKey, true)) {
      throw const _PreferenceWriteFailed();
    }
  }

  /// 无待清扫或清扫完成时返回 true。失败只记日志、不抛出，标记保留到下次启动
  /// 重试。
  Future<bool> run() async {
    try {
      if (_preferences.getBool(pendingKey) != true) return true;
      const options = SecureCredentialStore.iosOptions;
      final stored = await _storage.readAll(iOptions: options);
      for (final key in stored.keys.toList()) {
        if (_isLeftBehind(SecureCredentialStore.serverIdOf(key))) {
          await _storage.delete(key: key, iOptions: options);
        }
      }
      for (final key in _preferences.getKeys().toList()) {
        if (!key.startsWith(_lastRoomKeyPrefix)) continue;
        final serverId = key.substring(_lastRoomKeyPrefix.length);
        if (_isLeftBehind(serverId) && !await _preferences.remove(key)) {
          throw const _PreferenceWriteFailed();
        }
      }
      if (!await _preferences.remove(pendingKey)) {
        throw const _PreferenceWriteFailed();
      }
      return true;
    } on Object catch (error) {
      // 异常消息可能含带服务器 id 的键名，只记录类型。
      AppLog.warn(
        'server',
        'server data sweep failed',
        type: '${error.runtimeType}',
      );
      return false;
    }
  }

  bool _isLeftBehind(String? serverId) =>
      serverId != null && !_listedServerIds.contains(serverId);
}

final class _PreferenceWriteFailed implements Exception {
  const _PreferenceWriteFailed();
}
