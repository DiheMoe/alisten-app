import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class TrackStartReminder {
  /// 应用不可见、提醒开启且已获授权时才显示；返回是否显示。
  Future<bool> notify({
    required bool appVisible,
    required bool enabled,
    required bool systemEnabled,
    required bool permissionGranted,
    required String roomId,
    required String entryId,
    required String title,
  });
}

final trackStartReminderProvider = Provider<TrackStartReminder>((ref) {
  throw UnimplementedError('trackStartReminder 未注入');
});
