import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class SystemSettings {
  Future<bool> openNotificationSettings();

  Future<void> setMinimizeToTrayOnClose(bool enabled);
}

final systemSettingsProvider = Provider<SystemSettings>((ref) {
  throw UnimplementedError('systemSettings 未注入');
});
