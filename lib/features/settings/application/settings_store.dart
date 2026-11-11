import 'package:alisten/features/settings/application/settings_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  throw UnimplementedError('settingsStore 未注入');
});

abstract interface class SettingsStore {
  /// 缺失或读不出的设置取默认值。
  LocalSettings load();

  Future<void> setTheme(AppTheme theme);

  Future<void> setReminders(bool enabled);

  Future<void> setSystemNotifications(bool enabled);

  Future<void> setRecordSearch(bool enabled);

  Future<void> setSearchHistoryLimit(int limit);

  Future<void> setVolume(int volume);

  Future<void> setMuted(bool muted);

  Future<void> setEmail(String email);

  Future<void> clearEmail();
}
