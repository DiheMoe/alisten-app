import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class NotificationAccess {
  Future<bool> checkPermission();

  Future<bool> requestPermission();
}

final notificationAccessProvider = Provider<NotificationAccess>((ref) {
  throw UnimplementedError('notificationAccess 未注入');
});
