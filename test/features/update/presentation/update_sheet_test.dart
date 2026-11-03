import 'dart:async';
import 'dart:ffi' show Abi;

import 'package:alisten/domain/release/app_release.dart';
import 'package:alisten/domain/release/release_version.dart';
import 'package:alisten/features/update/data/platform_release_opener.dart';
import 'package:alisten/features/update/data/preferences_update_store.dart';
import 'package:alisten/features/update/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../update_test_doubles.dart';

const _notes = '- 修复了切歌时的卡顿\n- 新增检查更新';

final _update = UpdateAvailable(
  testRelease(tag: 'v9.0.0', notes: _notes),
  const ReleaseVersion(9, 0, 0),
);

void main() {
  late List<(ToastKind, String)> notices;
  late SharedPreferences preferences;

  setUp(() async {
    notices = [];
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Future<void> open(
    WidgetTester tester, {
    UpdateAvailable? update,
    ReleaseOpener? opener,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateStoreProvider.overrideWithValue(
            PreferencesUpdateStore(preferences),
          ),
          releaseOpenerProvider.overrideWithValue(
            opener ?? FakeReleaseOpener(),
          ),
          installedVersionProvider.overrideWithValue(
            const ReleaseVersion(1, 0, 0),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: textScaler),
          child: MaterialApp(
            theme: buildAlistenTheme(
              AlistenColors.brandScheme(Brightness.dark),
            ),
            home: const Text('首页'),
          ),
        ),
      ),
    );
    unawaited(
      showUpdateSheet(
        tester.element(find.text('首页')),
        update ?? _update,
        onNotice: (kind, text) => notices.add((kind, text)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the panel names the new and the installed version, shows the '
      'whole release notes and offers three choices', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(find.text('发现新版本 9.0.0'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('发现新版本 9.0.0')),
      isSemantics(isHeader: true),
    );
    expect(find.text('当前版本 1.0.0'), findsOneWidget);
    expect(find.text(_notes), findsOneWidget);
    final download = tester.widget<PillButton>(
      find.widgetWithText(PillButton, '下载更新'),
    );
    expect(download.style, PillButtonStyle.primary);
    expect(
      tester.widget<PillButton>(find.widgetWithText(PillButton, '稍后')).style,
      PillButtonStyle.secondary,
    );
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, '跳过这个版本'))
          .style,
      PillButtonStyle.ghost,
    );
    semantics.dispose();
  });

  testWidgets(
    'on iOS the main choice goes to the release page',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await open(tester);

      expect(find.text('前往发布页'), findsOneWidget);
      expect(find.text('下载更新'), findsNothing);
    },
  );

  testWidgets('downloading opens the package for this device in another app '
      'and closes the panel', (tester) async {
    final launched = <(Uri, LaunchMode)>[];
    await open(
      tester,
      opener: PlatformReleaseOpener(
        abi: Abi.androidArm64,
        launch: (uri, {mode = LaunchMode.platformDefault}) async {
          launched.add((uri, mode));
          return true;
        },
      ),
    );

    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();

    expect(launched, [
      (
        Uri.parse(
          'https://github.com/DiheMoe/alisten-app/releases/download/v9.0.0/'
          'Alisten-9.0.0-arm64-v8a.apk',
        ),
        LaunchMode.externalApplication,
      ),
    ]);
    expect(find.text('发现新版本 9.0.0'), findsNothing);
    expect(notices, isEmpty);
    expect(preferences.getKeys(), isEmpty);
  });

  testWidgets('a link that cannot be opened says so and keeps the panel '
      'open', (tester) async {
    final opener = FakeReleaseOpener()..opens = false;
    await open(tester, opener: opener);

    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();

    expect(opener.opened, [same(_update.release)]);
    expect(notices, [(ToastKind.failure, '没能打开链接，请稍后再试。')]);
    expect(find.text('发现新版本 9.0.0'), findsOneWidget);
  });

  testWidgets('the main choice is pressed once while the link opens', (
    tester,
  ) async {
    final opening = Completer<bool>();
    final opener = _HeldOpener(opening.future);
    await open(tester, opener: opener);

    await tester.tap(find.text('下载更新'));
    await tester.pump();
    expect(
      tester.widget<PillButton>(find.widgetWithText(PillButton, '下载更新')).busy,
      isTrue,
    );
    await tester.tap(find.text('下载更新'), warnIfMissed: false);
    await tester.pump();
    expect(opener.calls, 1);

    opening.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 9.0.0'), findsNothing);
  });

  testWidgets('while the link opens, later and skipping cannot be chosen, so '
      'a failure is never told after the panel closed', (tester) async {
    final opening = Completer<bool>();
    await open(tester, opener: _HeldOpener(opening.future));

    await tester.tap(find.text('下载更新'));
    await tester.pump();
    for (final choice in ['稍后', '跳过这个版本']) {
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, choice))
            .onPressed,
        isNull,
        reason: choice,
      );
      await tester.tap(find.text(choice), warnIfMissed: false);
      // 忙碌转圈不会停，只能推进时间。
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('发现新版本 9.0.0'), findsOneWidget, reason: choice);
    }
    expect(preferences.getKeys(), isEmpty);

    opening.complete(false);
    await tester.pumpAndSettle();
    expect(notices, [(ToastKind.failure, '没能打开链接，请稍后再试。')]);
    expect(find.text('发现新版本 9.0.0'), findsOneWidget);
    for (final choice in ['稍后', '跳过这个版本']) {
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, choice))
            .onPressed,
        isNotNull,
        reason: choice,
      );
    }
  });

  testWidgets('later closes the panel and remembers nothing', (tester) async {
    final opener = FakeReleaseOpener();
    await open(tester, opener: opener);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 9.0.0'), findsNothing);
    expect(opener.opened, isEmpty);
    expect(preferences.getKeys(), isEmpty);
  });

  testWidgets('skipping this version keeps it in the preferences and closes '
      'the panel', (tester) async {
    final opener = FakeReleaseOpener();
    await open(tester, opener: opener);

    await tester.tap(find.text('跳过这个版本'));
    await tester.pumpAndSettle();

    expect(preferences.getString('alisten.update.skipped-version'), '9.0.0');
    expect(find.text('发现新版本 9.0.0'), findsNothing);
    expect(opener.opened, isEmpty);
  });

  testWidgets('long notes scroll inside a bounded area, and with large text '
      'every choice can still be reached', (tester) async {
    final notes = [for (var line = 1; line <= 200; line++) '第 $line 条更新'];
    final update = UpdateAvailable(
      testRelease(tag: 'v9.0.0', notes: notes.join('\n')),
      const ReleaseVersion(9, 0, 0),
    );
    final opener = FakeReleaseOpener();
    await open(
      tester,
      update: update,
      opener: opener,
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    final notesBox = find.descendant(
      of: find.byType(UpdateSheet),
      matching: find.byType(Scrollable),
    );
    expect(tester.getSize(notesBox).height, lessThanOrEqualTo(780 * 0.4));
    final before = tester.getTopLeft(find.text(notes.join('\n')));
    await tester.drag(notesBox, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text(notes.join('\n'))).dy,
      lessThan(before.dy),
    );

    for (final choice in ['跳过这个版本', '稍后', '下载更新']) {
      await tester.ensureVisible(find.text(choice));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.widgetWithText(PillButton, choice));
      expect(rect.top, greaterThanOrEqualTo(0), reason: choice);
      expect(rect.bottom, lessThanOrEqualTo(780), reason: choice);
    }
    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    expect(opener.opened, hasLength(1));
  });

  testWidgets('a release without notes shows no notes area', (tester) async {
    await open(
      tester,
      update: UpdateAvailable(
        testRelease(tag: 'v9.0.0', notes: ''),
        const ReleaseVersion(9, 0, 0),
      ),
    );

    expect(find.text('发现新版本 9.0.0'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UpdateSheet),
        matching: find.byType(Scrollbar),
      ),
      findsNothing,
    );
  });
}

final class _HeldOpener implements ReleaseOpener {
  _HeldOpener(this._result);

  final Future<bool> _result;
  int calls = 0;

  @override
  Future<bool> open(AppRelease release) {
    calls++;
    return _result;
  }
}
