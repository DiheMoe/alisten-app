import 'package:alisten/features/settings/application/settings_state.dart';
import 'package:alisten/features/settings/data/local_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SharedPreferences, LocalSettingsStore)> open(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    final preferences = await SharedPreferences.getInstance();
    return (preferences, LocalSettingsStore(preferences));
  }

  test(
    'an empty store loads the defaults, following the system theme',
    () async {
      final (_, store) = await open({});

      final settings = store.load();

      expect(settings.theme, AppTheme.system);
      expect(settings.reminders, isTrue);
      expect(settings.systemNotifications, isFalse);
      expect(settings.recordSearch, isTrue);
      expect(settings.searchHistoryLimit, 10);
      expect(settings.volume, 75);
      expect(settings.muted, isFalse);
      expect(settings.email, '');
    },
  );

  test('a key of the wrong type falls back alone', () async {
    final (_, store) = await open({
      'alisten.theme': 3,
      'alisten.volume': 'loud',
      'alisten.muted': true,
      'alisten.reminder.enabled': 'yes',
      'alisten.email': 'listener@example.com',
      'alisten.search-history.limit': 20,
    });

    final settings = store.load();

    expect(settings.theme, AppTheme.system);
    expect(settings.volume, 75);
    expect(settings.reminders, isTrue);
    expect(settings.muted, isTrue);
    expect(settings.email, 'listener@example.com');
    expect(settings.searchHistoryLimit, 20);
  });

  test(
    'values outside what the settings offer fall back or are limited',
    () async {
      final (_, store) = await open({
        'alisten.theme': 'neon',
        'alisten.volume': 150,
        'alisten.search-history.limit': 7,
      });

      final settings = store.load();

      expect(settings.theme, AppTheme.system);
      expect(settings.volume, 100);
      expect(settings.searchHistoryLimit, 10);
    },
  );

  test('keys of removed settings are ignored', () async {
    final (_, store) = await open({
      'alisten.font-size': 18,
      'alisten.performance': 'low',
      'alisten.reduced-motion': true,
      'alisten.theme': 'dark',
    });

    expect(store.load().theme, AppTheme.dark);
  });

  test('each setting writes only its own key', () async {
    final writers = <String, Future<void> Function(LocalSettingsStore)>{
      'alisten.theme': (store) => store.setTheme(AppTheme.light),
      'alisten.reminder.enabled': (store) => store.setReminders(false),
      'alisten.reminder.system-notifications': (store) =>
          store.setSystemNotifications(true),
      'alisten.search-history.enabled': (store) => store.setRecordSearch(false),
      'alisten.search-history.limit': (store) => store.setSearchHistoryLimit(5),
      'alisten.volume': (store) => store.setVolume(30),
      'alisten.muted': (store) => store.setMuted(true),
      'alisten.email': (store) => store.setEmail('listener@example.com'),
    };

    for (final MapEntry(:key, :value) in writers.entries) {
      final (preferences, store) = await open({});

      await value(store);

      expect(preferences.getKeys(), {key}, reason: key);
    }
  });

  test('written settings are read back', () async {
    final (_, store) = await open({});

    await store.setTheme(AppTheme.dark);
    await store.setVolume(42);
    await store.setSearchHistoryLimit(50);
    await store.setEmail('listener@example.com');

    final settings = store.load();
    expect(settings.theme, AppTheme.dark);
    expect(settings.volume, 42);
    expect(settings.searchHistoryLimit, 50);
    expect(settings.email, 'listener@example.com');
  });

  test('clearing the email leaves the other settings alone', () async {
    final (preferences, store) = await open({
      'alisten.email': 'listener@example.com',
      'alisten.theme': 'light',
    });

    await store.clearEmail();

    expect(preferences.getString('alisten.email'), '');
    expect(preferences.getString('alisten.theme'), 'light');
  });
}
