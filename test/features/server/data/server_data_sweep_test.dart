import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/server/data/server_data_sweep.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _listed = 'fcd7a878032db68b';
const _removed = 'f475765b53c3272e';

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
    throw PlatformException(code: '-25308', message: 'member_token@$_removed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secure = {
    'member_token@$_listed': 'kept',
    'room_ticket@$_listed.room-1': 'kept',
    'member_token@$_removed': 'left',
    'room_ticket@$_removed.room-1': 'left',
    'room_ticket@$_removed.room%2F2': 'left',
    'login_device@$_listed.mao': 'kept',
    'login_device@$_removed.mao': 'left',
    'member_token': 'legacy',
    'room_ticket.room-1': 'legacy',
    'unrelated': 'u',
  };
  const stored = <String, Object>{
    'alisten.last-room@$_listed': 'kept',
    'alisten.last-room@$_removed': 'left',
    'alisten.last-room': 'legacy',
    'alisten.theme': 'dark',
  };

  Future<SharedPreferences> preferencesWith(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  ServerDataSweep sweep(
    SharedPreferences preferences, {
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) {
    return ServerDataSweep(
      storage: storage,
      preferences: preferences,
      listedServerIds: const {_listed},
      lastRoomKeyPrefix: 'alisten.last-room@',
    );
  }

  Future<Map<String, String>> secureValues() async =>
      Map.of(await const FlutterSecureStorage().readAll());

  test('a pending sweep removes only what servers no longer listed left '
      'behind', () async {
    FlutterSecureStorage.setMockInitialValues(Map.of(secure));
    final preferences = await preferencesWith({
      ...stored,
      ServerDataSweep.pendingKey: true,
    });

    expect(await sweep(preferences).run(), isTrue);

    expect(await secureValues(), {
      'member_token@$_listed': 'kept',
      'room_ticket@$_listed.room-1': 'kept',
      'login_device@$_listed.mao': 'kept',
      'member_token': 'legacy',
      'room_ticket.room-1': 'legacy',
      'unrelated': 'u',
    });
    expect(
      {for (final key in preferences.getKeys()) key: preferences.get(key)},
      {
        'alisten.last-room@$_listed': 'kept',
        'alisten.last-room': 'legacy',
        'alisten.theme': 'dark',
      },
    );
  });

  test('nothing is removed while no sweep is pending', () async {
    FlutterSecureStorage.setMockInitialValues(Map.of(secure));
    final preferences = await preferencesWith(stored);

    expect(await sweep(preferences).run(), isTrue);

    expect(await secureValues(), secure);
    expect(preferences.getString('alisten.last-room@$_removed'), 'left');
  });

  test('a sweep that fails stays pending and logs only the error '
      'type', () async {
    final logs = <String>[];
    AppLog.onRecord = (name, level, message) => logs.add(message);
    addTearDown(() => AppLog.onRecord = null);
    final preferences = await preferencesWith({
      ...stored,
      ServerDataSweep.pendingKey: true,
    });

    expect(
      await sweep(preferences, storage: const _UnreadableStorage()).run(),
      isFalse,
    );

    expect(preferences.getBool(ServerDataSweep.pendingKey), isTrue);
    expect(logs, [contains('type=PlatformException')]);
    expect(logs.single, isNot(contains(_removed)));
  });

  test('marking a sweep keeps it pending for the next start', () async {
    final preferences = await preferencesWith({});

    await ServerDataSweep.markPending(preferences);

    expect(preferences.getBool(ServerDataSweep.pendingKey), isTrue);
  });
}
