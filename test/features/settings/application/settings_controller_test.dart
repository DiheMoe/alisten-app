import 'dart:async';
import 'dart:convert';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/data/reminder_notifier.dart';
import 'package:alisten/features/settings/application/settings_controller.dart';
import 'package:alisten/features/settings/application/settings_state.dart';
import 'package:alisten/features/settings/application/settings_store.dart';
import 'package:alisten/features/settings/application/system_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../settings_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late _FakeGateway gateway;
  late FakeSystemSettings systemSettings;
  late ProviderContainer container;

  Future<ProviderContainer> open([
    Map<String, Object> stored = const {},
  ]) async {
    final opened = ProviderContainer(
      overrides: [
        ...alistenWiring(await loadPreferences(stored)),
        alistenApiProvider.overrideWithValue(api),
        credentialStoreFactoryProvider.overrideWithValue((_) => credentials),
        notificationGatewayProvider.overrideWithValue(gateway),
        systemSettingsProvider.overrideWithValue(systemSettings),
      ],
    );
    addTearDown(opened.dispose);
    return opened;
  }

  SettingsController controllerOf(ProviderContainer container) =>
      container.read(settingsControllerProvider.notifier);

  SettingsState stateOf(ProviderContainer container) =>
      container.read(settingsControllerProvider);

  setUp(() async {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore();
    gateway = _FakeGateway();
    systemSettings = FakeSystemSettings();
    container = await open();
  });

  group('system settings', () {
    test('the notification settings are opened, and whether they opened is '
        'told', () async {
      final settings = controllerOf(container);

      expect(await settings.openNotificationSettings(), isTrue);
      systemSettings.opens = false;
      expect(await settings.openNotificationSettings(), isFalse);
      expect(systemSettings.notificationSettingsOpened, 2);
    });
  });

  group('loading', () {
    test(
      'stored settings are in effect at the first read, before any network',
      () async {
        credentials.memberToken = 'valid-token';
        api.getMeResult = Completer<Member>();
        container = await open({
          'alisten.theme': 'light',
          'alisten.muted': true,
        });

        // 模拟第一帧的读取：此前没有等待任何异步操作。
        final first = container.read(settingsControllerProvider);

        expect(first.value.theme, AppTheme.light);
        expect(first.value.muted, isTrue);
        final restoring = container
            .read(identityControllerProvider.notifier)
            .restore();
        await pumpEventQueue();
        expect(api.getMeCalls, 1);
        expect(stateOf(container).value.theme, AppTheme.light);
        api.getMeResult!.complete(FakeAlistenApi.member);
        await restoring;
      },
    );

    test('settings never create or look up a member by themselves', () async {
      credentials.memberToken = 'valid-token';

      await controllerOf(container).refreshPermission();

      expect(api.getMeCalls, 0);
      expect(api.createMemberCalls, 0);
    });

    test('a change right after the first read keeps the stored rest', () async {
      container = await open({'alisten.theme': 'light', 'alisten.muted': true});

      await controllerOf(container).setVolume(30, persist: true);

      final value = stateOf(container).value;
      expect(value.volume, 30);
      expect(value.theme, AppTheme.light);
      expect(value.muted, isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('alisten.theme'), 'light');
      expect(preferences.getBool('alisten.muted'), isTrue);
    });

    test('keys of removed settings do not stop the load', () async {
      container = await open({
        'alisten.font-size': 18,
        'alisten.performance': 'off',
        'alisten.reduced-motion': true,
        'alisten.theme': 'dark',
      });

      expect(stateOf(container).value.theme, AppTheme.dark);
    });

    test('a key of the wrong type falls back without the others', () async {
      container = await open({'alisten.theme': 7, 'alisten.volume': 20});

      expect(stateOf(container).value.theme, AppTheme.system);
      expect(stateOf(container).value.volume, 20);
    });
  });

  group('persistence', () {
    test(
      'a volume being dragged is applied but written only when released',
      () async {
        final settings = controllerOf(container);
        final preferences = await SharedPreferences.getInstance();

        await settings.setVolume(30, persist: false);

        expect(stateOf(container).value.volume, 30);
        expect(preferences.getKeys(), isEmpty);

        await settings.setVolume(30, persist: true);

        expect(preferences.getKeys(), {'alisten.volume'});
        expect(preferences.getInt('alisten.volume'), 30);
      },
    );

    test('settings changed in turn do not roll each other back', () async {
      final settings = controllerOf(container);

      await settings.setVolume(30, persist: false);
      await settings.setTheme(AppTheme.light);
      await settings.setVolume(30, persist: true);

      final value = stateOf(container).value;
      expect(value.theme, AppTheme.light);
      expect(value.volume, 30);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('alisten.theme'), 'light');
      expect(preferences.getInt('alisten.volume'), 30);
    });

    test('settings changed at the same time all keep their value', () async {
      final settings = controllerOf(container);

      await Future.wait([
        settings.setTheme(AppTheme.dark),
        settings.setVolume(30, persist: true),
        settings.setMuted(true),
        settings.setRecordSearch(false),
      ]);

      final value = stateOf(container).value;
      expect(value.theme, AppTheme.dark);
      expect(value.volume, 30);
      expect(value.muted, isTrue);
      expect(value.recordSearch, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {
        'alisten.theme',
        'alisten.volume',
        'alisten.muted',
        'alisten.search-history.enabled',
      });
    });

    test('a setting is in effect before it has been written', () async {
      final settings = controllerOf(container);

      final writing = settings.setMuted(true);

      expect(stateOf(container).value.muted, isTrue);
      await writing;
    });
  });

  group('a write that fails', () {
    test('is logged and leaves the setting in effect', () async {
      container = ProviderContainer(
        overrides: [
          await preferencesOverride(),
          alistenApiProvider.overrideWithValue(api),
          credentialStoreProvider.overrideWithValue(credentials),
          ...settingsOverrides(
            store: _FailingStore(),
            notifications: ReminderNotifier(gateway, serverId: () => 'server'),
            systemSettings: systemSettings,
          ),
        ],
      );
      addTearDown(container.dispose);
      final settings = controllerOf(container);

      await settings.setTheme(AppTheme.light);
      await settings.setVolume(30, persist: true);

      expect(stateOf(container).value.theme, AppTheme.light);
      expect(stateOf(container).value.volume, 30);
    });
  });

  group('search history', () {
    final records = [
      for (var i = 0; i < 7; i++)
        SearchRecord(
          query: 'q$i',
          source: TrackSource.qq,
          category: SearchCategory.all,
          searchedAtMs: i,
        ),
    ];
    final encoded = jsonEncode(records.map((r) => r.toJson()).toList());

    test('a smaller limit shortens the stored searches', () async {
      container = await open({
        'alisten.search-history': encoded,
        'alisten.search-history.limit': 20,
      });
      final settings = controllerOf(container);

      await settings.setSearchHistoryLimit(5);

      final preferences = await SharedPreferences.getInstance();
      expect(
        parseSearches(preferences.getString('alisten.search-history'), 50),
        hasLength(5),
      );
      expect(preferences.getInt('alisten.search-history.limit'), 5);
    });

    test('a larger limit does not touch the stored searches', () async {
      // 一旦重写搜索历史，这个无效条目就会被丢弃。
      final untouched = encoded.replaceFirst('[', '[7,');
      container = await open({'alisten.search-history': untouched});
      final settings = controllerOf(container);

      await settings.setSearchHistoryLimit(20);
      await settings.setSearchHistoryLimit(20);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('alisten.search-history'), untouched);
    });

    test('a limit the settings do not offer is ignored', () async {
      final settings = controllerOf(container);

      await settings.setSearchHistoryLimit(7);

      expect(stateOf(container).value.searchHistoryLimit, 10);
    });
  });

  group('system notifications', () {
    test('a granted permission turns them on and a refusal off', () async {
      final settings = controllerOf(container);

      await settings.setSystemNotifications(true);

      expect(gateway.requests, 1);
      expect(stateOf(container).permission, NotificationPermission.granted);
      expect(stateOf(container).value.systemNotifications, isTrue);

      await settings.setSystemNotifications(false);

      expect(gateway.requests, 1);
      expect(stateOf(container).value.systemNotifications, isFalse);
    });

    test('a refused permission is shown and keeps them off', () async {
      gateway.granted = false;
      final settings = controllerOf(container);

      await settings.setSystemNotifications(true);

      expect(stateOf(container).permission, NotificationPermission.denied);
      expect(stateOf(container).value.systemNotifications, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getBool('alisten.reminder.system-notifications'),
        isFalse,
      );
    });

    test('returning to the app re-checks the permission', () async {
      final settings = controllerOf(container);
      // 等创建设置时发起的权限检查完成。
      await pumpEventQueue();
      expect(stateOf(container).permission, NotificationPermission.granted);

      gateway.granted = false;
      await settings.refreshPermission();
      expect(stateOf(container).permission, NotificationPermission.denied);

      gateway.granted = true;
      await settings.refreshPermission();

      expect(stateOf(container).permission, NotificationPermission.granted);
    });

    test('a check that cannot be made leaves the permission unknown', () async {
      gateway.checkError = Exception('channel down');
      final settings = controllerOf(container);

      await settings.refreshPermission();

      expect(stateOf(container).permission, NotificationPermission.unknown);
    });
  });

  group('profile', () {
    test(
      'only the changed fields are sent, the email is kept on success',
      () async {
        final settings = controllerOf(container);

        final result = await settings.saveProfile(
          nickname: '新昵称',
          email: stateOf(container).value.email,
        );

        expect(result, isA<MutationSucceeded<Member>>());
        expect(api.updatedName, '新昵称');
        expect(api.updatedEmail, isNull);

        await settings.saveProfile(nickname: '新昵称', email: 'a@example.com');

        expect(api.updatedName, isNull);
        expect(api.updatedEmail, 'a@example.com');
        expect(stateOf(container).value.email, 'a@example.com');
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('alisten.email'), 'a@example.com');
      },
    );

    test('a member created by the save is sent the stored email, since each '
        'server keeps its own avatar', () async {
      container = await open({'alisten.email': 'a@b.c'});
      final settings = controllerOf(container);

      final result = await settings.saveProfile(nickname: '', email: 'a@b.c');

      expect(result, isA<MutationSucceeded<Member>>());
      expect(api.createMemberCalls, 1);
      expect(api.updatedName, isNull);
      expect(api.updatedEmail, 'a@b.c');
      expect(stateOf(container).value.email, 'a@b.c');
    });

    test('an unchanged email is not sent to a member already known', () async {
      credentials.memberToken = 'valid-token';
      container = await open({'alisten.email': 'a@b.c'});
      final settings = controllerOf(container);
      await settings.loadProfile();

      final result = await settings.saveProfile(
        nickname: '新昵称',
        email: 'a@b.c',
      );

      expect(result, isA<MutationSucceeded<Member>>());
      expect(api.updatedName, '新昵称');
      expect(api.updatedEmail, isNull);
    });

    test('a refused save keeps the stored email', () async {
      container = await open({'alisten.email': 'old@example.com'});
      api.updateMeError = unauthorized;
      final settings = controllerOf(container);

      final result = await settings.saveProfile(
        nickname: '',
        email: 'new@example.com',
      );

      expect(result, isA<MutationFailed<Member>>());
      expect(stateOf(container).value.email, 'old@example.com');
    });

    test('a save that breaks unexpectedly has an unknown result: it is '
        'logged without the profile, the member already known is read back, '
        'and the email is not kept', () async {
      final records = <(String, int, String)>[];
      AppLog.onRecord = (name, level, message) =>
          records.add((name, level, message));
      addTearDown(() => AppLog.onRecord = null);
      credentials.memberToken = 'stored-token';
      container = await open({'alisten.email': 'old@example.com'});
      final settings = controllerOf(container);
      await settings.loadProfile();
      expect(api.getMeCalls, 1);
      api
        ..updateMeError = const FormatException('新昵称 me@example.com')
        ..getMeResult = Completer<Member>();

      final result = await settings.saveProfile(
        nickname: '新昵称',
        email: 'me@example.com',
      );
      await pumpEventQueue();
      expect(api.getMeCalls, 2);
      // 服务端实际已保存这次修改。
      api.getMeResult!.complete(
        const Member(id: 'member-id', name: '新昵称', avatarHash: ''),
      );
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<Member>>());
      expect(container.read(identityControllerProvider).member?.name, '新昵称');
      expect(stateOf(container).value.email, 'old@example.com');
      final errors = [
        for (final record in records)
          if (record.$2 >= 1000) record,
      ];
      expect(errors.map((record) => record.$1), ['alisten.settings']);
      expect(
        errors.where(
          (record) =>
              record.$3.contains('example.com') ||
              record.$3.contains('stored-token') ||
              record.$3.contains('新昵称'),
        ),
        isEmpty,
      );
    });

    test('an email entered for a replaced identity is not kept', () async {
      credentials.memberToken = 'old-token';
      api.updateMeResult = Completer<Member>();
      final settings = controllerOf(container);

      final saving = settings.saveProfile(
        nickname: '',
        email: 'new@example.com',
      );
      await pumpEventQueue();
      expect(api.updateMeCalls, 1);
      await container
          .read(identityControllerProvider.notifier)
          .replaceAfterUnauthorized();
      api.updateMeResult!.complete(FakeAlistenApi.member);
      final result = await saving;

      expect(result, isA<MutationSucceeded<Member>>());
      expect(stateOf(container).value.email, '');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('alisten.email'), isNot('new@example.com'));
    });

    test('a rejected member token takes its email with it', () async {
      credentials.memberToken = 'expired-token';
      api.getMeError = unauthorized;
      container = await open({'alisten.email': 'old@example.com'});
      expect(stateOf(container).value.email, 'old@example.com');

      await container.read(identityControllerProvider.notifier).restore();

      expect(stateOf(container).value.email, '');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('alisten.email'), '');
    });

    test(
      'opening the profile restores a member that is not known yet',
      () async {
        credentials.memberToken = 'valid-token';
        final settings = controllerOf(container);

        await settings.loadProfile();
        await settings.loadProfile();

        expect(api.getMeCalls, 1);
        expect(container.read(identityControllerProvider).member?.name, '听众');
      },
    );

    test('a profile that cannot be restored is not an error', () async {
      credentials.memberToken = 'valid-token';
      api.getMeError = Exception('offline');
      final settings = controllerOf(container);

      await settings.loadProfile();

      expect(container.read(identityControllerProvider).member, isNull);
    });
  });
}

final class _FailingStore implements SettingsStore {
  @override
  LocalSettings load() => const LocalSettings();

  @override
  Future<void> setTheme(AppTheme theme) => _fail();

  @override
  Future<void> setReminders(bool enabled) => _fail();

  @override
  Future<void> setSystemNotifications(bool enabled) => _fail();

  @override
  Future<void> setRecordSearch(bool enabled) => _fail();

  @override
  Future<void> setSearchHistoryLimit(int limit) => _fail();

  @override
  Future<void> setRecordHistory(bool enabled) => _fail();

  @override
  Future<void> setVolume(int volume) => _fail();

  @override
  Future<void> setMuted(bool muted) => _fail();

  @override
  Future<void> setEmail(String email) => _fail();

  @override
  Future<void> clearEmail() => _fail();

  Future<void> _fail() async => throw StateError('disk full');
}

final class _FakeGateway implements NotificationGateway {
  bool granted = true;
  int requests = 0;
  Exception? checkError;

  @override
  Future<void> initialize(void Function(String payload) onPayload) async {}

  @override
  Future<bool> checkPermission() async {
    final error = checkError;
    if (error != null) throw error;
    return granted;
  }

  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {}
}
