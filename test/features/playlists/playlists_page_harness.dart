import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../app/app_test_harness.dart';
import '../lobby/lobby_test_doubles.dart';
import 'playlists_test_doubles.dart';

/// 单独显示一个歌单的页面或部件：与 App 相同的接线、主题和中文本地化（读屏的
/// 排序操作因此是“上移”“下移”）。房间没有连接。
Future<ProviderContainer> pumpPlaylistsPage(
  WidgetTester tester,
  Widget page, {
  FakePlaylistApi? playlists,
  FakePlaylistFileSource? files,
  FakePlaylistExporter? exporter,
  bool signedIn = true,
  String? memberToken = accountToken,
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(360, 780),
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await alistenAppOverrides(
          api: FakeAlistenApi()..account = signedIn ? testAccount : null,
          credentials: FakeCredentialStore()..memberToken = memberToken,
          playlists: playlists,
          playlistFiles: files,
          playlistExporter: exporter,
        ),
        playlistsNowProvider.overrideWithValue(() => testNowMs),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await settlePage(tester);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return ProviderScope.containerOf(tester.element(find.byWidget(page)));
}

/// 加载中的忙碌指示器一直在转，不能等画面静止，只能按固定步长推进。
Future<void> settlePage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
