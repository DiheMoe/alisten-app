import 'package:alisten/features/settings/data/platform_system_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('moe.dihe.alisten/system_settings');
  const windowChannel = MethodChannel('moe.dihe.alisten/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(windowChannel, null);
  });

  test('on Android the activity opens the notification settings', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    final launched = <Uri>[];

    final opened = await PlatformSystemSettings(
      android: true,
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
    ).openNotificationSettings();

    expect(opened, isTrue);
    expect(calls, ['openNotificationSettings']);
    expect(launched, isEmpty);
  });

  test(
    'on Android a missing or failing activity is told as not opened',
    () async {
      final settings = PlatformSystemSettings(
        android: true,
        launch: (_) async => true,
      );

      expect(await settings.openNotificationSettings(), isFalse);

      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'failed'),
      );
      expect(await settings.openNotificationSettings(), isFalse);
    },
  );

  test("on iOS the app's page in the Settings app is opened", () async {
    final launched = <Uri>[];
    var channelUsed = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      channelUsed = true;
      return true;
    });

    final opened = await PlatformSystemSettings(
      android: false,
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
    ).openNotificationSettings();

    expect(opened, isTrue);
    expect(launched, [Uri.parse('app-settings:')]);
    expect(channelUsed, isFalse);
  });

  test('on Windows window tray calls go through the window channel', () async {
    final calls = <(String, Object?)>[];
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add((call.method, call.arguments));
      return null;
    });

    final settings = PlatformSystemSettings(android: false, windows: true);
    await settings.setMinimizeToTrayOnClose(true);

    expect(calls, [('setMinimizeToTrayOnClose', true)]);
  });

  test('on non-Windows window tray calls do not touch the channel', () async {
    var called = false;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      called = true;
      return null;
    });

    final settings = PlatformSystemSettings(android: false, windows: false);
    await settings.setMinimizeToTrayOnClose(true);

    expect(called, isFalse);
  });
}
