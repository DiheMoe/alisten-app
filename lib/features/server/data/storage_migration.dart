import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把旧版本不分服务器的凭据和偏好移到默认服务器名下。
///
/// 先写新键再删旧键，新键已有值时以新键为准；中途失败不写版本号，下次启动从
/// 剩余的旧键继续。
final class StorageMigration {
  const StorageMigration({
    required this._storage,
    required this._preferences,
    required this._defaultServerId,
    required this._preferenceMoves,
  });

  static const versionKey = 'alisten.storage-version';
  static const version = 2;

  final FlutterSecureStorage _storage;
  final SharedPreferences _preferences;
  final String _defaultServerId;
  final Map<String, String> _preferenceMoves;

  /// 迁移完成或无需迁移时返回 true；失败只记日志、不抛出。
  Future<bool> run() async {
    try {
      if ((_preferences.getInt(versionKey) ?? 0) >= version) return true;
      await _moveCredentials();
      await _movePreferences();
      if (!await _preferences.setInt(versionKey, version)) {
        throw const _PreferenceWriteFailed();
      }
      return true;
    } on Object catch (error) {
      // 异常消息可能含键名，只记录类型。
      AppLog.warn(
        'migration',
        'storage migration failed',
        type: '${error.runtimeType}',
      );
      return false;
    }
  }

  Future<void> _moveCredentials() async {
    const options = SecureCredentialStore.iosOptions;
    final stored = await _storage.readAll(iOptions: options);
    final moves = [
      for (final MapEntry(:key, :value) in stored.entries)
        if (_credentialTarget(key) case final target?)
          (
            from: key,
            to: target,
            value: value,
            kept: stored.containsKey(target),
          ),
    ];
    for (final move in moves) {
      if (!move.kept) {
        await _storage.write(
          key: move.to,
          value: move.value,
          iOptions: options,
        );
      }
      await _storage.delete(key: move.from, iOptions: options);
    }
  }

  String? _credentialTarget(String key) {
    if (key == SecureCredentialStore.legacyMemberTokenKey) {
      return SecureCredentialStore.memberTokenKey(_defaultServerId);
    }
    const ticketPrefix = SecureCredentialStore.legacyTicketPrefix;
    if (key.startsWith(ticketPrefix)) {
      return SecureCredentialStore.ticketPrefix(_defaultServerId) +
          key.substring(ticketPrefix.length);
    }
    return null;
  }

  Future<void> _movePreferences() async {
    for (final MapEntry(key: from, value: to) in _preferenceMoves.entries) {
      final value = _preferences.getString(from);
      if (value == null) continue;
      if (!_preferences.containsKey(to) &&
          !await _preferences.setString(to, value)) {
        throw const _PreferenceWriteFailed();
      }
      if (!await _preferences.remove(from)) {
        throw const _PreferenceWriteFailed();
      }
    }
  }
}

final class _PreferenceWriteFailed implements Exception {
  const _PreferenceWriteFailed();
}
