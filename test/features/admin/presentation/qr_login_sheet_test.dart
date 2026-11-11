import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _startMs = 1700000000000;

// 1×1 的透明 PNG。
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8'
  'AAAAASUVORK5CYII=',
);

const _signedIn = SourceAccountStatus(
  saved: true,
  account: SourceAccount(id: '42', name: '小明', vip: true, verified: true),
);

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(AlistenTextField, label),
  matching: find.byType(EditableText),
);

Finder _inRow(LoginSource source, String text) => find.descendant(
  of: find.byKey(ValueKey(source)),
  matching: find.text(text),
);

void main() {
  late FakeAdminApi api;
  late FakeQrImageLoader images;
  late FakeImageGallery gallery;
  late List<(ToastKind, String)> notices;
  late DateTime origin;
  late Duration clockAhead;

  setUp(() {
    api = FakeAdminApi();
    images = FakeQrImageLoader()..bytes = _png;
    gallery = FakeImageGallery();
    notices = [];
    clockAhead = Duration.zero;
  });

  // 时钟随假时间前进，打开扫码面板时为 [_startMs] 加上设备时钟领先服务端的
  // [clockAhead]。
  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    origin = tester.binding.clock.now();
    final container = ProviderContainer(
      overrides: [
        ...await switchingOverrides(
          store: FakeServerStore(profiles: [serverB]),
          credentials: FakeCredentialStores(),
        ),
        adminApiProvider.overrideWithValue(api),
        qrImageLoaderProvider.overrideWithValue(images),
        imageGalleryProvider.overrideWithValue(gallery),
        adminNowProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(
            _startMs +
                clockAhead.inMilliseconds +
                tester.binding.clock.now().difference(origin).inMilliseconds,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: AdminScreen(
            onNotice: (kind, text) => notices.add((kind, text)),
            onExit: () {},
            onOpenRoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.enterText(_field('管理 token'), 't-1');
    await tester.tap(find.text('进入后台'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('音源账号'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, LoginSource source) async {
    final button = _inRow(source, '扫码登录');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    origin = tester.binding.clock.now();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  // 测试结束卸下整棵树时若面板仍开着，Riverpod 不再销毁控制器，其计时器会残留，
  // 因此结束前先关闭面板。
  Future<void> closeSheets(WidgetTester tester) async {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
  }

  void sheetTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      await body(tester);
      await closeSheets(tester);
    });
  }

  Future<void> platformReports(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
  }

  group('the source accounts', () {
    testWidgets('each source shows how it is signed in, with a button to '
        'sign in or sign in again', (tester) async {
      api.sourceAccounts[LoginSource.qq] = const SourceAccountStatus(
        saved: true,
        account: SourceAccount(id: '7', verified: false),
      );
      await open(tester);
      await tester.ensureVisible(find.text('音源账号'));
      await tester.pumpAndSettle();

      expect(_inRow(LoginSource.netease, '网易云音乐'), findsOneWidget);
      expect(_inRow(LoginSource.netease, '未登录'), findsOneWidget);
      expect(_inRow(LoginSource.netease, '扫码登录'), findsOneWidget);
      expect(_inRow(LoginSource.qq, 'QQ 音乐'), findsOneWidget);
      expect(_inRow(LoginSource.qq, '已保存登录信息，未经 QQ 音乐核实'), findsOneWidget);
      expect(_inRow(LoginSource.qq, '账号 ID：7'), findsOneWidget);
      expect(_inRow(LoginSource.qq, '重新登录'), findsOneWidget);
      expect(_inRow(LoginSource.bilibili, 'B 站'), findsOneWidget);
      expect(_inRow(LoginSource.bilibili, '未登录'), findsOneWidget);
    });

    testWidgets('a source that cannot be read says why and is read again '
        'on request', (tester) async {
      api.sourceAccountErrors[LoginSource.bilibili] = StateError('down');
      await open(tester);
      final retry = _inRow(LoginSource.bilibili, '重试');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      expect(retry, findsOneWidget);

      api.sourceAccountErrors.clear();
      await tap(tester, retry);

      expect(_inRow(LoginSource.bilibili, '未登录'), findsOneWidget);
      expect(retry, findsNothing);
    });
  });

  sheetTest('a code is shown in a sheet with its seconds left, its status, '
      'a way to save it and the steps to scan it from the gallery', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await signIn(tester, LoginSource.netease);

    expect(find.text('扫码登录网易云音乐'), findsOneWidget);
    expect(find.text('剩余 120 秒'), findsOneWidget);
    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    expect(find.bySemanticsLabel('登录二维码'), findsOneWidget);
    expect(find.text('1. 点“保存到相册”。'), findsOneWidget);
    expect(find.text('2. 打开网易云音乐，进入“扫一扫”。'), findsOneWidget);
    expect(find.text('3. 在扫一扫里选择相册中的这张二维码。'), findsOneWidget);
    expect(find.text('重新获取'), findsNothing);
    expect(api.startedSources, [LoginSource.netease]);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('剩余 119 秒'), findsOneWidget);
    semantics.dispose();
  });

  sheetTest('a saved code goes to the gallery under the name of its '
      'source', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await tap(tester, find.text('保存到相册'));

    expect(gallery.saved.single.name, 'alisten-netease-login');
    expect(gallery.saved.single.bytes, _png);
    expect(notices, [(ToastKind.success, '已保存到相册')]);
  });

  sheetTest('saving without access to the gallery says where to allow '
      'it', (tester) async {
    gallery.deny = true;
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await tap(tester, find.text('保存到相册'));

    expect(gallery.saved, isEmpty);
    expect(notices, [(ToastKind.warning, '没有相册权限，可在系统设置中开启')]);
  });

  sheetTest('a code that cannot be saved says so', (tester) async {
    gallery.error = StateError('disk full');
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await tap(tester, find.text('保存到相册'));

    expect(notices, [(ToastKind.failure, '没能保存到相册')]);
  });

  sheetTest('QQ music is scanned with QQ or WeChat, and switching asks for '
      'a new code; the steps name the app that scans', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.qq);

    expect(find.text('扫码登录 QQ 音乐'), findsOneWidget);
    expect(find.text('QQ 扫码'), findsOneWidget);
    expect(find.text('2. 打开 QQ，进入“扫一扫”。'), findsOneWidget);
    expect(api.startedQqTypes, [QqLoginType.qq]);

    await tap(tester, find.text('微信扫码'));

    expect(api.startedQqTypes, [QqLoginType.qq, QqLoginType.wx]);
    expect(find.text('2. 打开微信，进入“扫一扫”。'), findsOneWidget);
    expect(find.text('等待扫码'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(api.checkedQqTypes, [QqLoginType.wx]);
  });

  sheetTest('B 站 is scanned with the bilibili app', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.bilibili);

    expect(find.text('扫码登录 B 站'), findsOneWidget);
    expect(find.text('2. 打开哔哩哔哩，进入“扫一扫”。'), findsOneWidget);
    expect(find.text('QQ 扫码'), findsNothing);
  });

  sheetTest('a sign-in taken closes the sheet and names the account '
      'signed in', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.netease);
    api
      ..checkResults.add(const FakeQrCheck(QrCheckState.success))
      ..sourceAccounts[LoginSource.netease] = _signedIn;

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('等待扫码'), findsNothing);
    expect(find.text('保存到相册'), findsNothing);
    expect(notices, [(ToastKind.success, '已登录 小明')]);
    expect(_inRow(LoginSource.netease, '已登录'), findsOneWidget);
    expect(_inRow(LoginSource.netease, '昵称：小明'), findsOneWidget);
    expect(_inRow(LoginSource.netease, '重新登录'), findsOneWidget);
  });

  sheetTest('a sign-in taken whose account cannot be read again still '
      'says so', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.netease);
    api
      ..checkResults.add(const FakeQrCheck(QrCheckState.success))
      ..sourceAccountErrors[LoginSource.netease] = StateError('down');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(notices, [(ToastKind.success, '已登录')]);
  });

  sheetTest('a code that ran out cannot be saved and is asked for again on '
      'request', (tester) async {
    api.checkResults.add(const FakeQrCheck(QrCheckState.expired));
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('二维码已过期'), findsOneWidget);
    expect(find.textContaining('剩余'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('保存到相册'), findsNothing);

    await tap(tester, find.text('重新获取'));

    expect(api.startedSources, hasLength(2));
    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.text('重新获取'), findsNothing);
    expect(find.text('保存到相册'), findsOneWidget);
  });

  sheetTest('nothing can be saved before the code arrives', (tester) async {
    final gate = api.startQrGate = Completer<void>();
    await open(tester);
    final button = _inRow(LoginSource.netease, '扫码登录');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    // 加载指示器持续转动，只能逐步推进时间。
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('正在获取二维码'), findsOneWidget);
    await tester.tap(find.text('保存到相册'));
    await tester.pump();
    expect(gallery.saved, isEmpty);
    expect(notices, isEmpty);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('等待扫码'), findsOneWidget);
  });

  sheetTest('a failed sign-in gives its reason and can be tried again', (
    tester,
  ) async {
    api.checkResults.add(
      const FakeQrCheck(QrCheckState.failed, message: '账号存在风险'),
    );
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('登录失败：账号存在风险'), findsOneWidget);
    expect(find.text('重新获取'), findsOneWidget);
  });

  sheetTest('the code is not checked while the app is in the background, '
      'and is checked at once when it comes back', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await platformReports(tester, AppLifecycleState.inactive);
    await platformReports(tester, AppLifecycleState.hidden);
    await platformReports(tester, AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(api.checkCalls, 0);
    expect(find.text('剩余 120 秒'), findsOneWidget);

    await platformReports(tester, AppLifecycleState.hidden);
    await platformReports(tester, AppLifecycleState.inactive);
    await platformReports(tester, AppLifecycleState.resumed);

    expect(api.checkCalls, 1);
    expect(find.text('剩余 110 秒'), findsOneWidget);
  });

  sheetTest('a closed sheet stops checking its code', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text('等待扫码'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    expect(api.checkCalls, 0);
  });

  sheetTest('a check whose answer was lost keeps the code waiting, and a '
      'sign-in after it names the account', (tester) async {
    await open(tester);
    await signIn(tester, LoginSource.netease);
    api
      ..checkResults.addAll(const [
        FakeQrCheck.error(
          ApiException(
            code: 'NETWORK',
            message: '网络请求失败，请检查网络后重试。',
            status: null,
          ),
        ),
        FakeQrCheck(QrCheckState.success),
      ])
      ..sourceAccounts[LoginSource.netease] = _signedIn;

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.textContaining('登录失败'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('等待扫码'), findsNothing);
    expect(notices, [(ToastKind.success, '已登录 小明')]);
    expect(_inRow(LoginSource.netease, '已登录'), findsOneWidget);
  });

  sheetTest('the account of a source is read again however its sheet '
      'closes, with nothing to say unless signed in', (tester) async {
    api.checkResults.add(
      const FakeQrCheck(QrCheckState.failed, message: '账号存在风险'),
    );
    await open(tester);
    int reads() => api.sourceAccountCalls
        .where((source) => source == LoginSource.netease)
        .length;
    final before = reads();
    await signIn(tester, LoginSource.netease);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('登录失败：账号存在风险'), findsOneWidget);
    // 答复丢失之前，服务端可能已保存登录信息。
    api.sourceAccounts[LoginSource.netease] = _signedIn;

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();

    expect(reads(), before + 1);
    expect(notices, isEmpty);
    expect(_inRow(LoginSource.netease, '已登录'), findsOneWidget);

    int qqReads() => api.sourceAccountCalls
        .where((source) => source == LoginSource.qq)
        .length;
    final qqBefore = qqReads();
    await signIn(tester, LoginSource.qq);
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(qqReads(), qqBefore + 1);
  });

  sheetTest('a device clock ahead of the server by more than the life of the '
      'code shows 0 seconds left, keeps the code scannable and leaves running '
      'out to the server', (tester) async {
    clockAhead = const Duration(minutes: 3);
    await open(tester);
    await signIn(tester, LoginSource.netease);

    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.text('剩余 0 秒'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('二维码已过期'), findsNothing);
    expect(find.text('剩余 0 秒'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(api.checkCalls, 2);

    api.checkResults.add(const FakeQrCheck(QrCheckState.expired));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('二维码已过期'), findsOneWidget);
  });

  sheetTest('a code past its countdown stays scannable at 0 seconds left', (
    tester,
  ) async {
    api.qrTicket = const QrLoginTicket(
      key: 'k-1',
      qrImage: 'data:image/png;base64,iVBORw0KGgo=',
      expiresAtMs: _startMs + 3000,
    );
    await open(tester);
    await signIn(tester, LoginSource.netease);

    await tester.pump(const Duration(seconds: 10));

    expect(find.text('剩余 0 秒'), findsOneWidget);
    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.text('二维码已过期'), findsNothing);
    expect(find.textContaining('剩余 -'), findsNothing);
    expect(api.checkCalls, 5);
  });
}
