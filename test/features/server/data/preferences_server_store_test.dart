import 'dart:convert';

import 'package:alisten/features/server/data/preferences_server_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../server_test_doubles.dart';

void main() {
  test('saved servers read back from a new store', () async {
    final preferences = await loadPreferences();

    await PreferencesServerStore(preferences).saveProfiles([serverB, serverC]);

    expect(PreferencesServerStore(preferences).loadProfiles(), [
      serverB,
      serverC,
    ]);
    expect(jsonDecode(preferences.getString('alisten.servers')!), [
      serverB.toJson(),
      serverC.toJson(),
    ]);
  });

  test('servers stored in a form that cannot be read are left out', () async {
    for (final stored in ['not json', '{}', '"x"']) {
      final preferences = await loadPreferences({'alisten.servers': stored});

      expect(
        PreferencesServerStore(preferences).loadProfiles(),
        isEmpty,
        reason: stored,
      );
    }
  });

  test('only the readable entries of the stored list are read', () async {
    final preferences = await loadPreferences({
      'alisten.servers': jsonEncode([
        serverB.toJson(),
        {'origin': 'https://Example.org', 'brandName': 'x', 'addedAtMs': 1},
        'x',
        serverC.toJson(),
      ]),
    });

    expect(PreferencesServerStore(preferences).loadProfiles(), [
      serverB,
      serverC,
    ]);
  });

  test('the current server is stored by its id', () async {
    final preferences = await loadPreferences();
    final store = PreferencesServerStore(preferences);

    expect(store.loadCurrentId(), isNull);
    await store.saveCurrentId('abc');

    expect(PreferencesServerStore(preferences).loadCurrentId(), 'abc');
    expect(preferences.getString('alisten.current-server'), 'abc');
  });

  test('a write the platform does not keep throws', () async {
    final store = PreferencesServerStore(_RefusingPreferences());

    await expectLater(store.saveProfiles([serverB]), throwsStateError);
    await expectLater(store.saveCurrentId('abc'), throwsStateError);
  });
}

final class _RefusingPreferences implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
