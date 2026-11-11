import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // just_audio 通过 127.0.0.1 上的本地代理以明文 HTTP 串流。
  test('release allows cleartext only to the local audio proxy', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final config = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(
      RegExp(r'<base-config\s+cleartextTrafficPermitted="false"')
          .hasMatch(config),
      isTrue,
    );
    final domainConfigs = RegExp(
      r'<domain-config\b([^>]*)>(.*?)</domain-config>',
      dotAll: true,
    ).allMatches(config).toList();
    expect(domainConfigs, hasLength(1));
    expect(
      domainConfigs.single.group(1),
      contains('cleartextTrafficPermitted="true"'),
    );
    final domains = RegExp(r'<domain\b[^>]*>([^<]*)</domain>')
        .allMatches(domainConfigs.single.group(2)!)
        .map((match) => match.group(1)!.trim());
    expect(domains, ['127.0.0.1']);
  });

  // 深层链接只由 app_links 处理；Flutter 自带的处理会把同一链接再路由一次，
  // 绕过 routeFor 的校验。
  test('Flutter built-in deep linking is disabled on the activity', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final activity = RegExp(
      r'<activity\b.*?</activity>',
      dotAll: true,
    ).firstMatch(manifest)!.group(0)!;

    expect(
      RegExp(
        r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+'
        r'android:value="false"\s*/>',
      ).hasMatch(activity),
      isTrue,
    );
  });

  // 备份会把 FlutterSecureStorage 的密文带到无法解密它的设备上。
  test('application opts out of backup', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(
      RegExp(r'<application\b[^>]*android:allowBackup="false"')
          .hasMatch(manifest),
      isTrue,
    );
  });

  test('App Links host comes from the Flutter dart-defines, not localhost', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('"dart-defines"'));
    expect(gradle, contains('"ALISTEN_LINK_HOST"'));
    expect(gradle, contains('"livehouse.dihe.moe"'));
    expect(gradle, isNot(contains('?: "localhost"')));
    expect(gradle, matches(RegExp(r'targetSdk\s*=\s*36\b')));
  });

  // java.net.URI 读不出主机名的源（如主机名带下划线）不能让调试构建或 IDE
  // 同步失败，只能由 release 构建前的检查拒绝。
  test('an unreadable API host fails only the release guard', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final configuration = gradle.substring(
      0,
      gradle.indexOf('val verifyReleaseLinkHost'),
    );

    expect(configuration, isNot(contains('throw ')));
    expect(configuration, contains('removeSurrounding("[", "]")'));
    expect(
      gradle.substring(gradle.indexOf('val verifyReleaseLinkHost')),
      contains('throw GradleException'),
    );
  });

  test('the activity receives plain text shared by other apps', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final activity = RegExp(
      r'<activity\b.*?</activity>',
      dotAll: true,
    ).firstMatch(manifest)!.group(0)!;
    final filters = RegExp(
      r'<intent-filter\b[^>]*>(.*?)</intent-filter>',
      dotAll: true,
    ).allMatches(activity).map((match) => match.group(1)!);

    expect(
      filters.where(
        (filter) =>
            filter.contains(
              '<action android:name="android.intent.action.SEND"/>',
            ) &&
            filter.contains(
              '<category android:name="android.intent.category.DEFAULT"/>',
            ) &&
            filter.contains('<data android:mimeType="text/plain"/>'),
      ),
      hasLength(1),
    );
  });

  // audio_service 缓存的引擎同一时间只服务一个 Activity：分享必须交给正在运行
  // 的 Activity，不能在分享方的任务里另起一个 Activity 抢走引擎。
  test('the activity is single-task, so that a share reaches the running '
      'app', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final activity = RegExp(
      r'<activity\b[^>]*>',
      dotAll: true,
    ).firstMatch(manifest)!.group(0)!;

    expect(activity, contains('android:launchMode="singleTask"'));
  });

  test('the activity forwards shared text on the channel Dart listens to', () {
    final activity = File(
      'android/app/src/main/kotlin/moe/dihe/alisten/MainActivity.kt',
    ).readAsStringSync();
    final source = File('lib/features/search/data/shared_text_source.dart')
        .readAsStringSync();
    const channel = 'moe.dihe.alisten/shared_text';

    expect(activity, contains('"$channel"'));
    expect(source, contains("'$channel'"));
    expect(activity, contains('Intent.ACTION_SEND'));
    expect(activity, contains('Intent.EXTRA_TEXT'));
    expect(activity, contains('override fun onNewIntent'));
    expect(activity, contains('FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY'));
  });

  // Android 12 起读取剪贴板内容会弹出系统提示，所以只凭剪贴板描述取变化时间。
  test('the activity stamps the clipboard without reading its content', () {
    final activity = File(
      'android/app/src/main/kotlin/moe/dihe/alisten/MainActivity.kt',
    ).readAsStringSync();
    final source = File('lib/features/search/data/clipboard_source.dart')
        .readAsStringSync();
    const channel = 'moe.dihe.alisten/clipboard';

    expect(activity, contains('"$channel"'));
    expect(source, contains("'$channel'"));
    expect(activity, contains('"primaryClipStamp"'));
    expect(source, contains("'primaryClipStamp'"));
    expect(activity, contains('primaryClipDescription'));
    expect(activity, contains('.timestamp'));
    expect(
      RegExp(r'getPrimaryClip\(|\.primaryClip(?!Description)\b')
          .hasMatch(activity),
      isFalse,
      reason: 'the content itself is never read natively',
    );
  });

  test('the activity copies text marked sensitive on the clipboard channel '
      'Dart calls', () {
    final activity = File(
      'android/app/src/main/kotlin/moe/dihe/alisten/MainActivity.kt',
    ).readAsStringSync();
    final source = File(
      'lib/features/admin/data/platform_sensitive_clipboard.dart',
    ).readAsStringSync();
    const channel = 'moe.dihe.alisten/clipboard';

    expect(activity, contains('"$channel"'));
    expect(source, contains("'$channel'"));
    expect(activity, contains('"setSensitiveText"'));
    expect(source, contains("'setSensitiveText'"));
    expect(activity, contains('ClipDescription.EXTRA_IS_SENSITIVE'));
    expect(activity, contains('"android.content.extra.IS_SENSITIVE"'));
    expect(activity, contains('setPrimaryClip('));
  });

  test('the activity opens the notification settings on the channel Dart '
      'calls, beside the share and clipboard channels', () {
    final activity = File(
      'android/app/src/main/kotlin/moe/dihe/alisten/MainActivity.kt',
    ).readAsStringSync();
    final source = File(
      'lib/features/settings/data/platform_system_settings.dart',
    ).readAsStringSync();
    const channel = 'moe.dihe.alisten/system_settings';

    expect(activity, contains('"$channel"'));
    expect(source, contains("'$channel'"));
    expect(activity, contains('"openNotificationSettings"'));
    expect(source, contains("'openNotificationSettings'"));
    expect(activity, contains('Settings.ACTION_APP_NOTIFICATION_SETTINGS'));
    expect(activity, contains('Settings.EXTRA_APP_PACKAGE'));
    expect(activity, contains('Intent.FLAG_ACTIVITY_NEW_TASK'));
    for (final attached in [
      'SharedTextChannel.attach(',
      'ClipboardChannel.attach(',
      'SystemSettingsChannel.attach(',
    ]) {
      expect(activity, contains(attached));
    }
  });

  // 这些图标在运行时按名称查找，release 的资源压缩看不到引用。按钮图标被删后，
  // audio_service 同步播放状态时抛出异常，前台服务起不来，应用进后台即被静音。
  test('release keeps the drawables looked up by name at runtime', () {
    final keep = File('android/app/src/main/res/raw/keep.xml')
        .readAsStringSync();
    final kept = RegExp(r'tools:keep="([^"]*)"')
        .firstMatch(keep)!
        .group(1)!
        .split(',')
        .map((name) => name.trim());

    expect(
      kept,
      containsAll(['@drawable/ic_stat_alisten', '@drawable/audio_service_*']),
    );
  });

  test('Android build output is ignored', () {
    expect(File('android/.gitignore').readAsLinesSync(), contains('/build/'));
  });

  test('the gallery write permission is asked for only up to API 29', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final permissions = RegExp(r'<uses-permission\b[^>]*>')
        .allMatches(manifest)
        .map((match) => match.group(0)!)
        .where(
          (element) => element.contains(
            'android:name="android.permission.WRITE_EXTERNAL_STORAGE"',
          ),
        )
        .toList();

    expect(permissions, hasLength(1));
    expect(permissions.single, contains('android:maxSdkVersion="29"'));
  });

  // 回调地址 `moe.dihe.alisten:/auth/github` 没有 host，Android 在没有 host 的
  // 过滤器上不比较 path，所以只写 scheme。
  test('the GitHub callback scheme is declared only on the callback activity, '
      'without a label', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final activity = RegExp(
      r'<activity\s+android:name="com\.linusu\.flutter_web_auth_2\.'
      r'CallbackActivity".*?</activity>',
      dotAll: true,
    ).firstMatch(manifest)?.group(0);

    expect(activity, isNotNull);
    expect(activity, contains('android:exported="true"'));
    expect(activity, contains('android:taskAffinity=""'));
    expect(
      activity,
      contains('<action android:name="android.intent.action.VIEW"/>'),
    );
    expect(
      activity,
      contains('<category android:name="android.intent.category.DEFAULT"/>'),
    );
    expect(
      activity,
      contains('<category android:name="android.intent.category.BROWSABLE"/>'),
    );
    expect(activity, contains('<data android:scheme="moe.dihe.alisten"/>'));
    expect(activity, isNot(contains('android:label')));
    expect(activity, isNot(contains('android:host')));
    expect(
      RegExp('android:scheme="moe\\.dihe\\.alisten"').allMatches(manifest),
      hasLength(1),
    );
  });

  test('App Links open room links, pairing links and shared playlists of the '
      'build host, in one filter', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      RegExp(r'<intent-filter android:autoVerify="true">').allMatches(manifest),
      hasLength(1),
    );
    final filter = RegExp(
      r'<intent-filter android:autoVerify="true">(.*?)</intent-filter>',
      dotAll: true,
    ).firstMatch(manifest)!.group(1)!;

    expect(
      filter,
      contains(
        r'<data android:scheme="https" android:host="${linkHost}" '
        r'android:pathPrefix="/r/"/>',
      ),
    );
    expect(
      filter,
      contains(
        r'<data android:scheme="https" android:host="${linkHost}" '
        r'android:path="/pair"/>',
      ),
    );
    expect(
      filter,
      contains(
        r'<data android:scheme="https" android:host="${linkHost}" '
        r'android:pathPrefix="/s/"/>',
      ),
    );
    expect(RegExp('<data ').allMatches(filter), hasLength(3));
  });
}
