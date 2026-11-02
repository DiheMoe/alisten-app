import 'package:alisten/features/room/application/last_room_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class PreferencesLastRoomStore implements LastRoomStore {
  const PreferencesLastRoomStore(this._preferences, {required this._serverId});

  // 不区分服务器的旧键名，只供存储迁移读取。
  static const legacyKey = 'alisten.last-room';

  static const keyPrefix = 'alisten.last-room@';

  static String keyFor(String serverId) => '$keyPrefix$serverId';

  final SharedPreferences _preferences;
  final String _serverId;

  @override
  String? read() => _preferences.getString(keyFor(_serverId));

  @override
  Future<void> write(String room) {
    return _preferences.setString(keyFor(_serverId), room);
  }

  @override
  Future<void> clear() => _preferences.remove(keyFor(_serverId));
}
