import 'dart:io';

import 'package:alisten/features/playback/application/track_start_reminder.dart';
import 'package:alisten/features/settings/index.dart' show NotificationAccess;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract interface class NotificationGateway {
  Future<void> initialize(void Function(String payload) onPayload);

  Future<bool> checkPermission();

  Future<bool> requestPermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });
}

final class PluginNotificationGateway implements NotificationGateway {
  const PluginNotificationGateway(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize(void Function(String payload) onPayload) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_alisten'),
        iOS: DarwinInitializationSettings(
          // iOS 只询问一次权限，所以等用户打开系统通知时才请求，而非启动时。
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) onPayload(payload);
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload != null) onPayload(payload);
    }
  }

  @override
  Future<bool> checkPermission() async {
    if (Platform.isAndroid) {
      final plugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await plugin?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      final plugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await plugin?.checkPermissions().then(
            (permissions) => permissions?.isEnabled ?? false,
          ) ??
          false;
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final plugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await plugin?.requestNotificationsPermission() ?? true;
    }
    if (Platform.isIOS) {
      final plugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await plugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'own-track-reminders',
          '开播提醒',
          channelDescription: '自己点的歌曲开始播放时提醒',
          tag: payload,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}

final _serverIdPart = RegExp(r'^[0-9a-f]{16}$');

final class ReminderNotifier implements TrackStartReminder, NotificationAccess {
  const ReminderNotifier(this._gateway, {required this._serverId});

  final NotificationGateway _gateway;
  final String Function() _serverId;

  /// 处理被点击的提醒（含启动应用的那条）并打开对应房间。载荷为
  /// `服务器id:房间id:条目id`；旧版本发出的是 `房间id:条目id`，此时
  /// `serverId` 为 null。
  Future<void> initialize({
    required void Function(String? serverId, String roomId) onOpenRoom,
  }) {
    return _gateway.initialize((payload) {
      final parts = payload.split(':');
      if (parts.length >= 3 && _serverIdPart.hasMatch(parts[0])) {
        if (parts[1].isNotEmpty) onOpenRoom(parts[0], parts[1]);
      } else if (parts.length >= 2 && parts[0].isNotEmpty) {
        onOpenRoom(null, parts[0]);
      }
    });
  }

  @override
  Future<bool> checkPermission() => _gateway.checkPermission();

  @override
  Future<bool> requestPermission() => _gateway.requestPermission();

  @override
  Future<bool> notify({
    required bool appVisible,
    required bool enabled,
    required bool systemEnabled,
    required bool permissionGranted,
    required String roomId,
    required String entryId,
    required String title,
  }) async {
    if (appVisible || !enabled || !systemEnabled || !permissionGranted) {
      return false;
    }
    final payload = '${_serverId()}:$roomId:$entryId';
    await _gateway.show(
      id: payload.hashCode & 0x7fffffff,
      title: '你点的歌开播了',
      body: title,
      payload: payload,
    );
    return true;
  }
}
