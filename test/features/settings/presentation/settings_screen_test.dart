import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alisten/app/app_version.dart';
import 'package:alisten/app/assembly.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' show protocolVersion;
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/features/update/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_test_harness.dart';
import '../../../core/avatar/avatar_test_doubles.dart';
import '../../../core/cache/cover_cache_test_doubles.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../update/update_test_doubles.dart';
import '../settings_test_doubles.dart';

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(AlistenTextField, label),
  matching: find.byType(EditableText),
);

Future<void> _openSettings(
  WidgetTester tester, {
  MediaQueryData system = const MediaQueryData(),
  FakeAlistenApi? api,
  FakeCredentialStore? credentials,
  FakeNotificationGateway? notifications,
  FakeSystemSettings? systemSettings,
  FakeCoverCache? coverCache,
  FakeAvatarCache? avatarCache,
  FakeReleaseSource? releases,
  Map<String, Object> preferences = const {},
}) async {
  tester.view
    ..physicalSize = const Size(360, 780) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await pumpAlistenApp(
    tester,
    system: system,
    api: api,
    credentials: credentials,
    notifications: notifications,
    systemSettings: systemSettings,
    coverCache: coverCache,
    avatarCache: avatarCache,
    releases: releases,
    preferences: preferences,
  );
  appContainer(tester).read(routerProvider).go('/settings');
  await tester.pumpAndSettle();
}

// 测试绑定不登记 Flutter 工具生成的 NOTICES（发布版由 ServicesBinding 登记），
// 这里按同样格式登记本次构建的 NOTICES，页面才会列出真实的依赖。
void _registerBuiltNotices() {
  LicenseRegistry.addLicense(() async* {
    final compressed = await rootBundle.load('NOTICES.Z');
    final notices = utf8.decode(gzip.decode(compressed.buffer.asUint8List()));
    for (final license in notices.split('\n${'-' * 80}\n')) {
      final split = license.indexOf('\n\n');
      if (split < 0) continue;
      yield LicenseEntryWithLineBreaks(
        license.substring(0, split).split('\n'),
        license.substring(split + 2),
      );
    }
  });
}

Future<void> _showLicense(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byType(LicensesScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the settings leave out what follows the system or the player, '
      'and name no roles', (tester) async {
    await _openSettings(tester);

    for (final text in ['界面字号', '资源档位', '减少动态效果', '本机音量', '房主', '管理员']) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
    await _show(tester, find.text(protocolVersion));
    expect(find.text(appVersion), findsOneWidget);
    for (final text in ['界面字号', '资源档位', '减少动态效果', '本机音量', '房主', '管理员']) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
  });

  testWidgets('long long short long long short on the version row opens the '
      'servers, and the row still reads as the version alone', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var opened = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: SettingsScreen(
            appVersion: appVersion,
            protocolVersion: protocolVersion,
            onProfileResult: (_) {},
            onNotice: (_, _) {},
            onOpenLicenses: () {},
            onOpenServers: () => opened++,
            onOpenAdmin: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _show(tester, find.text('版本'));
    final row = find.text('版本');
    // TapRhythm 包在合并语义的版本行之外，点按动作会出现在外层节点上。
    void expectNoTap() {
      for (
        SemanticsNode? node = tester.getSemantics(row);
        node != null;
        node = node.parent
      ) {
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      }
    }

    expectNoTap();
    expect(
      tester.getSemantics(row).label,
      allOf(contains('版本'), contains(appVersion)),
    );

    for (final (index, long) in [
      true,
      true,
      false,
      true,
      true,
      false,
    ].indexed) {
      expect(opened, 0, reason: 'before beat ${index + 1}');
      final gesture = await tester.startGesture(tester.getCenter(row));
      await tester.pump(Duration(milliseconds: long ? 500 : 100));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(opened, 1);
    expectNoTap();
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('short short short long twice on the version row, then a 2 s '
      'hold, opens the site admin; the beats alone open nothing', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var servers = 0;
    var admin = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: SettingsScreen(
            appVersion: appVersion,
            protocolVersion: protocolVersion,
            onProfileResult: (_) {},
            onNotice: (_, _) {},
            onOpenLicenses: () {},
            onOpenServers: () => servers++,
            onOpenAdmin: () => admin++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _show(tester, find.text('版本'));
    final row = tester.getCenter(find.text('版本'));
    Future<void> fate() async {
      for (final long in [
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
      ]) {
        final gesture = await tester.startGesture(row);
        await tester.pump(Duration(milliseconds: long ? 500 : 100));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await fate();
    await tester.pump(const Duration(seconds: 2));
    expect(admin, 0, reason: 'the beats alone');
    expect(servers, 0);

    await fate();
    final hold = await tester.startGesture(row);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(admin, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(admin, 1);
    await hold.up();
    await tester.pumpAndSettle();

    expect(admin, 1);
    expect(servers, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a theme chosen takes effect at once and is kept', (
    tester,
  ) async {
    await _openSettings(
      tester,
      system: const MediaQueryData(platformBrightness: Brightness.dark),
    );
    Brightness brightness() =>
        Theme.of(tester.element(find.text('外观'))).brightness;
    expect(
      brightness(),
      Brightness.dark,
      reason:
          'the default follows the '
          'system',
    );

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();

    expect(brightness(), Brightness.light);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('alisten.theme'), 'light');
  });

  testWidgets('notifications the system refused say so and lead to the '
      'system settings', (tester) async {
    final systemSettings = FakeSystemSettings();
    await _openSettings(
      tester,
      notifications: FakeNotificationGateway(),
      systemSettings: systemSettings,
    );
    await _show(tester, find.text('去系统设置'));

    expect(find.text('已被系统拒绝'), findsOneWidget);
    await tester.tap(find.text('去系统设置'));
    await tester.pump();
    expect(systemSettings.notificationSettingsOpened, 1);
  });

  testWidgets('system settings that cannot be opened say so as a failure', (
    tester,
  ) async {
    final systemSettings = FakeSystemSettings()..opens = false;
    await _openSettings(
      tester,
      notifications: FakeNotificationGateway(),
      systemSettings: systemSettings,
    );
    await _show(tester, find.text('去系统设置'));

    await tester.tap(find.text('去系统设置'));
    await tester.pumpAndSettle();

    expect(find.textContaining('没能打开系统设置'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ToastHost),
        matching: find.byIcon(Icons.error_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('allowed notifications offer no way to the system settings', (
    tester,
  ) async {
    await _openSettings(
      tester,
      notifications: FakeNotificationGateway()..granted = true,
    );
    await _show(tester, find.text('已允许'));

    expect(find.text('去系统设置'), findsNothing);
    expect(find.text('已被系统拒绝'), findsNothing);
  });

  testWidgets('the storage settings, between privacy and about, show how much '
      'covers and avatars take together', (tester) async {
    await _openSettings(
      tester,
      coverCache: FakeCoverCache(bytes: (21.4 * 1024 * 1024).round()),
      avatarCache: FakeAvatarCache(bytes: 2 * 1024 * 1024),
    );
    await _show(tester, find.text('版本'));

    expect(find.text('23.4 MB'), findsOneWidget);
    expect(find.text('封面缓存'), findsNothing);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('存储'), greaterThan(top('记录播放历史')));
    expect(top('存储'), lessThan(top('图片缓存')));
    expect(top('清除缓存'), lessThan(top('关于')));
  });

  group('open-source licenses', () {
    setUpAll(() {
      registerBundledLicenses();
      _registerBuiltNotices();
    });

    // rootBundle 缓存 loadString 的 Future：上一个用例在假时间中留下的 Future
    // 在下一个用例中永远不会完成，许可列表将一直读不出来。
    setUp(rootBundle.clear);

    // gal 在 Android 上带入 commons-imaging，Apache-2.0 要求随分发附上其许可证
    // 和 NOTICE。
    testWidgets('the licenses list commons-imaging with its NOTICE and its '
        'Apache License', (tester) async {
      await _openSettings(tester);
      await _show(tester, find.text('开源许可'));
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();

      await _showLicense(tester, find.text('commons-imaging'));
      expect(find.text('commons-imaging'), findsOneWidget);
      expect(
        find.textContaining(
          'Copyright 2007-2022 The Apache Software Foundation',
        ),
        findsNothing,
      );

      await tester.tap(find.text('commons-imaging'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Apache Commons Imaging Copyright 2007-2022 The Apache Software '
          'Foundation',
        ),
        findsOneWidget,
      );
      await _showLicense(
        tester,
        find.textContaining('Version 2.0, January 2004'),
      );
      expect(find.textContaining('Version 2.0, January 2004'), findsOneWidget);
      await _showLicense(
        tester,
        find.textContaining('END OF TERMS AND CONDITIONS'),
      );
      expect(
        find.textContaining('END OF TERMS AND CONDITIONS'),
        findsOneWidget,
      );
    });

    testWidgets('the about section opens the licenses of the bundled font and '
        'of the dependencies, each expanding to its full text', (tester) async {
      await _openSettings(tester);
      await _show(tester, find.text('开源许可'));
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();

      await _showLicense(tester, find.text('dio'));
      expect(find.text('dio'), findsOneWidget);
      await _showLicense(tester, find.text('Plus Jakarta Sans'));
      expect(
        find.textContaining('SIL OPEN FONT LICENSE Version 1.1'),
        findsNothing,
      );

      await tester.tap(find.text('Plus Jakarta Sans'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('SIL OPEN FONT LICENSE Version 1.1'),
        findsOneWidget,
      );
      expect(
        find.textContaining('The Plus Jakarta Sans Project Authors'),
        findsOneWidget,
      );

      await tester.tap(find.text('Plus Jakarta Sans'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('SIL OPEN FONT LICENSE Version 1.1'),
        findsNothing,
      );

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconCircleButton && widget.semanticLabel == '返回',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LicensesScreen), findsNothing);
      expect(find.text('开源许可'), findsOneWidget);
    });
  });

  group('checking for updates from the about section', () {
    // 启动时的自动检查已用掉一次请求，之后都是手动检查。
    Future<FakeReleaseSource> openAbout(
      WidgetTester tester, {
      Map<String, Object> preferences = const {},
    }) async {
      final releases = FakeReleaseSource();
      await _openSettings(tester, releases: releases, preferences: preferences);
      await _show(tester, find.text('检查更新'));
      expect(find.text('协议版本'), findsOneWidget);
      return releases;
    }

    Finder toastIcon(IconData icon) => find.descendant(
      of: find.byType(ToastHost),
      matching: find.byIcon(icon),
    );

    testWidgets('says the app is up to date', (tester) async {
      final releases = await openAbout(tester);
      final launchCalls = releases.calls;

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(releases.calls, launchCalls + 1);
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.textContaining('发现新版本'), findsNothing);
    });

    testWidgets('shows the panel of a newer version, even one skipped '
        'before', (tester) async {
      final releases = await openAbout(
        tester,
        preferences: {'alisten.update.skipped-version': '9.0.0'},
      );
      releases.release = testRelease(tag: 'v9.0.0');

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 9.0.0'), findsOneWidget);
      expect(find.text('已是最新版本'), findsNothing);
    });

    testWidgets('that fails says so as a failure', (tester) async {
      final releases = await openAbout(tester);
      releases.error = const ReleaseUnavailable();

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.text('检查更新失败，请稍后再试。'), findsOneWidget);
      expect(toastIcon(Icons.error_rounded), findsOneWidget);
    });

    testWidgets('shows the check in progress and cannot be started again '
        'meanwhile', (tester) async {
      final semantics = tester.ensureSemantics();
      final releases = await openAbout(tester);
      final launchCalls = releases.calls;
      final holding = releases.holding = Completer<void>();

      await tester.tap(find.text('检查更新'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('检查更新'),
            matching: find.byType(Pressable),
          ),
          matching: find.byType(BusyIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('检查更新')),
        isSemantics(value: busySemanticValue),
      );
      await tester.tap(find.text('检查更新'), warnIfMissed: false);
      await tester.pump();
      expect(releases.calls, launchCalls + 1);

      holding.complete();
      await tester.pumpAndSettle();
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.byType(BusyIndicator), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('the image cache size shows a placeholder until it is '
      'measured', (tester) async {
    final measuring = Completer<void>();
    await _openSettings(
      tester,
      coverCache: FakeCoverCache(bytes: 10 * 1024)..measuring = measuring,
    );
    await _show(tester, find.text('清除缓存'));
    expect(find.text('计算中…'), findsOneWidget);

    measuring.complete();
    await tester.pumpAndSettle();

    expect(find.text('计算中…'), findsNothing);
    // 不足 0.1 MB 的缓存不显示为“0.0 MB”，以免看起来像是空的。
    expect(find.text('0.1 MB'), findsOneWidget);
  });

  testWidgets('an image cache size that cannot be measured says so', (
    tester,
  ) async {
    final measuring = Completer<void>();
    await _openSettings(
      tester,
      coverCache: FakeCoverCache()..measuring = measuring,
    );
    await _show(tester, find.text('清除缓存'));

    measuring.completeError(const FileSystemException('unreadable'));
    await tester.pumpAndSettle();

    expect(find.text('计算中…'), findsNothing);
    expect(find.text('无法计算'), findsOneWidget);
  });

  testWidgets('clearing the image cache empties covers and avatars once and '
      'shows it empty', (tester) async {
    final clearing = Completer<void>();
    final cache = FakeCoverCache(bytes: 5 * 1024 * 1024)..clearing = clearing;
    final avatars = FakeAvatarCache(bytes: 1024 * 1024);
    await _openSettings(tester, coverCache: cache, avatarCache: avatars);
    await _show(tester, find.text('清除缓存'));
    expect(find.text('6.0 MB'), findsOneWidget);
    PillButton clear() =>
        tester.widget<PillButton>(find.widgetWithText(PillButton, '清除缓存'));

    await tester.tap(find.text('清除缓存'));
    await tester.pump();
    expect(clear().busy, isTrue);
    await tester.tap(find.text('清除缓存'));
    await tester.pump();

    clearing.complete();
    await tester.pumpAndSettle();

    expect(cache.clears, 1);
    expect(avatars.clears, 1);
    expect(find.text('0 MB'), findsOneWidget);
    expect(clear().busy, isFalse);
    expect(find.text('已清除图片缓存'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ToastHost),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an image cache that cannot be cleared says so as a failure, '
      'and still clears what it can', (tester) async {
    final cache = FakeCoverCache(bytes: 5 * 1024 * 1024)
      ..clearError = const FileSystemException('busy');
    final avatars = FakeAvatarCache(bytes: 1024 * 1024);
    await _openSettings(tester, coverCache: cache, avatarCache: avatars);
    await _show(tester, find.text('清除缓存'));

    await tester.tap(find.text('清除缓存'));
    await tester.pumpAndSettle();

    expect(cache.clears, 1);
    expect(avatars.clears, 1);
    expect(find.text('没能清除图片缓存，请稍后再试。'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ToastHost),
        matching: find.byIcon(Icons.error_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('5.0 MB'), findsOneWidget);
    expect(find.text('已清除图片缓存'), findsNothing);
  });

  testWidgets('a profile that could not be loaded at startup is loaded by '
      'the settings', (tester) async {
    final api = FakeAlistenApi()
      ..getMeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络不可用',
        status: null,
      );
    final credentials = FakeCredentialStore()..memberToken = 'stored-token';
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(tester, api: api, credentials: credentials);
    expect(api.getMeCalls, 1);

    api.getMeError = null;
    appContainer(tester).read(routerProvider).go('/settings');
    await tester.pumpAndSettle();

    expect(api.getMeCalls, 2);
    expect(tester.widget<EditableText>(_field('昵称')).controller.text, '听众');
  });

  testWidgets('the profile is saved with its own button, and settings are '
      'not', (tester) async {
    final api = FakeAlistenApi();
    await _openSettings(
      tester,
      api: api,
      credentials: FakeCredentialStore()..memberToken = 'stored-token',
    );
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(api.updateMeCalls, 0);

    await tester.enterText(_field('昵称'), '新昵称');
    await tester.pump();
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();

    expect(api.updateMeCalls, 1);
    expect(api.updatedName, '新昵称');
    expect(api.updatedEmail, isNull);
    expect(find.text('资料已保存'), findsOneWidget);
  });

  testWidgets('a save that breaks unexpectedly says so and can be tried '
      'again', (tester) async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    final api = FakeAlistenApi()
      ..updateMeError = const FormatException('broken');
    await _openSettings(
      tester,
      api: api,
      credentials: FakeCredentialStore()..memberToken = 'stored-token',
    );

    await tester.enterText(_field('昵称'), '新昵称');
    await tester.enterText(_field('Gravatar 邮箱'), 'me@example.com');
    await tester.pump();
    final reads = api.getMeCalls;
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();

    // 请求可能已到达服务端，结果未知，不能提示保存失败。
    expect(find.text('结果未知，已重新同步'), findsOneWidget);
    expect(api.getMeCalls, reads + 1, reason: 'the member is read back');
    final errors = [
      for (final record in records)
        if (record.$2 >= 1000) record,
    ];
    expect(errors.map((record) => record.$1), ['alisten.settings']);
    expect(
      errors.where(
        (record) =>
            record.$3.contains('example.com') ||
            record.$3.contains('stored-token') ||
            record.$3.contains('新昵称'),
      ),
      isEmpty,
    );
    final save = tester.widget<PillButton>(
      find.widgetWithText(PillButton, '保存资料'),
    );
    expect(save.busy, isFalse);
    expect(save.onPressed, isNotNull);
  });

  testWidgets('a save whose result is unknown is a warning, and the member '
      'read back does not replace what was typed', (tester) async {
    final api = FakeAlistenApi()
      ..updateMeError = const FormatException('broken');
    await _openSettings(
      tester,
      api: api,
      credentials: FakeCredentialStore()..memberToken = 'stored-token',
    );
    await tester.enterText(_field('昵称'), '新昵称');
    await tester.enterText(_field('Gravatar 邮箱'), 'me@example.com');
    await tester.pump();
    api.getMeResult = Completer<Member>()
      ..complete(const Member(id: 'member-id', name: '服务端昵称', avatarHash: ''));

    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();

    expect(
      appContainer(tester).read(identityControllerProvider).member?.name,
      '服务端昵称',
    );
    expect(tester.widget<EditableText>(_field('昵称')).controller.text, '新昵称');
    expect(
      tester.widget<EditableText>(_field('Gravatar 邮箱')).controller.text,
      'me@example.com',
    );
    expect(
      find.descendant(
        of: find.byType(ToastHost),
        matching: find.byIcon(Icons.warning_rounded),
      ),
      findsOneWidget,
    );
  });
}
