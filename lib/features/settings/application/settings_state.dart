enum AppTheme { dark, light, system }

enum NotificationPermission {
  /// 尚未询问系统或询问失败。
  unknown,
  granted,
  denied,
}

final class LocalSettings {
  const LocalSettings({
    this.theme = AppTheme.system,
    this.reminders = true,
    this.systemNotifications = false,
    this.recordSearch = true,
    this.searchHistoryLimit = 10,
    this.recordHistory = true,
    this.volume = 75,
    this.muted = false,
    this.email = '',
  });

  final AppTheme theme;
  final bool reminders;
  final bool systemNotifications;
  final bool recordSearch;
  final int searchHistoryLimit;
  final bool recordHistory;
  final int volume;
  final bool muted;

  /// 只用来生成 Gravatar 头像，属于输入它时的成员。
  final String email;

  LocalSettings copyWith({
    AppTheme? theme,
    bool? reminders,
    bool? systemNotifications,
    bool? recordSearch,
    int? searchHistoryLimit,
    bool? recordHistory,
    int? volume,
    bool? muted,
    String? email,
  }) {
    return LocalSettings(
      theme: theme ?? this.theme,
      reminders: reminders ?? this.reminders,
      systemNotifications: systemNotifications ?? this.systemNotifications,
      recordSearch: recordSearch ?? this.recordSearch,
      searchHistoryLimit: searchHistoryLimit ?? this.searchHistoryLimit,
      recordHistory: recordHistory ?? this.recordHistory,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      email: email ?? this.email,
    );
  }
}

final class SettingsState {
  const SettingsState({required this.value, required this.permission});

  /// 包含没能写入存储的改动。
  final LocalSettings value;

  final NotificationPermission permission;

  SettingsState copyWith({
    LocalSettings? value,
    NotificationPermission? permission,
  }) {
    return SettingsState(
      value: value ?? this.value,
      permission: permission ?? this.permission,
    );
  }
}
