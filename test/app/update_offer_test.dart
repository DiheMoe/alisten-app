import 'dart:async';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/features/update/index.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import '../features/update/update_test_doubles.dart';
import 'app_test_harness.dart';

const _title = '发现新版本 9.0.0';

final _now = DateTime.utc(2026, 11, 4, 9);

final _clock = updateNowProvider.overrideWithValue(() => _now);

void main() {
  testWidgets('a newer release found at launch is offered in its panel, and '
      'the check is recorded', (tester) async {
    final releases = FakeReleaseSource(release: testRelease(tag: 'v9.0.0'));
    await pumpAlistenApp(tester, releases: releases, overrides: [_clock]);

    expect(find.text(_title), findsOneWidget);
    expect(find.bySemanticsLabel('创建房间'), findsOneWidget);
    expect(releases.calls, 1);
    expect(
      appContainer(tester)
          .read(sharedPreferencesProvider)
          .getInt('alisten.update.last-auto-check'),
      _now.millisecondsSinceEpoch,
    );

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
  });

  testWidgets('the app checked within the last day asks nothing at '
      'launch', (tester) async {
    final releases = FakeReleaseSource(release: testRelease(tag: 'v9.0.0'));
    await pumpAlistenApp(
      tester,
      releases: releases,
      preferences: {
        'alisten.update.last-auto-check': _now
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      },
      overrides: [_clock],
    );

    expect(releases.calls, 0);
    expect(find.text(_title), findsNothing);
  });

  group('a manual check answered while the launch check is still out', () {
    // 只挂起启动时的那一次请求，手动检查立即得到答复，弹出面板。
    Future<Completer<void>> showManualPanel(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(360, 780) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final releases = FakeReleaseSource(release: testRelease(tag: 'v9.0.0'));
      final launch = releases.holding = Completer<void>();
      await pumpAlistenApp(tester, releases: releases, overrides: [_clock]);
      expect(releases.calls, 1);
      releases.holding = null;
      appContainer(tester).read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('检查更新'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(releases.calls, 2);
      return launch;
    }

    testWidgets('leaves a version skipped on its panel skipped, though the '
        'launch check answers while that panel is open', (tester) async {
      final launch = await showManualPanel(tester);

      launch.complete();
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      await tester.tap(find.text('跳过这个版本'));
      await tester.pumpAndSettle();

      expect(find.text(_title), findsNothing);
    });

    testWidgets('leaves a version skipped on its panel skipped when the '
        'launch check answers afterwards', (tester) async {
      final launch = await showManualPanel(tester);

      await tester.tap(find.text('跳过这个版本'));
      await tester.pumpAndSettle();
      launch.complete();
      await tester.pumpAndSettle();

      expect(find.text(_title), findsNothing);
    });

    testWidgets('does not let the launch check show the same version again '
        'after later', (tester) async {
      final launch = await showManualPanel(tester);

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      launch.complete();
      await tester.pumpAndSettle();

      expect(find.text(_title), findsNothing);
    });
  });

  testWidgets('a skipped version is not offered at launch', (tester) async {
    await pumpAlistenApp(
      tester,
      releases: FakeReleaseSource(release: testRelease(tag: 'v9.0.0')),
      preferences: {'alisten.update.skipped-version': '9.0.0'},
    );

    expect(find.text(_title), findsNothing);
  });

  testWidgets('a launch check that breaks unexpectedly shows nothing and is '
      'logged only at debug level', (tester) async {
    final records = <(int, String)>[];
    AppLog.onRecord = (name, level, message) {
      if (name == 'alisten.update') records.add((level, message));
    };
    addTearDown(() => AppLog.onRecord = null);

    await pumpAlistenApp(
      tester,
      releases: FakeReleaseSource(release: testRelease(tag: 'v9.0.0')),
      overrides: [
        updateNowProvider.overrideWithValue(
          () => throw StateError('clock unreadable'),
        ),
      ],
    );

    expect(find.bySemanticsLabel('创建房间'), findsOneWidget);
    expect(find.text(_title), findsNothing);
    expect(records, isNotEmpty);
    expect(records.map((record) => record.$1), everyElement(500));
    expect(
      records.map((record) => record.$2),
      everyElement(isNot(contains('unreadable'))),
    );
  });

  testWidgets('a launch check that fails shows nothing', (tester) async {
    final releases = FakeReleaseSource()..error = const ReleaseUnavailable();
    await pumpAlistenApp(tester, releases: releases);

    expect(releases.calls, 1);
    expect(find.text(_title), findsNothing);
    expect(find.textContaining('检查更新'), findsNothing);
    expect(find.bySemanticsLabel('创建房间'), findsOneWidget);
  });

  testWidgets('the room of the launch link is opened first, and the panel '
      'is offered on top of it', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final origin = BuildEnvironment.fromEnvironment().defaultOrigin;
    final links = _HeldLinkSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(
          api: FakeAlistenApi()
            ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
          credentials: FakeCredentialStore()
            ..tickets[testRoomId] = 'saved-ticket',
          links: links,
          releases: FakeReleaseSource(release: testRelease(tag: 'v9.0.0')),
        ),
        child: const AlistenApp(),
      ),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    for (var step = 0; step < 3; step++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text(_title), findsNothing);

    links.open(Uri.parse('$origin/r/listen'));
    // 房间页的极光动画不会停止，只能逐步推进时间。
    for (var step = 0; step < 4; step++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    final router = appContainer(tester).read(routerProvider);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/r/listen');
    expect(find.text(_title).hitTestable(), findsOneWidget);
  });

  testWidgets('a panel already open at launch, such as a share or an '
      'invite, is not covered; the update follows once it closes', (
    tester,
  ) async {
    final releases = FakeReleaseSource(release: testRelease(tag: 'v9.0.0'))
      ..holding = Completer<void>();
    await pumpAlistenApp(tester, releases: releases);
    final root = appContainer(tester)
        .read(routerProvider)
        .routerDelegate
        .navigatorKey
        .currentContext!;
    unawaited(showSheetPanel<void>(root, builder: (_) => const Text('另一个面板')));
    await tester.pumpAndSettle();

    releases.holding!.complete();
    await tester.pumpAndSettle();
    expect(find.text('另一个面板'), findsOneWidget);
    expect(find.text(_title), findsNothing);

    Navigator.of(tester.element(find.text('另一个面板'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('另一个面板'), findsNothing);
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('the test app never asks GitHub: its release source and '
      'opener are fakes', (tester) async {
    await pumpAlistenApp(tester);

    final container = appContainer(tester);
    expect(container.read(releaseSourceProvider), isA<FakeReleaseSource>());
    expect(container.read(releaseOpenerProvider), isA<FakeReleaseOpener>());
    expect(find.text(_title), findsNothing);
  });
}

/// 启动链接到 [open] 时才送达，与插件一样经 [uriLinkStream] 投递。
final class _HeldLinkSource implements AppLinkSource {
  final _initial = Completer<Uri?>();
  final _links = StreamController<Uri>.broadcast();

  void open(Uri uri) {
    _initial.complete(uri);
    _links.add(uri);
  }

  @override
  Future<Uri?> getInitialLink() => _initial.future;

  @override
  Stream<Uri> get uriLinkStream => _links.stream;
}
