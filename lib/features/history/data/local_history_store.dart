import 'dart:convert';

import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class LocalHistoryStore implements PlayHistoryStore {
  const LocalHistoryStore(
    this._preferences, {
    required this._legacyServerOrigin,
  });

  static const _historyKey = 'alisten.play-history';

  final SharedPreferences _preferences;
  final String _legacyServerOrigin;

  @override
  List<PlayRecord> loadPlays() {
    return parsePlays(
      _preferences.getString(_historyKey),
      legacyServerOrigin: _legacyServerOrigin,
    );
  }

  @override
  Future<void> savePlays(List<PlayRecord> records) {
    return _preferences.setString(
      _historyKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }
}
