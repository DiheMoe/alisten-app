import 'package:alisten/features/update/application/update_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class PreferencesUpdateStore implements UpdateStore {
  const PreferencesUpdateStore(this._preferences);

  static const _lastAutoCheck = 'alisten.update.last-auto-check';
  static const _skippedVersion = 'alisten.update.skipped-version';

  final SharedPreferences _preferences;

  @override
  DateTime? readLastAutoCheck() {
    final at = _preferences.get(_lastAutoCheck);
    return at is int
        ? DateTime.fromMillisecondsSinceEpoch(at, isUtc: true)
        : null;
  }

  @override
  Future<void> writeLastAutoCheck(DateTime at) {
    return _check(
      _lastAutoCheck,
      _preferences.setInt(_lastAutoCheck, at.millisecondsSinceEpoch),
    );
  }

  @override
  String? readSkippedVersion() {
    final version = _preferences.get(_skippedVersion);
    return version is String ? version : null;
  }

  @override
  Future<void> writeSkippedVersion(String version) {
    return _check(
      _skippedVersion,
      _preferences.setString(_skippedVersion, version),
    );
  }
}

Future<void> _check(String key, Future<bool> write) async {
  if (!await write) throw StateError('Preference $key could not be saved');
}
