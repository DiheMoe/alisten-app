import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/features/settings/data/local_settings_store.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

List<Override> settingsOverrides({
  SettingsStore? store,
  Future<void> Function(int limit)? trimSearchHistory,
  NotificationAccess? notifications,
  SystemSettings? systemSettings,
}) {
  return [
    settingsStoreProvider.overrideWith(
      (ref) =>
          store ?? LocalSettingsStore(ref.watch(sharedPreferencesProvider)),
    ),
    trimSearchHistoryProvider.overrideWithValue(
      trimSearchHistory ?? (limit) async {},
    ),
    notificationAccessProvider.overrideWithValue(
      notifications ?? FakeNotificationAccess(),
    ),
    systemSettingsProvider.overrideWithValue(
      systemSettings ?? FakeSystemSettings(),
    ),
  ];
}

final class FakeNotificationAccess implements NotificationAccess {
  bool granted = false;

  @override
  Future<bool> checkPermission() async => granted;

  @override
  Future<bool> requestPermission() async => granted;
}

final class FakeSystemSettings implements SystemSettings {
  int notificationSettingsOpened = 0;

  bool opens = true;

  @override
  Future<bool> openNotificationSettings() async {
    notificationSettingsOpened++;
    return opens;
  }
}
