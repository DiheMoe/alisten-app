import 'dart:convert';

import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/server/application/server_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class PreferencesServerStore implements ServerStore {
  const PreferencesServerStore(this._preferences);

  /// JSON 数组，元素为 [ServerProfile.toJson]。
  static const profilesKey = 'alisten.servers';
  static const currentKey = 'alisten.current-server';

  final SharedPreferences _preferences;

  @override
  List<ServerProfile> loadProfiles() {
    final stored = _preferences.getString(profilesKey);
    if (stored == null) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [for (final entry in decoded) ?ServerProfile.tryParse(entry)];
  }

  @override
  String? loadCurrentId() => _preferences.getString(currentKey);

  @override
  Future<void> saveProfiles(List<ServerProfile> profiles) {
    return _write(
      profilesKey,
      jsonEncode([for (final p in profiles) p.toJson()]),
    );
  }

  @override
  Future<void> saveCurrentId(String id) => _write(currentKey, id);

  Future<void> _write(String key, String value) async {
    if (!await _preferences.setString(key, value)) {
      throw StateError('server store write failed');
    }
  }
}
