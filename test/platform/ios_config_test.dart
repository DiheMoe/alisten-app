import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // target 级构建设置优先于 xcconfig，在 target 上设置 INFOPLIST_FILE 会让
  // Debug 悄悄用上 Release 的 plist。
  test('Runner takes its Info.plist from the configuration xcconfig', () {
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();

    expect(
      RegExp(r'^\s*INFOPLIST_FILE\s*=', multiLine: true).hasMatch(project),
      isFalse,
    );
    expect(
      File('ios/Flutter/Debug.xcconfig').readAsLinesSync(),
      contains('INFOPLIST_FILE=Runner/Debug-Info.plist'),
    );
    expect(
      File('ios/Flutter/Release.xcconfig').readAsLinesSync(),
      contains('INFOPLIST_FILE=Runner/Info.plist'),
    );
  });

  // 存在 NSAllowsLocalNetworking 时 ATS 会忽略 NSAllowsArbitraryLoads，因此
  // 允许任意连接的 Debug 不能带这一项。
  test('Debug Info.plist differs from Release only in App Transport '
      'Security', () {
    final release = File('ios/Runner/Info.plist').readAsStringSync();
    final debug = File('ios/Runner/Debug-Info.plist').readAsStringSync();

    expect(_transportSecurity(release), {
      'NSAllowsArbitraryLoads': false,
      'NSAllowsLocalNetworking': true,
    });
    expect(_transportSecurity(debug), {'NSAllowsArbitraryLoads': true});
    expect(
      debug.replaceFirst(_transportSecurityDict, ''),
      release.replaceFirst(_transportSecurityDict, ''),
    );
  });

  // FlutterAppDelegate 只有成为通知中心的 delegate，才会把通知回调转发给插件。
  test('AppDelegate installs itself as the notification center delegate', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(delegate, contains('import UserNotifications'));
    expect(
      delegate,
      contains(
        'UNUserNotificationCenter.current().delegate = '
        'self as? UNUserNotificationCenterDelegate',
      ),
    );
  });

  for (final name in ['Info.plist', 'Debug-Info.plist']) {
    group('ios/Runner/$name', () {
      late String plist;
      setUp(() => plist = File('ios/Runner/$name').readAsStringSync());

      test('disables Flutter built-in deep linking', () {
        expect(
          plist,
          matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')),
        );
      });

      // 未声明中文本地化时，VoiceOver 会用英文朗读 Flutter 组件。
      test('is Chinese localized', () {
        expect(
          plist,
          matches(
            RegExp(
              r'<key>CFBundleDevelopmentRegion</key>\s*'
              r'<string>zh_CN</string>',
            ),
          ),
        );
        expect(
          plist,
          matches(
            RegExp(
              r'<key>CFBundleLocalizations</key>\s*<array>\s*'
              r'<string>zh_CN</string>\s*</array>',
            ),
          ),
        );
      });

      test('declares exempt encryption', () {
        expect(
          plist,
          matches(
            RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>'),
          ),
        );
      });

      // 缺少这项说明时，首次保存到相册会使应用崩溃。
      test('says why it adds photos to the library', () {
        expect(
          plist,
          matches(
            RegExp(
              r'<key>NSPhotoLibraryAddUsageDescription</key>\s*'
              r'<string>保存登录二维码到相册</string>',
            ),
          ),
        );
      });
    });
  }

  // 关联域名由这项设置替换进 entitlements；Dart 默认使用同一主机名。
  test('Universal Links host defaults to the production host', () {
    for (final name in ['Debug', 'Release']) {
      expect(
        File('ios/Flutter/$name.xcconfig').readAsLinesSync(),
        contains('ALISTEN_LINK_HOST=livehouse.dihe.moe'),
      );
    }
  });
}

final _transportSecurityDict = RegExp(
  r'<key>NSAppTransportSecurity</key>\s*<dict>(.*?)</dict>',
  dotAll: true,
);

Map<String, bool> _transportSecurity(String plist) {
  final dict = _transportSecurityDict.firstMatch(plist)!.group(1)!;
  return {
    for (final entry in RegExp(
      r'<key>(\w+)</key>\s*<(true|false)/>',
    ).allMatches(dict))
      entry.group(1)!: entry.group(2) == 'true',
  };
}
