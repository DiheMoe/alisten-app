import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/media_format.dart';
import 'package:alisten/features/admin/presentation/media_page.dart';
import 'package:alisten/features/admin/presentation/media_pager.dart';
import 'package:alisten/features/admin/presentation/media_row.dart';
import 'package:alisten/features/admin/presentation/media_selection_bar.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

final class FakeLinkOpener implements MediaLinkOpener {
  final List<String> opened = [];
  bool result = true;

  @override
  Future<bool> open(String link) async {
    opened.add(link);
    return result;
  }
}

Finder searchField() => find.descendant(
  of: find.byType(AlistenTextField),
  matching: find.byType(EditableText),
);

// 搜索框里的 EditableText 自带一个 Scrollable，页面的列表是第一个。
Finder pageList() => find.byType(Scrollable).first;

final now = DateTime(2026, 11, 18, 20);

// 每一行的“⋯”读作“《歌名》的更多操作”。
Finder moreButtons() => find.bySemanticsLabel(RegExp('的更多操作'));

void main() {
  late FakeAdminApi api;
  late FakeLinkOpener opener;
  late List<(ToastKind, String)> notices;
  late List<void Function()> timers;
  late ProviderContainer container;

  setUp(() {
    api = FakeAdminApi();
    opener = FakeLinkOpener();
    notices = [];
    timers = [];
  });

  int totalBytes() => api.media.fold(0, (sum, track) => sum + track.bytes);

  Future<void> openMedia(
    WidgetTester tester, {
    bool settle = true,
    Size size = const Size(360, 780),
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        ...await switchingOverrides(
          store: FakeServerStore(profiles: [serverB]),
          credentials: FakeCredentialStores(),
        ),
        adminApiProvider.overrideWithValue(api),
        adminNowProvider.overrideWithValue(() => now),
        // 回调记下来由测试触发；返回已取消的 Timer，不留挂起的计时器。
        adminTimerProvider.overrideWithValue((duration, callback) {
          timers.add(callback);
          return Timer(Duration.zero, () {})..cancel();
        }),
        mediaLinkOpenerProvider.overrideWithValue(opener),
      ],
    );
    addTearDown(container.dispose);
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: AdminMediaScreen(
            onNotice: (kind, text) => notices.add((kind, text)),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('the first page shows 20 songs with their details and the '
      'totals', (tester) async {
    api.media = [for (var n = 1; n <= 45; n++) storedTrack(n)];
    await openMedia(tester);
    expect(
      find.text('共 45 首 · 占用 ${formatBytes(totalBytes())}'),
      findsOneWidget,
    );
    expect(find.byType(MediaRow), findsWidgets);
    expect(find.text('歌曲 45'), findsOneWidget);
    expect(find.text('歌手 · 网易云音乐'), findsWidgets);
    expect(find.text(mediaDetails(storedTrack(45), now)), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('第 1–20 首'),
      300,
      scrollable: pageList(),
    );
    expect(find.text('第 1–20 首'), findsOneWidget);
    expect(find.text('歌曲 26'), findsOneWidget);
    expect(find.text('歌曲 25'), findsNothing);
  });

  testWidgets('placeholder rows show while the first page is on its way', (
    tester,
  ) async {
    api.media = [storedTrack(1)];
    final gate = api.listMediaGate = Completer();
    await openMedia(tester, settle: false);
    await tester.pump();
    expect(find.byType(MediaRowSkeleton), findsNWidgets(6));
    expect(find.byType(MediaRow), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MediaRowSkeleton), findsNothing);
    expect(find.text('歌曲 1'), findsOneWidget);
  });

  testWidgets('next page shows the next 20', (tester) async {
    api.media = [for (var n = 1; n <= 45; n++) storedTrack(n)];
    await openMedia(tester);
    await tester.scrollUntilVisible(
      find.text('下一页'),
      300,
      scrollable: pageList(),
    );
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 25'), findsOneWidget);
  });

  testWidgets('tapping the range lets you jump to a page', (tester) async {
    api.media = [for (var n = 1; n <= 45; n++) storedTrack(n)];
    await openMedia(tester);
    await tester.scrollUntilVisible(
      find.text('第 1–20 首'),
      300,
      scrollable: pageList(),
    );
    await tester.tap(find.text('第 1–20 首'));
    await tester.pumpAndSettle();
    expect(find.text('共 3 页'), findsOneWidget);
    final jump = find.widgetWithText(PillButton, '跳转');
    await tester.enterText(find.byType(EditableText).last, '4');
    await tester.pump();
    expect(tester.widget<PillButton>(jump).onPressed, isNull);

    await tester.enterText(find.byType(EditableText).last, '3');
    await tester.pump();
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 5'), findsOneWidget);
  });

  testWidgets('a long press starts selecting; the bar says how many and how '
      'big, and back leaves selecting before the page', (tester) async {
    api.media = [for (var n = 1; n <= 3; n++) storedTrack(n)];
    await openMedia(tester);
    await tester.longPress(find.text('歌曲 3'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 首 · 3.0 MiB'), findsOneWidget);
    // 多选时“⋯”菜单收起。
    expect(moreButtons(), findsNothing);
    await tester.tap(find.text('歌曲 2'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 首 · 5.0 MiB'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('已选'), findsNothing);
    expect(find.byType(AdminMediaScreen), findsOneWidget);
  });

  testWidgets('the bar selects the whole page, then lets it go again', (
    tester,
  ) async {
    api.media = [for (var n = 1; n <= 3; n++) storedTrack(n)];
    await openMedia(tester);
    await tester.longPress(find.text('歌曲 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选本页'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 首 · 6.0 MiB'), findsOneWidget);

    await tester.tap(find.text('取消全选本页'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选'), findsNothing);
  });

  testWidgets('deleting asks with the count and size, then reports what '
      'happened', (tester) async {
    api
      ..media = [for (var n = 1; n <= 3; n++) storedTrack(n)]
      ..mediaInUse = {storedTrack(3).key};
    await openMedia(tester);
    await tester.longPress(find.text('歌曲 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 首歌曲？'), findsOneWidget);
    expect(find.text('将释放 5.0 MiB，删除后不能恢复。'), findsOneWidget);
    final confirm = find.widgetWithText(PillButton, '删除').last;
    // 确认按钮是危险色。
    expect(tester.widget<PillButton>(confirm).danger, isTrue);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(notices.last, (ToastKind.info, '已删除 1 首；1 首正在房间里播放，没有删除'));
    expect(find.text('歌曲 2'), findsNothing);
    expect(find.text('已选 1 首 · 3.0 MiB'), findsOneWidget);
  });

  testWidgets('a song can be deleted from its menu after confirming', (
    tester,
  ) async {
    api.media = [storedTrack(1), storedTrack(2)];
    await openMedia(tester);
    await tester.tap(moreButtons().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 1 首歌曲？'), findsOneWidget);
    expect(find.text('将释放 2.0 MiB，删除后不能恢复。'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '删除').last);
    await tester.pumpAndSettle();
    expect(api.removals, [
      [storedTrack(2).key],
    ]);
    expect(notices.last, (ToastKind.success, '已删除 1 首'));
    expect(find.text('歌曲 2'), findsNothing);
    expect(find.text('共 1 首 · 占用 1.0 MiB'), findsOneWidget);
  });

  testWidgets('deleting songs that are already gone says so rather than '
      '"已删除 0 首"', (tester) async {
    api.media = [storedTrack(1), storedTrack(2), storedTrack(3)];
    await openMedia(tester);
    // 别处已经删掉了这几首。
    api.media = [storedTrack(1)];
    await tester.tap(moreButtons().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillButton, '删除').last);
    await tester.pumpAndSettle();
    expect(notices.last, (ToastKind.info, '这首歌已经不在了'));
    expect(find.text('歌曲 3'), findsNothing);

    api.media = [storedTrack(1), storedTrack(2), storedTrack(3)];
    await container.read(adminMediaControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();
    api.media = [storedTrack(1)];
    await tester.longPress(find.text('歌曲 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillButton, '删除').last);
    await tester.pumpAndSettle();
    expect(notices.last, (ToastKind.info, '这些歌曲已经不在了'));
    expect(notices.map((n) => n.$2), isNot(contains(startsWith('已删除 0'))));
  });

  testWidgets('deleting only songs still playing says just that', (
    tester,
  ) async {
    api
      ..media = [storedTrack(1)]
      ..mediaInUse = {storedTrack(1).key};
    await openMedia(tester);
    await tester.tap(moreButtons().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillButton, '删除').last);
    await tester.pumpAndSettle();
    expect(notices.last, (ToastKind.info, '1 首正在房间里播放，没有删除'));
    expect(find.text('歌曲 1'), findsOneWidget);
  });

  testWidgets("a song's menu opens its page", (tester) async {
    api.media = [storedTrack(1)];
    await openMedia(tester);
    await tester.tap(moreButtons().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开歌曲页面'));
    await tester.pumpAndSettle();
    expect(opener.opened, ['https://music.example.com/1']);
    expect(notices, isEmpty);
  });

  testWidgets('a link that cannot be opened says so', (tester) async {
    api.media = [storedTrack(1)];
    opener.result = false;
    await openMedia(tester);
    await tester.tap(moreButtons().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开歌曲页面'));
    await tester.pumpAndSettle();
    expect(notices.last, (ToastKind.failure, '没能打开链接'));
  });

  testWidgets('empty states tell a search with no match from an empty '
      'library', (tester) async {
    await openMedia(tester);
    expect(find.text('还没有存储任何歌曲'), findsOneWidget);
    api.media = [storedTrack(1)];
    await container.read(adminMediaControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();
    await tester.enterText(searchField(), '没有这首');
    // adminTimerProvider 替身记下的回调，立即触发防抖。
    timers.removeLast()();
    await tester.pumpAndSettle();
    expect(find.text('没有找到歌曲'), findsOneWidget);
    expect(find.text('共 0 首 · 占用 0 B'), findsOneWidget);
    await tester.tap(find.text('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 1'), findsOneWidget);
    expect(tester.widget<EditableText>(searchField()).controller.text, isEmpty);
  });

  for (final (how, clear) in [
    ('清除搜索', (WidgetTester tester) => tester.tap(find.text('清除搜索'))),
    (
      'the × in the field',
      (WidgetTester tester) =>
          tester.tap(find.byIcon(AlistenIcons.xCircleFill)),
    ),
  ]) {
    testWidgets('clearing a search with no match by $how reads again without '
        'calling the library empty', (tester) async {
      api.media = [storedTrack(1)];
      await openMedia(tester);
      await tester.enterText(searchField(), '没有这首');
      timers.removeLast()();
      await tester.pumpAndSettle();
      expect(find.text('没有找到歌曲'), findsOneWidget);

      final gate = api.listMediaGate = Completer();
      await clear(tester);
      await tester.pump();
      expect(find.text('还没有存储任何歌曲'), findsNothing);
      expect(find.text('没有找到歌曲'), findsNothing);
      expect(find.textContaining('共 0 首'), findsNothing);
      expect(find.byType(MediaRowSkeleton), findsNWidgets(6));

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('歌曲 1'), findsOneWidget);
      expect(find.text('共 1 首 · 占用 1.0 MiB'), findsOneWidget);
    });
  }

  testWidgets('a search waits while the input method is still composing', (
    tester,
  ) async {
    api.media = [storedTrack(1)];
    await openMedia(tester);
    final field = tester.widget<EditableText>(searchField()).controller;
    field.value = const TextEditingValue(
      text: 'ge',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.pump();
    expect(timers, isEmpty);

    field.value = const TextEditingValue(
      text: '歌',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    expect(timers, hasLength(1));
  });

  testWidgets('screen readers refresh from the totals, since they cannot '
      'pull', (tester) async {
    final semantics = tester.ensureSemantics();
    api.media = [storedTrack(1)];
    await openMedia(tester);
    api.media = [storedTrack(1), storedTrack(2)];
    tester.semantics.customAction(
      find.semantics.byLabel('共 1 首 · 占用 1.0 MiB'),
      const CustomSemanticsAction(label: '刷新'),
    );
    await tester.pumpAndSettle();
    expect(find.text('歌曲 2'), findsOneWidget);
    expect(find.text('共 2 首 · 占用 3.0 MiB'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a list that cannot be read offers a retry', (tester) async {
    api.listMediaError = const ApiException(
      code: 'UNAVAILABLE',
      message: '服务暂时不可用',
      status: 503,
    );
    await openMedia(tester);
    expect(find.text('服务暂时不可用'), findsOneWidget);
    api
      ..listMediaError = null
      ..media = [storedTrack(1)];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 1'), findsOneWidget);
  });

  testWidgets('a page that cannot be read keeps the last one and offers a '
      'retry above the pager', (tester) async {
    api.media = [for (var n = 1; n <= 120; n++) storedTrack(n)];
    await openMedia(tester);
    api.listMediaError = const ApiException(
      code: 'UNAVAILABLE',
      message: '服务暂时不可用',
      status: 503,
    );
    // 第 3 页跨服务端第 1、2 页，第 2 页还没读过。
    await container.read(adminMediaControllerProvider.notifier).goTo(3);
    await tester.pumpAndSettle();
    expect(find.text('歌曲 120'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('下一页'),
      300,
      scrollable: pageList(),
    );
    expect(find.text('服务暂时不可用'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('重试')).dy,
      lessThan(tester.getTopLeft(find.text('下一页')).dy),
    );

    api.listMediaError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 80'), findsOneWidget);
  });

  for (final (size, scale) in [
    (const Size(360, 780), 1.0),
    (const Size(360, 780), 1.3),
    (const Size(360, 780), 2.0),
    (const Size(320, 640), 2.0),
  ]) {
    testWidgets('at ${size.width.round()} dp wide with text at $scale, the '
        'list ends above the selection bar, pager and all', (tester) async {
      api.media = [for (var n = 1; n <= 1200; n++) storedTrack(n)];
      await openMedia(tester, size: size, textScale: scale);
      // 范围最长的一页：“第 1001–1020 首”。
      await container.read(adminMediaControllerProvider.notifier).goTo(51);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('歌曲 200'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选本页'));
      await tester.pumpAndSettle();
      expect(find.text('已选 20 首 · 3.7 GiB'), findsOneWidget);

      // 列表懒加载，滚到底后末端才算准，多滚几次。
      final list = tester.state<ScrollableState>(pageList()).position;
      for (var i = 0; i < 4; i++) {
        list.jumpTo(list.maxScrollExtent);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('第 1001–1020 首'), findsOneWidget);
      final pager = tester.getRect(find.byType(MediaPager));
      final bar = tester.getRect(find.byType(MediaSelectionBar));
      expect(pager.bottom, lessThanOrEqualTo(bar.top));
      // 留出的正好是操作条的高度：列表末尾和平时一样留 xl。
      expect(bar.top - pager.bottom, moreOrLessEquals(AlistenSpacing.xl));
    });
  }

  testWidgets('the sort menu changes the order', (tester) async {
    api.media = [
      storedTrack(1, bytes: 9 * 1024 * 1024),
      storedTrack(2, bytes: 1024 * 1024),
    ];
    await openMedia(tester);
    await tester.tap(find.text('最近存储'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('占用最大').last);
    await tester.pumpAndSettle();
    expect(api.mediaQueries.last.order, MediaOrder.size);
    expect(
      tester.getTopLeft(find.text('歌曲 1')).dy,
      lessThan(tester.getTopLeft(find.text('歌曲 2')).dy),
    );
  });
}
