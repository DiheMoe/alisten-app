import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/admin_home.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart' show roomListing;
import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _signedInSource = SourceAccountStatus(
  saved: true,
  account: SourceAccount(id: '42', name: '小明', verified: true),
);

String _rowSummary(WidgetTester tester, String title) => tester
    .widget<CategoryRow>(
      find.ancestor(of: find.text(title), matching: find.byType(CategoryRow)),
    )
    .summary;

void main() {
  late FakeAdminApi api;
  late List<AdminSection> opened;

  setUp(() {
    api = FakeAdminApi();
    opened = [];
  });

  Future<void> openHome(WidgetTester tester, {bool settle = true}) async {
    final container = ProviderContainer(
      overrides: [
        ...await switchingOverrides(
          store: FakeServerStore(profiles: [serverB]),
          credentials: FakeCredentialStores(),
        ),
        adminApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final gate = api.listRoomsGate;
    api.listRoomsGate = null;
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    api.listRoomsGate = gate;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: AdminHome(onExit: () {}, onOpenSection: opened.add),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('the home lists the sections with what each holds', (
    tester,
  ) async {
    api
      ..brandName = '大猫听歌房'
      ..registrationOpen = true
      ..rooms = [
        roomListing(id: 'r-1'),
        roomListing(id: 'r-2'),
        roomListing(id: 'r-3'),
      ]
      ..sourceAccounts.addAll({
        LoginSource.netease: _signedInSource,
        LoginSource.qq: const SourceAccountStatus(saved: false),
        LoginSource.bilibili: const SourceAccountStatus(saved: false),
      });
    await openHome(tester);

    expect(_rowSummary(tester, '站点'), '大猫听歌房');
    expect(_rowSummary(tester, '登录与注册'), startsWith('开放注册 · GitHub '));
    expect(_rowSummary(tester, '用户'), '查找与重置密码');
    expect(_rowSummary(tester, '房间'), '3 个常驻房间');
    expect(_rowSummary(tester, '音源'), '2 个未登录');
    expect(find.byKey(const ValueKey('category-alert')), findsOneWidget);
  });

  testWidgets('a summary that cannot be read says so on its own row', (
    tester,
  ) async {
    api.getBrandError = const ApiException(
      code: 'UNAVAILABLE',
      message: 'gone',
      status: 503,
    );
    await openHome(tester);
    expect(_rowSummary(tester, '站点'), '读取失败');
    expect(_rowSummary(tester, '用户'), '查找与重置密码');
  });

  testWidgets('with every source signed in there is no dot', (tester) async {
    api.sourceAccounts.addAll({
      for (final source in LoginSource.values) source: _signedInSource,
    });
    await openHome(tester);
    expect(_rowSummary(tester, '音源'), '都已登录');
    expect(find.byKey(const ValueKey('category-alert')), findsNothing);
  });

  testWidgets('a source that cannot be read shows no dot beside "读取失败"', (
    tester,
  ) async {
    api
      ..sourceAccounts[LoginSource.netease] = _signedInSource
      ..sourceAccountErrors[LoginSource.bilibili] = const ApiException(
        code: 'UNAVAILABLE',
        message: 'gone',
        status: 503,
      );
    // QQ 音乐没登录，但 B 站读不出来：不知道一共几个没登录。
    await openHome(tester);
    expect(_rowSummary(tester, '音源'), '读取失败');
    expect(find.byKey(const ValueKey('category-alert')), findsNothing);
  });

  testWidgets('the rooms row reads while the list is on its way, then says '
      'there are none', (tester) async {
    final gate = api.listRoomsGate = Completer();
    await openHome(tester, settle: false);
    await tester.pump();
    expect(_rowSummary(tester, '房间'), '读取中');

    gate.complete();
    await tester.pumpAndSettle();
    expect(_rowSummary(tester, '房间'), '还没有常驻房间');
  });

  testWidgets('the media row says how many songs are stored and the room '
      'they take', (tester) async {
    api.media = [storedTrack(1), storedTrack(2), storedTrack(3)];
    await openHome(tester);
    expect(_rowSummary(tester, '媒体'), '3 首 · 占用 6.0 MiB');
    expect(api.mediaQueries, [(page: 1, order: MediaOrder.stored, query: '')]);
  });

  testWidgets('an empty library says so on the media row', (tester) async {
    await openHome(tester);
    expect(_rowSummary(tester, '媒体'), '还没有存储歌曲');
  });

  testWidgets('the media row reads, and says so when it cannot', (
    tester,
  ) async {
    final gate = api.listMediaGate = Completer();
    api.listMediaError = const ApiException(
      code: 'UNAVAILABLE',
      message: 'gone',
      status: 503,
    );
    await openHome(tester, settle: false);
    await tester.pump();
    expect(_rowSummary(tester, '媒体'), '读取中');

    gate.complete();
    await tester.pumpAndSettle();
    expect(_rowSummary(tester, '媒体'), '读取失败');
    expect(_rowSummary(tester, '用户'), '查找与重置密码');
  });

  testWidgets('tapping a row opens its section', (tester) async {
    await openHome(tester);
    await tester.tap(find.text('房间'));
    await tester.tap(find.text('媒体'));
    expect(opened, [AdminSection.rooms, AdminSection.media]);
  });
}
