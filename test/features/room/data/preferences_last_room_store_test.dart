import 'package:alisten/features/room/data/preferences_last_room_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('each server keeps its own last room', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = PreferencesLastRoomStore(preferences, serverId: 'aaaa');
    final other = PreferencesLastRoomStore(preferences, serverId: 'bbbb');
    expect(store.read(), isNull);

    await store.write('listen');

    expect(preferences.getString('alisten.last-room@aaaa'), 'listen');
    expect(store.read(), 'listen');
    expect(other.read(), isNull);
  });

  test('clearing removes only its own server\'s room', () async {
    SharedPreferences.setMockInitialValues({
      'alisten.last-room@aaaa': 'listen',
      'alisten.last-room@bbbb': 'other',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = PreferencesLastRoomStore(preferences, serverId: 'aaaa');

    await store.clear();

    expect(preferences.containsKey('alisten.last-room@aaaa'), isFalse);
    expect(store.read(), isNull);
    expect(preferences.getString('alisten.last-room@bbbb'), 'other');
  });

  test('the key of an earlier version is not read', () async {
    SharedPreferences.setMockInitialValues({'alisten.last-room': 'listen'});
    final store = PreferencesLastRoomStore(
      await SharedPreferences.getInstance(),
      serverId: 'aaaa',
    );

    expect(store.read(), isNull);
  });

  test('keys are derived from the server id', () {
    expect(PreferencesLastRoomStore.legacyKey, 'alisten.last-room');
    expect(PreferencesLastRoomStore.keyFor('aaaa'), 'alisten.last-room@aaaa');
  });
}
