import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/admin_time.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart' show roomListing;
import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _hint = '粘贴 cookies.txt 的内容，或请求头里 cookie 的值';

const _cookies =
    '# Netscape HTTP Cookie File\n'
    '.youtube.com\tTRUE\t/\tTRUE\t1800000000\tSID\tsecret-sid\n';

const _saved = YoutubeCookieStatus(saved: true, updatedAtMs: 1700000000000);

const _network = ApiException(
  code: 'NETWORK',
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

const _steps = [
  '1. 在电脑浏览器打开无痕窗口，登录用来点歌的 YouTube 账号，账号可能被 YouTube '
      '封禁，建议用不常用的账号。',
  '2. 在同一个标签页打开 www.youtube.com/robots.txt，无痕窗口里只留这一个'
      '标签页。',
  '3. 用 Get cookies.txt LOCALLY 这类扩展导出 youtube.com 的 cookies.txt，或在'
      '开发者工具“网络”面板里复制 robots.txt 请求头中 cookie 的值。',
  '4. 保存之后直接关掉这个无痕窗口，不要再在里面打开 YouTube 的页面。',
];

final _cookieField = find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is AlistenTextField && widget.hint == _hint,
  ),
  matching: find.byType(EditableText),
);

// 后台首页的品牌名也有“保存”按钮，面板中的在其之后。
final _save = find.text('保存').last;

void main() {
  late FakeAdminApi api;
  late List<(ToastKind, String)> notices;
  late List<String> copied;

  setUp(() {
    api = FakeAdminApi();
    notices = [];
    copied = [];
  });

  Future<void> open(WidgetTester tester, {double textScale = 1}) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(AlistenTextField, '管理 token'),
        matching: find.byType(EditableText),
      ),
      't-1',
    );
    await tester.tap(find.text('进入后台'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('YouTube Cookie'),
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

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
  }

  String cookieText(WidgetTester tester) =>
      tester.widget<EditableText>(_cookieField).controller.text;

  testWidgets('without cookies the group says so and offers to fill them in, '
      'not to clear them', (tester) async {
    await open(tester);

    expect(find.text('YouTube Cookie'), findsOneWidget);
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('填写'), findsOneWidget);
    expect(find.text('覆盖'), findsNothing);
    expect(find.text('清除'), findsNothing);
  });

  testWidgets('saved cookies show when they were last filled in, and can be '
      'overwritten or cleared', (tester) async {
    api.youtubeCookie = _saved;
    await open(tester);

    expect(
      find.text('已配置，最近填写于 ${formatAdminTime(1700000000000)}'),
      findsOneWidget,
    );
    expect(find.text('覆盖'), findsOneWidget);
    expect(find.text('清除'), findsOneWidget);
    expect(find.text('填写'), findsNothing);
  });

  testWidgets('the group and its sheet fit a phone at twice the text size', (
    tester,
  ) async {
    api.youtubeCookie = _saved;
    await open(tester, textScale: 2);
    await tester.scrollUntilVisible(
      find.text('覆盖'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tap(tester, find.text('覆盖'));
    await tester.enterText(_cookieField, _cookies * 3);
    await tester.ensureVisible(_save);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_steps.last), findsOneWidget);
  });

  testWidgets('the status is announced as it changes', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(
      tester.getSemantics(find.text('未配置')),
      isSemantics(label: '未配置', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('the sheet explains the four steps and starts empty, without '
      'taking focus, even over saved cookies', (tester) async {
    api.youtubeCookie = _saved;
    await open(tester);

    await tap(tester, find.text('覆盖'));

    expect(find.text('填写 YouTube Cookie'), findsOneWidget);
    for (final step in _steps) {
      expect(find.text(step), findsOneWidget);
    }
    expect(cookieText(tester), isEmpty);
    expect(tester.widget<EditableText>(_cookieField).maxLines, 8);
    expect(
      tester.widget<EditableText>(_cookieField).focusNode.hasFocus,
      isFalse,
    );
    expect(find.bySemanticsLabel(_hint), findsOneWidget);
  });

  testWidgets('blank cookies ask for cookies and are not sent', (tester) async {
    await open(tester);
    await tap(tester, find.text('填写'));

    await tester.enterText(_cookieField, '  \n ');
    await tap(tester, _save);

    expect(find.text(youtubeCookieEmptyText), findsOneWidget);
    expect(api.savedCookies, isEmpty);
    expect(find.text('填写 YouTube Cookie'), findsOneWidget);
  });

  testWidgets('oversized cookies are pointed out as they come in and are not '
      'sent', (tester) async {
    final overhead = utf8.encode(jsonEncode({'cookies': ''})).length;
    await open(tester);
    await tap(tester, find.text('填写'));

    await tester.enterText(
      _cookieField,
      'a' * (youtubeCookieBodyLimit - overhead + 1),
    );
    await tester.pump();
    expect(find.text(youtubeCookieTooLargeText), findsOneWidget);

    await tap(tester, _save);

    expect(find.text(youtubeCookieTooLargeText), findsOneWidget);
    expect(api.savedCookies, isEmpty);
  });

  testWidgets('cookies the server cannot recognise are explained in its own '
      'words, and the sheet stays open with them', (tester) async {
    api.setYoutubeCookieError = const ApiException(
      code: 'INVALID_ARGUMENT',
      message: '没有识别出 YouTube 的 cookies',
      status: 400,
    );
    await open(tester);
    await tap(tester, find.text('填写'));

    await tester.enterText(_cookieField, 'not cookies');
    await tap(tester, _save);

    expect(find.text('没有识别出 YouTube 的 cookies'), findsOneWidget);
    expect(find.text('填写 YouTube Cookie'), findsOneWidget);
    expect(cookieText(tester), 'not cookies');
    expect(api.savedCookies, ['not cookies']);
    expect(notices, isEmpty);
  });

  testWidgets('saved cookies empty the field, close the sheet saying so, and '
      'the group shows the new time', (tester) async {
    await open(tester);
    await tap(tester, find.text('填写'));
    await tester.enterText(_cookieField, _cookies);
    // 输入框每半秒才记录一次撤销历史。
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(_save);
    await tester.pumpAndSettle();

    await tester.tap(_save);
    await tester.pump();
    expect(cookieText(tester), isEmpty);
    tester
        .state<UndoHistoryState<TextEditingValue>>(
          find.descendant(
            of: _cookieField,
            matching: find.byType(UndoHistory<TextEditingValue>),
          ),
        )
        .undo();
    await tester.pump();
    expect(cookieText(tester), isEmpty);
    await tester.pumpAndSettle();

    expect(api.savedCookies.single, _cookies);
    expect(notices, [(ToastKind.success, '已保存 YouTube Cookie')]);
    expect(_cookieField, findsNothing);
    expect(
      find.text('已配置，最近填写于 ${formatAdminTime(1800000000000)}'),
      findsOneWidget,
    );
    expect(find.text('覆盖'), findsOneWidget);
    expect(find.textContaining('secret-sid'), findsNothing);
  });

  testWidgets('a closed sheet forgets what was typed, undo included', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.text('填写'));
    await tester.enterText(_cookieField, 'SID=secret-sid');
    await tester.pump(const Duration(seconds: 1));

    await closeSheet(tester);
    expect(_cookieField, findsNothing);
    await tap(tester, find.text('填写'));

    expect(cookieText(tester), isEmpty);
    await tester.tap(_cookieField);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(cookieText(tester), isEmpty);
  });

  testWidgets('the cookie field lets text in but not out', (tester) async {
    await open(tester);
    await tap(tester, find.text('填写'));
    await tester.enterText(_cookieField, 'SID=secret-sid');
    await tester.pump();

    final field = tester.widget<EditableText>(_cookieField);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);

    // 长按开头的词，使菜单出现时有选中的文字。
    await tester.longPressAt(
      tester.getTopLeft(_cookieField) + const Offset(6, 10),
    );
    await tester.pumpAndSettle();
    expect(field.controller.selection.isCollapsed, isFalse);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(copied, isEmpty);
  });

  testWidgets('cookies without an answer close the sheet and ask for the '
      'status to be checked before trying again', (tester) async {
    api.setYoutubeCookieError = _network;
    await open(tester);
    await tap(tester, find.text('填写'));
    final read = api.getYoutubeCookieCalls;

    await tester.enterText(_cookieField, _cookies);
    await tap(tester, _save);

    expect(api.savedCookies, hasLength(1));
    expect(api.getYoutubeCookieCalls, read + 1);
    expect(_cookieField, findsNothing);
    expect(notices, [(ToastKind.warning, '结果未知，请确认状态后再决定是否重新填写。')]);
  });

  testWidgets('cookies being saved keep the sheet open until the answer', (
    tester,
  ) async {
    final gate = api.setYoutubeCookieGate = Completer();
    await open(tester);
    await tap(tester, find.text('填写'));
    await tester.enterText(_cookieField, _cookies);
    await tester.ensureVisible(_save);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pump();

    await tester.tapAt(const Offset(20, 40));
    await tester.pump(const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.text('填写 YouTube Cookie'), const Offset(0, 600));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('填写 YouTube Cookie'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(notices, [(ToastKind.success, '已保存 YouTube Cookie')]);
    expect(_cookieField, findsNothing);
  });

  testWidgets('a clear still says how it ended and reads the status again '
      'when the list is scrolled away meanwhile', (tester) async {
    api
      ..youtubeCookie = _saved
      ..rooms = [
        for (var i = 0; i < 40; i++) roomListing(id: 'r$i', name: '房间 $i'),
      ];
    await open(tester);
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('清除'), 300, scrollable: list);
    await tester.pumpAndSettle();
    final gate = api.deleteYoutubeCookieGate = Completer();
    await tap(tester, find.text('清除'));
    // 清除期间按钮持续转圈，不能等待动画停止。
    await tester.tap(find.text('清除').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final read = api.getYoutubeCookieCalls;

    await tester.scrollUntilVisible(find.text('品牌名'), -300, scrollable: list);
    await tester.pump(const Duration(seconds: 1));
    gate.complete();
    await tester.pumpAndSettle();

    expect(api.deleteYoutubeCookieCalls, 1);
    expect(notices, [(ToastKind.success, '已清除 YouTube Cookie')]);
    expect(api.getYoutubeCookieCalls, read + 1);
    await tester.scrollUntilVisible(find.text('未配置'), 300, scrollable: list);
    expect(find.text('清除'), findsNothing);
  });

  testWidgets('cookies are cleared only after a confirmation that says what '
      'changes', (tester) async {
    api.youtubeCookie = _saved;
    await open(tester);

    await tap(tester, find.text('清除'));
    expect(find.text('清除 YouTube Cookie？'), findsOneWidget);
    expect(find.text('清除后，下载 YouTube 链接时不再携带 cookies'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(api.deleteYoutubeCookieCalls, 0);

    await tap(tester, find.text('清除'));
    await tap(tester, find.text('清除').last);

    expect(api.deleteYoutubeCookieCalls, 1);
    expect(notices, [(ToastKind.success, '已清除 YouTube Cookie')]);
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('清除'), findsNothing);
  });

  testWidgets('a clear without an answer asks for the status to be checked', (
    tester,
  ) async {
    api
      ..youtubeCookie = _saved
      ..deleteYoutubeCookieError = _network;
    await open(tester);

    await tap(tester, find.text('清除'));
    await tap(tester, find.text('清除').last);

    expect(notices, [(ToastKind.warning, '结果未知，请确认状态后再决定是否重试。')]);
  });

  testWidgets('a clear the server could not finish asks for the status to be '
      'checked, and the status is read again', (tester) async {
    api
      ..youtubeCookie = _saved
      ..deleteYoutubeCookieError = const ApiException(
        code: 'INTERNAL',
        message: '服务器出错了',
        status: 500,
      );
    await open(tester);
    final read = api.getYoutubeCookieCalls;

    await tap(tester, find.text('清除'));
    await tap(tester, find.text('清除').last);

    expect(notices, [(ToastKind.warning, '结果未知，请确认状态后再决定是否重试。')]);
    expect(api.deleteYoutubeCookieCalls, 1);
    expect(api.getYoutubeCookieCalls, read + 1);
  });

  testWidgets('a clear turned away for coming too often says so', (
    tester,
  ) async {
    api
      ..youtubeCookie = _saved
      ..deleteYoutubeCookieError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
      );
    await open(tester);

    await tap(tester, find.text('清除'));
    await tap(tester, find.text('清除').last);

    expect(notices, [(ToastKind.failure, '请求太频繁，请稍后再试。')]);
  });

  testWidgets('a status that cannot be read can be read again, and cookies '
      'can still be filled in', (tester) async {
    api.getYoutubeCookieError = const ApiException.protocolMismatch(200);
    await open(tester);

    expect(find.text('服务器返回了无法识别的数据，请升级 Alisten。'), findsOneWidget);
    await tap(tester, find.text('填写'));
    expect(find.text('填写 YouTube Cookie'), findsOneWidget);
    await closeSheet(tester);

    api.getYoutubeCookieError = null;
    await tap(tester, find.text('重试').last);

    expect(find.text('服务器返回了无法识别的数据，请升级 Alisten。'), findsNothing);
    expect(find.text('未配置'), findsOneWidget);
  });
}
