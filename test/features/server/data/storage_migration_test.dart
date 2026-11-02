import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/server/data/storage_migration.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _defaultServerId = 'fcd7a878032db68b';

final class _UnreadableStorage extends FlutterSecureStorage {
  const _UnreadableStorage();

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: '-25308');
  }
}

final class _UnwritableStorage extends FlutterSecureStorage {
  const _UnwritableStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: '-25308', message: 'member_token');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> preferencesWith(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  StorageMigration migration(
    SharedPreferences preferences, {
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) {
    return StorageMigration(
      storage: storage,
      preferences: preferences,
      defaultServerId: _defaultServerId,
      preferenceMoves: const {
        'alisten.last-room': 'alisten.last-room@$_defaultServerId',
      },
    );
  }

  // 测试用的安全存储从 readAll 返回内部 map，须复制一份才能留作对比。
  Future<Map<String, String>> secureValues() async =>
      Map.of(await const FlutterSecureStorage().readAll());

  test('moves the credentials and the last room to the default '
      'server', () async {
    FlutterSecureStorage.setMockInitialValues({
      'member_token': 'm',
      'room_ticket.room-1': 't1',
      'room_ticket.room%2F2': 't2',
      'unrelated': 'u',
    });
    final preferences = await preferencesWith({'alisten.last-room': 'listen'});

    expect(await migration(preferences).run(), isTrue);

    expect(await secureValues(), {
      'member_token@$_defaultServerId': 'm',
      'room_ticket@$_defaultServerId.room-1': 't1',
      'room_ticket@$_defaultServerId.room%2F2': 't2',
      'unrelated': 'u',
    });
    expect(
      preferences.getString('alisten.last-room@$_defaultServerId'),
      'listen',
    );
    expect(preferences.containsKey('alisten.last-room'), isFalse);
    expect(preferences.getInt('alisten.storage-version'), 2);
  });

  test('values already under the new keys win over the old ones', () async {
    FlutterSecureStorage.setMockInitialValues({
      'member_token@$_defaultServerId': 'new',
      'member_token': 'old',
    });
    final preferences = await preferencesWith({
      'alisten.last-room@$_defaultServerId': 'new-room',
      'alisten.last-room': 'old-room',
    });

    expect(await migration(preferences).run(), isTrue);

    expect(await secureValues(), {'member_token@$_defaultServerId': 'new'});
    expect(
      preferences.getString('alisten.last-room@$_defaultServerId'),
      'new-room',
    );
    expect(preferences.containsKey('alisten.last-room'), isFalse);
  });

  test('running again changes nothing and no longer reads the secure '
      'storage', () async {
    FlutterSecureStorage.setMockInitialValues({
      'member_token': 'm',
      'room_ticket.room-1': 't1',
    });
    final preferences = await preferencesWith({'alisten.last-room': 'listen'});

    expect(await migration(preferences).run(), isTrue);
    final secure = await secureValues();
    final stored = {
      for (final key in preferences.getKeys()) key: preferences.get(key),
    };
    expect(await migration(preferences).run(), isTrue);

    expect(await secureValues(), secure);
    expect({
      for (final key in preferences.getKeys()) key: preferences.get(key),
    }, stored);
    expect(
      await migration(preferences, storage: const _UnreadableStorage()).run(),
      isTrue,
    );
  });

  test('a failure keeps the old keys, logs only the error type and is '
      'retried on the next run', () async {
    final logs = <String>[];
    AppLog.onRecord = (name, level, message) {
      if (name == 'alisten.migration') logs.add(message);
    };
    addTearDown(() => AppLog.onRecord = null);
    const old = {
      'member_token': 'm',
      'room_ticket.room-1': 't1',
      'room_ticket.room%2F2': 't2',
    };
    FlutterSecureStorage.setMockInitialValues(Map.of(old));
    final preferences = await preferencesWith({'alisten.last-room': 'listen'});

    expect(
      await migration(preferences, storage: const _UnwritableStorage()).run(),
      isFalse,
    );

    expect(await secureValues(), old);
    expect(preferences.getString('alisten.last-room'), 'listen');
    expect(preferences.containsKey('alisten.storage-version'), isFalse);
    expect(logs, [
      allOf(
        contains('storage migration failed'),
        contains('type=PlatformException'),
      ),
    ]);
    expect(logs.single, isNot(contains('member_token')));
    expect(logs.single, isNot(contains('-25308')));

    expect(await migration(preferences).run(), isTrue);

    expect(await secureValues(), {
      'member_token@$_defaultServerId': 'm',
      'room_ticket@$_defaultServerId.room-1': 't1',
      'room_ticket@$_defaultServerId.room%2F2': 't2',
    });
    expect(
      preferences.getString('alisten.last-room@$_defaultServerId'),
      'listen',
    );
    expect(preferences.getInt('alisten.storage-version'), 2);
  });

  test('without old data the version is still recorded', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = await preferencesWith({});

    expect(await migration(preferences).run(), isTrue);

    expect(await secureValues(), isEmpty);
    expect(preferences.getInt('alisten.storage-version'), 2);
  });
}
