import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _callback = 'https://example.com:8443/api/auth/github/callback';
const _offText =
    '在 GitHub 的 Settings → Developer settings → OAuth Apps 新建一个 OAuth App，'
    '填好下面的 Client ID 和 Client Secret 就会开启。';
const _onText = '用户可以用 GitHub 登录、注册和绑定账号。';
const _closeMessage =
    '关闭后，不能再用 GitHub 登录、注册或绑定，已经绑定的 GitHub 保持绑定。'
    '只绑定了 GitHub 的账号，关闭之后就无法用 GitHub 登录，重新开启之前也无法在'
    '其他设备上登录。';
const _notLoadedText = '暂时无法获取 GitHub 登录的配置。';
const _enabled = GithubAppStatus(
  clientId: 'Iv1.abc',
  clientSecretSet: true,
  callbackUrl: _callback,
);

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(AlistenTextField, label),
  matching: find.byType(EditableText),
);

void main() {
  late FakeAdminApi api;
  late List<(ToastKind, String)> notices;
  late List<String> copied;
  late bool clipboardFails;

  setUp(() {
    api = FakeAdminApi();
    notices = [];
    copied = [];
    clipboardFails = false;
  });

  // [loaded] 为 false 时这一组读不出状态、没有回调地址，滚到组标题为止。
  Future<void> open(WidgetTester tester, {bool loaded = true}) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            if (clipboardFails) throw PlatformException(code: 'denied');
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          case 'Clipboard.hasStrings':
            return {'value': true};
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
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
      find.text(loaded ? _callback : _notLoadedText),
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

  testWidgets('a site without GitHub says how to turn it on and where GitHub '
      'calls back', (tester) async {
    await open(tester);

    expect(find.text('GitHub 登录'), findsOneWidget);
    expect(find.text('未开启'), findsOneWidget);
    expect(find.text(_offText), findsOneWidget);
    expect(
      find.text('OAuth App 的 Authorization callback URL 填这个地址。'),
      findsOneWidget,
    );
    expect(find.widgetWithText(PillButton, '开启'), findsOneWidget);
    expect(find.text('修改'), findsNothing);
    expect(find.text('关闭 GitHub 登录'), findsNothing);
  });

  testWidgets('a site with GitHub can change it or close it', (tester) async {
    api.githubApp = _enabled;
    await open(tester);

    expect(find.text('已开启'), findsOneWidget);
    expect(find.text(_onText), findsOneWidget);
    expect(find.widgetWithText(PillButton, '修改'), findsOneWidget);
    expect(find.widgetWithText(PillButton, '关闭 GitHub 登录'), findsOneWidget);
  });

  testWidgets('the callback address is copied as it is', (tester) async {
    await open(tester);

    await tap(tester, find.widgetWithText(PillButton, '复制'));

    expect(copied, [_callback]);
    expect(notices, [(ToastKind.success, '已复制回调地址')]);
  });

  testWidgets('a copy the system refuses gives the address to copy by '
      'hand', (tester) async {
    clipboardFails = true;
    await open(tester);

    await tap(tester, find.widgetWithText(PillButton, '复制'));

    expect(notices, [(ToastKind.warning, '请手动复制回调地址：$_callback')]);
  });

  testWidgets('both fields are needed, blanks aside, before GitHub is turned '
      'on', (tester) async {
    await open(tester);
    await tap(tester, find.widgetWithText(PillButton, '开启'));
    expect(find.text('GitHub OAuth App'), findsOneWidget);
    expect(find.text('保存后不会再显示。'), findsOneWidget);
    // 组里的“开启”在前，面板里的在后。
    final submit = find.widgetWithText(PillButton, '开启').last;
    bool enabled() => tester.widget<PillButton>(submit).onPressed != null;

    expect(enabled(), isFalse);
    await tester.enterText(_field('Client ID'), 'Iv1.abc');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(_field('Client Secret'), '   ');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(_field('Client Secret'), ' secret-1 ');
    await tester.pump();
    expect(enabled(), isTrue);

    await tap(tester, submit);

    expect(api.savedGithubApps, [
      (clientId: 'Iv1.abc', clientSecret: 'secret-1'),
    ]);
    expect(find.text('GitHub OAuth App'), findsNothing);
    expect(notices, [(ToastKind.success, '已开启 GitHub 登录')]);
    expect(find.text('已开启'), findsOneWidget);
  });

  testWidgets('changing it fills in the client id and needs the secret '
      'again', (tester) async {
    api.githubApp = _enabled;
    await open(tester);
    await tap(tester, find.widgetWithText(PillButton, '修改'));

    expect(
      tester.widget<EditableText>(_field('Client ID')).controller.text,
      'Iv1.abc',
    );
    expect(find.text('已设置。已保存的不会显示，保存时要和 Client ID 一起重新填写。'), findsOneWidget);
    await tester.enterText(_field('Client Secret'), 'secret-2');
    await tester.pump();
    // 后台首页的品牌名也有“保存”按钮，面板中的在其之后。
    await tap(tester, find.widgetWithText(PillButton, '保存').last);

    expect(notices, [(ToastKind.success, '已保存 GitHub OAuth App')]);
  });

  testWidgets('a save that ends under another page still closes the sheet', (
    tester,
  ) async {
    api.setGithubAppGate = Completer<void>();
    await open(tester);
    await tap(tester, find.widgetWithText(PillButton, '开启'));
    await tester.enterText(_field('Client ID'), 'Iv1.abc');
    await tester.enterText(_field('Client Secret'), 'secret-1');
    await tester.pump();
    await tester.tap(find.widgetWithText(PillButton, '开启').last);
    await tester.pump();
    final navigator = Navigator.of(
      tester.element(find.text('GitHub OAuth App')),
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('邀请确认')),
      ),
    );
    // 保存中的忙碌指示一直在动，不能 pumpAndSettle。
    Future<void> pumpFrames() async {
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await pumpFrames();

    api.setGithubAppGate!.complete();
    await pumpFrames();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('邀请确认'), findsNothing);
    expect(find.text('GitHub OAuth App'), findsNothing);
    expect(notices, [(ToastKind.success, '已开启 GitHub 登录')]);
  });

  testWidgets('a client the server cannot accept is told in the sheet', (
    tester,
  ) async {
    api.setGithubAppError = const ApiException(
      code: 'INVALID_ARGUMENT',
      message: 'clientId 格式不对',
      status: 400,
    );
    await open(tester);
    await tap(tester, find.widgetWithText(PillButton, '开启'));
    await tester.enterText(_field('Client ID'), 'Iv1 abc');
    await tester.enterText(_field('Client Secret'), 'secret-1');
    await tester.pump();

    await tap(tester, find.widgetWithText(PillButton, '开启').last);

    expect(find.text('GitHub OAuth App'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InlineMessage),
        matching: find.text(githubAppInvalidText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('closing asks first, then says it is closed', (tester) async {
    api.githubApp = _enabled;
    await open(tester);

    await tap(tester, find.widgetWithText(PillButton, '关闭 GitHub 登录'));
    expect(find.text(_closeMessage), findsOneWidget);
    expect(api.deleteGithubAppCalls, 0);
    await tap(
      tester,
      find.descendant(of: find.byType(ConfirmSheet), matching: find.text('关闭')),
    );

    expect(api.deleteGithubAppCalls, 1);
    expect(notices, [(ToastKind.success, '已关闭 GitHub 登录')]);
    expect(find.text('未开启'), findsOneWidget);
  });

  testWidgets('a status that cannot be read can be read again', (tester) async {
    api.getGithubAppError = const ApiException(
      code: 'NETWORK',
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );
    await open(tester, loaded: false);

    api.getGithubAppError = null;
    await tap(
      tester,
      find.descendant(
        of: find.ancestor(
          of: find.text(_notLoadedText),
          matching: find.byType(InlineMessage),
        ),
        matching: find.widgetWithText(PillButton, '重试'),
      ),
    );

    expect(find.text('未开启'), findsOneWidget);
  });
}
