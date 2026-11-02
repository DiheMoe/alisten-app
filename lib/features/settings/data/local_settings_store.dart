import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/features/settings/application/settings_state.dart';
import 'package:alisten/features/settings/application/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每项设置单独存一个键：读取时缺失或类型不对的键各自取默认值，写入只改当前
/// 设置的键，几乎同时的改动不会互相覆盖。
final class LocalSettingsStore implements SettingsStore {
  const LocalSettingsStore(this._preferences);

  static const _theme = 'alisten.theme';
  static const _reminders = 'alisten.reminder.enabled';
  static const _systemNotifications = 'alisten.reminder.system-notifications';
  static const _recordSearch = 'alisten.search-history.enabled';
  static const _searchHistoryLimit = 'alisten.search-history.limit';
  static const _recordHistory = 'alisten.play-history.enabled';
  static const _volume = 'alisten.volume';
  static const _muted = 'alisten.muted';
  static const _email = 'alisten.email';

  final SharedPreferences _preferences;

  @override
  LocalSettings load() {
    const defaults = LocalSettings();
    final theme = _read<String>(_theme, '');
    final limit = _read<int>(_searchHistoryLimit, 0);
    return LocalSettings(
      theme: AppTheme.values.firstWhere(
        (candidate) => candidate.name == theme,
        orElse: () => defaults.theme,
      ),
      reminders: _read(_reminders, defaults.reminders),
      systemNotifications: _read(
        _systemNotifications,
        defaults.systemNotifications,
      ),
      recordSearch: _read(_recordSearch, defaults.recordSearch),
      searchHistoryLimit: searchHistoryLimits.contains(limit)
          ? limit
          : defaults.searchHistoryLimit,
      recordHistory: _read(_recordHistory, defaults.recordHistory),
      volume: _read(_volume, defaults.volume).clamp(0, 100),
      muted: _read(_muted, defaults.muted),
      email: _read(_email, defaults.email),
    );
  }

  @override
  Future<void> setTheme(AppTheme theme) {
    return _check(_theme, _preferences.setString(_theme, theme.name));
  }

  @override
  Future<void> setReminders(bool enabled) {
    return _check(_reminders, _preferences.setBool(_reminders, enabled));
  }

  @override
  Future<void> setSystemNotifications(bool enabled) {
    return _check(
      _systemNotifications,
      _preferences.setBool(_systemNotifications, enabled),
    );
  }

  @override
  Future<void> setRecordSearch(bool enabled) {
    return _check(_recordSearch, _preferences.setBool(_recordSearch, enabled));
  }

  @override
  Future<void> setSearchHistoryLimit(int limit) {
    return _check(
      _searchHistoryLimit,
      _preferences.setInt(_searchHistoryLimit, limit),
    );
  }

  @override
  Future<void> setRecordHistory(bool enabled) {
    return _check(
      _recordHistory,
      _preferences.setBool(_recordHistory, enabled),
    );
  }

  @override
  Future<void> setVolume(int volume) {
    return _check(_volume, _preferences.setInt(_volume, volume));
  }

  @override
  Future<void> setMuted(bool muted) {
    return _check(_muted, _preferences.setBool(_muted, muted));
  }

  @override
  Future<void> setEmail(String email) {
    return _check(_email, _preferences.setString(_email, email));
  }

  @override
  Future<void> clearEmail() => setEmail('');

  T _read<T extends Object>(String key, T fallback) {
    final value = _preferences.get(key);
    return value is T ? value : fallback;
  }
}

Future<void> _check(String key, Future<bool> write) async {
  if (!await write) throw StateError('Setting $key could not be saved');
}
