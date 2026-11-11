import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class CredentialStore {
  Future<String?> readMemberToken();
  Future<void> writeMemberToken(String token);

  /// 尽力删除：失败只记日志、不抛出，因为可能发生在设备锁定时，调用方无从处理。
  Future<void> deleteMemberToken();
  Future<String?> readTicket(String roomId);
  Future<void> writeTicket(String roomId, String ticket);

  /// 与 [deleteMemberToken] 一样尽力而为。
  Future<void> deleteTicket(String roomId);

  /// 只删除本服务器的票据，memberToken 和设备凭证保留；与 [deleteMemberToken]
  /// 一样尽力而为。票据绑定签发它的会话，换会话时全部作废。
  Future<void> deleteTickets();

  Future<String?> readLoginDevice(String username);

  /// 退出登录时不删除：以后用同一个用户名登录时还要带上它。
  Future<void> writeLoginDevice(String username, String device);

  /// 删除本服务器的 memberToken、全部票据和设备凭证，同样尽力而为。
  Future<void> clear();
}

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  throw UnimplementedError('credentialStore 未注入');
});

final credentialStoreFactoryProvider =
    Provider<CredentialStore Function(String serverId)>((ref) {
      throw UnimplementedError('credentialStoreFactory 未注入');
    });

final class SecureCredentialStore implements CredentialStore {
  /// [serverListed] 返回 false 时跳过写入：服务器已从列表中删除，
  /// 之后才返回的请求结果不能再留下它的凭据。
  const SecureCredentialStore(
    this._storage, {
    required this.serverId,
    this._serverListed,
  });

  final String serverId;
  final bool Function()? _serverListed;

  // 开机后解锁过一次即可读取，锁屏时后台播放仍能读到凭据；
  // 不随备份复制到其他设备。
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  // 旧版本不区分服务器时的键名，只有存储迁移还会读取。
  static const legacyMemberTokenKey = 'member_token';
  static const legacyTicketPrefix = 'room_ticket.';

  static const _memberTokenKeyPrefix = 'member_token@';
  static const _ticketKeyPrefix = 'room_ticket@';
  static const _loginDeviceKeyPrefix = 'login_device@';

  static String memberTokenKey(String serverId) =>
      '$_memberTokenKeyPrefix$serverId';

  static String ticketPrefix(String serverId) => '$_ticketKeyPrefix$serverId.';

  static String ticketKey(String serverId, String roomId) {
    return ticketPrefix(serverId) + Uri.encodeComponent(roomId);
  }

  static String loginDeviceKey(String serverId, String username) =>
      '$_loginDeviceKeyPrefix$serverId.$username';

  static String? serverIdOf(String key) {
    if (key.startsWith(_memberTokenKeyPrefix)) {
      return key.substring(_memberTokenKeyPrefix.length);
    }
    for (final prefix in const [_ticketKeyPrefix, _loginDeviceKeyPrefix]) {
      if (!key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length);
      final end = rest.indexOf('.');
      return end < 0 ? null : rest.substring(0, end);
    }
    return null;
  }

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readMemberToken() {
    return _storage.read(key: memberTokenKey(serverId), iOptions: iosOptions);
  }

  @override
  Future<void> writeMemberToken(String token) async {
    if (!_listed()) return;
    await _storage.write(
      key: memberTokenKey(serverId),
      value: token,
      iOptions: iosOptions,
    );
  }

  @override
  Future<void> deleteMemberToken() => _delete(memberTokenKey(serverId));

  @override
  Future<String?> readTicket(String roomId) {
    return _storage.read(
      key: ticketKey(serverId, roomId),
      iOptions: iosOptions,
    );
  }

  @override
  Future<void> writeTicket(String roomId, String ticket) async {
    if (!_listed()) return;
    await _storage.write(
      key: ticketKey(serverId, roomId),
      value: ticket,
      iOptions: iosOptions,
    );
  }

  @override
  Future<void> deleteTicket(String roomId) =>
      _delete(ticketKey(serverId, roomId));

  @override
  Future<void> deleteTickets() =>
      _deleteWhere((key) => key.startsWith(ticketPrefix(serverId)));

  @override
  Future<String?> readLoginDevice(String username) {
    return _storage.read(
      key: loginDeviceKey(serverId, username),
      iOptions: iosOptions,
    );
  }

  @override
  Future<void> writeLoginDevice(String username, String device) async {
    if (!_listed()) return;
    await _storage.write(
      key: loginDeviceKey(serverId, username),
      value: device,
      iOptions: iosOptions,
    );
  }

  @override
  Future<void> clear() => _deleteWhere(
    (key) =>
        key == memberTokenKey(serverId) ||
        key.startsWith(ticketPrefix(serverId)) ||
        key.startsWith('$_loginDeviceKeyPrefix$serverId.'),
  );

  Future<void> _deleteWhere(bool Function(String key) matches) async {
    final List<String> keys;
    try {
      final stored = await _storage.readAll(iOptions: iosOptions);
      keys = [
        for (final key in stored.keys)
          if (matches(key)) key,
      ];
    } on Object {
      AppLog.warn('credentials', 'delete failed', code: 'KEYCHAIN');
      return;
    }
    for (final key in keys) {
      await _delete(key);
    }
  }

  bool _listed() {
    if (_serverListed?.call() ?? true) return true;
    AppLog.debug('credentials', 'write skipped for a removed server');
    return false;
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key, iOptions: iosOptions);
    } on Object {
      AppLog.warn('credentials', 'delete failed', code: 'KEYCHAIN');
    }
  }
}
