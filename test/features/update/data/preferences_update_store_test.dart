import 'package:alisten/features/update/data/preferences_update_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('nothing is known before the first check', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesUpdateStore(await SharedPreferences.getInstance());

    expect(store.readLastAutoCheck(), isNull);
    expect(store.readSkippedVersion(), isNull);
  });

  test('the last check and the skipped version are kept in the ordinary '
      'preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = PreferencesUpdateStore(preferences);
    final at = DateTime.utc(2026, 11, 4, 9, 30);

    await store.writeLastAutoCheck(at);
    await store.writeSkippedVersion('1.2.0');

    expect(
      preferences.getInt('alisten.update.last-auto-check'),
      at.millisecondsSinceEpoch,
    );
    expect(preferences.getString('alisten.update.skipped-version'), '1.2.0');
    final reloaded = PreferencesUpdateStore(preferences);
    expect(reloaded.readLastAutoCheck(), at);
    expect(reloaded.readSkippedVersion(), '1.2.0');
  });

  test('values of the wrong type are taken as missing', () async {
    SharedPreferences.setMockInitialValues({
      'alisten.update.last-auto-check': 'yesterday',
      'alisten.update.skipped-version': 120,
    });
    final store = PreferencesUpdateStore(await SharedPreferences.getInstance());

    expect(store.readLastAutoCheck(), isNull);
    expect(store.readSkippedVersion(), isNull);
  });
}
