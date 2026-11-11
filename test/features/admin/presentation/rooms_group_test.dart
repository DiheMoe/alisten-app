import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/admin_time.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/idle_frames.dart';
import '../../lobby/lobby_test_doubles.dart' show roomListing;
import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _network = ApiException(
  code: 'NETWORK',
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

const _internal = ApiException(
  code: 'INTERNAL',
  message: '服务器出错了',
  status: 500,
);

const _resetLost =
    'Key 已重置，但没有收到新 Key，请再重置一次。旧 Key 已不能发起新请求，'
    '但已经连上的 bot 可能还没有断开。';

const _everyoneVerifiesAgain = '房间里的所有人都需要重新验证。';
const _youDisconnectToo = '你也会断开，需要重新输入密码。';

// 后台首页的品牌名也有“保存”按钮，面板中的在其之后。
final _save = find.text('保存').last;

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(AlistenTextField, label),
  matching: find.byType(EditableText),
);

void main() {
  late FakeAdminApi api;
  late FakeSensitiveClipboard sensitive;
  late List<String> copied;
  late List<(ToastKind, String)> notices;
  late List<String> opened;
  late String? activeRoomId;
  late ProviderContainer container;

  setUp(() {
    api = FakeAdminApi()
      ..rooms = [
        roomListing(
          id: 'r1',
          name: '大厅',
          slug: 'hall',
          hasPassword: true,
          onlineCount: 3,
        ),
      ];
    sensitive = FakeSensitiveClipboard();
    copied = [];
    notices = [];
    opened = [];
    activeRoomId = null;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    container = ProviderContainer(
      overrides: [
        ...await switchingOverrides(
          store: FakeServerStore(profiles: [serverB]),
          credentials: FakeCredentialStores(),
        ),
        adminApiProvider.overrideWithValue(api),
        sensitiveClipboardProvider.overrideWithValue(sensitive),
        roomControllerProvider.overrideWithBuild(
          (ref, _) => RoomState(activeRoomId: activeRoomId),
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
            onOpenRoom: opened.add,
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
      find.text('常驻房间'),
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

  Future<void> act(
    WidgetTester tester,
    String action, {
    String room = '大厅',
  }) async {
    await tap(tester, find.text(room));
    await tap(tester, find.text(action));
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
  }

  testWidgets('the rooms are listed with their alias or id, the people online '
      'and whether a password is needed', (tester) async {
    api.rooms = [
      ...api.rooms,
      roomListing(id: 'r2', name: '小厅', slug: null, onlineCount: 0),
    ];
    await open(tester);

    expect(find.text('常驻房间'), findsOneWidget);
    expect(find.text('大厅'), findsOneWidget);
    expect(find.text('hall'), findsOneWidget);
    expect(find.text('在线 3 人'), findsOneWidget);
    expect(find.text('小厅'), findsOneWidget);
    expect(find.text('r2'), findsOneWidget);
    expect(find.text('在线 0 人'), findsOneWidget);
    expect(find.text('有密码'), findsOneWidget);
    expect(find.text('新建常驻房间'), findsOneWidget);
  });

  testWidgets('the rooms page draws nothing while left alone', (tester) async {
    await open(tester);

    expect(await idleFrames(tester), 0);
  });

  testWidgets('a room is entered by its alias, or by its id without one', (
    tester,
  ) async {
    api.rooms = [...api.rooms, roomListing(id: 'r2', name: '小厅', slug: null)];
    await open(tester);

    await act(tester, '进入');
    await act(tester, '进入', room: '小厅');

    expect(opened, ['hall', 'r2']);
  });

  testWidgets('the invite link of a room is copied with the link host of the '
      'current server', (tester) async {
    await open(tester);

    await act(tester, '复制邀请链接');

    expect(copied, ['https://livehouse.dihe.moe/r/hall']);
    expect(notices, [(ToastKind.success, '邀请链接已复制')]);
  });

  group('the room form', () {
    testWidgets('takes no focus by itself and keeps the password unchanged '
        'unless asked', (tester) async {
      await open(tester);

      await act(tester, '编辑');

      expect(find.text('编辑常驻房间'), findsOneWidget);
      for (final field in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        expect(field.focusNode.hasFocus, isFalse);
      }
      expect(tester.widget<EditableText>(_field('房间名称')).controller.text, '大厅');
      expect(
        tester.widget<EditableText>(_field('别名（可选）')).controller.text,
        'hall',
      );
      expect(find.text('保持'), findsOneWidget);
      expect(_field('新密码'), findsNothing);
      expect(find.textContaining(_everyoneVerifiesAgain), findsNothing);
    });

    testWidgets('setting a password warns that everyone in the room verifies '
        'again', (tester) async {
      activeRoomId = 'another-room';
      await open(tester);

      await act(tester, '编辑');
      await tap(tester, find.text('设置或修改'));

      expect(_field('新密码'), findsOneWidget);
      expect(tester.widget<EditableText>(_field('新密码')).obscureText, isTrue);
      expect(find.textContaining(_everyoneVerifiesAgain), findsOneWidget);
      expect(find.textContaining(_youDisconnectToo), findsNothing);
    });

    testWidgets('setting a password on the room this device is in warns that '
        'it disconnects too', (tester) async {
      activeRoomId = 'r1';
      await open(tester);

      await act(tester, '编辑');
      await tap(tester, find.text('设置或修改'));

      expect(find.textContaining(_everyoneVerifiesAgain), findsOneWidget);
      expect(find.textContaining(_youDisconnectToo), findsOneWidget);
    });

    testWidgets('an alias against the rule is pointed out as it is typed and '
        'not sent', (tester) async {
      await open(tester);
      await act(tester, '编辑');

      await tester.enterText(_field('别名（可选）'), 'Hall');
      await tester.pump();
      expect(find.text(roomSlugRuleText), findsOneWidget);

      await tap(tester, _save);

      expect(api.updates, isEmpty);
      expect(find.text(roomSlugRuleText), findsOneWidget);
      expect(find.text('编辑常驻房间'), findsOneWidget);
      expect(notices, isEmpty);
    });

    testWidgets('an alias previews the invite link; without one the link '
        'uses the room id', (tester) async {
      await open(tester);

      await tap(tester, find.text('新建常驻房间'));
      expect(find.text('不填别名时，邀请链接使用房间 ID'), findsOneWidget);

      await tester.enterText(_field('别名（可选）'), 'late-night');
      await tester.pump();
      expect(
        find.text('邀请链接：https://livehouse.dihe.moe/r/late-night'),
        findsOneWidget,
      );
      expect(find.text('不填别名时，邀请链接使用房间 ID'), findsNothing);
    });

    testWidgets('a new room is created with the password given, and the '
        'sheet closes saying so', (tester) async {
      await open(tester);

      await tap(tester, find.text('新建常驻房间'));
      expect(tester.widget<EditableText>(_field('密码（可选）')).obscureText, isTrue);
      await tester.enterText(_field('房间名称'), ' 小厅 ');
      await tester.enterText(_field('别名（可选）'), 'small');
      await tester.enterText(_field('密码（可选）'), 'p');
      await tap(tester, _save);

      final draft = api.createdDrafts.single;
      expect(draft.name, '小厅');
      expect(draft.slug, 'small');
      expect(draft.password, 'p');
      expect(notices, [(ToastKind.success, '已保存')]);
      expect(_field('密码（可选）'), findsNothing);
      expect(find.text('小厅'), findsOneWidget);
      expect(find.text('small'), findsOneWidget);
    });

    testWidgets('a change sends only what changed and the list follows', (
      tester,
    ) async {
      await open(tester);
      await act(tester, '编辑');

      await tester.enterText(_field('房间名称'), '大厅二号');
      await tap(tester, _save);

      final update = api.updates.single;
      expect(update.roomId, 'r1');
      expect(update.patch.name, '大厅二号');
      expect(update.patch.description, isNull);
      expect(update.patch.slug, isNull);
      expect(update.patch.password, isNull);
      expect(notices, [(ToastKind.success, '已保存')]);
      expect(find.text('编辑常驻房间'), findsNothing);
      expect(find.text('大厅二号'), findsOneWidget);
    });

    testWidgets('an alias already taken is explained in the sheet', (
      tester,
    ) async {
      api.updateRoomError = const ApiException(
        code: 'CONFLICT',
        message: 'slug taken',
        status: 409,
      );
      await open(tester);
      await act(tester, '编辑');

      await tester.enterText(_field('别名（可选）'), 'lounge');
      await tap(tester, _save);

      expect(find.text('这个别名已被占用'), findsOneWidget);
      expect(find.text('编辑常驻房间'), findsOneWidget);
      expect(notices, isEmpty);
    });

    testWidgets('a room without a password offers no way to take one away', (
      tester,
    ) async {
      api.rooms = [
        ...api.rooms,
        roomListing(id: 'r2', name: '小厅', slug: 'small', hasPassword: false),
      ];
      await open(tester);

      await act(tester, '编辑', room: '小厅');
      expect(find.text('保持'), findsOneWidget);
      expect(find.text('设置或修改'), findsOneWidget);
      expect(find.text('取消'), findsNothing);
      await closeSheet(tester);

      await act(tester, '编辑');
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('the name is limited the way the server counts it: blanks '
        'around it do not count, and each code point does', (tester) async {
      await open(tester);
      await act(tester, '编辑');
      String name() =>
          tester.widget<EditableText>(_field('房间名称')).controller.text;
      // 先清空，以免被当作在已满的输入框中继续输入。
      Future<void> paste(String text) async {
        await tester.enterText(_field('房间名称'), '');
        await tester.enterText(_field('房间名称'), text);
      }

      final blanked = ' ${'长' * 80} ';
      await paste(blanked);
      expect(name(), blanked);

      await paste('长' * 81);
      expect(name(), '长' * 80);

      // 一个字形由五个码点组成，放不下时整个舍弃，不拆开。
      const family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}';
      final full = '${'长' * 75}$family';
      await paste(full);
      expect(name(), full);
      await tester.enterText(_field('房间名称'), '$full长');
      expect(name(), full);

      await paste('${'长' * 76}$family');
      expect(name(), '长' * 76);
    }, variant: TargetPlatformVariant.mobile());

    testWidgets('a change the server could not finish closes the sheet and '
        'asks for the list to be checked', (tester) async {
      api.updateRoomError = _internal;
      await open(tester);
      await act(tester, '编辑');

      await tester.enterText(_field('房间名称'), '大厅二号');
      await tap(tester, _save);

      expect(api.updates, hasLength(1));
      expect(find.text('编辑常驻房间'), findsNothing);
      expect(notices, [(ToastKind.warning, '结果未知，请查看列表确认后再决定是否重试。')]);
    });

    testWidgets('a room turned away for coming too often says so in the '
        'sheet, which stays open', (tester) async {
      api.createRoomError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
      );
      await open(tester);
      await tap(tester, find.text('新建常驻房间'));
      await tester.enterText(_field('房间名称'), '小厅');

      await tap(tester, _save);

      expect(find.text('请求太频繁，请稍后再试。'), findsOneWidget);
      expect(_field('房间名称'), findsOneWidget);
      expect(notices, isEmpty);
    });

    testWidgets('a room the server finds against its rules asks for the form '
        'to be checked, without the server wording', (tester) async {
      api.createRoomError = const ApiException(
        code: 'INVALID_ARGUMENT',
        message: 'name：不能包含 U+0000',
        status: 400,
      );
      await open(tester);
      await tap(tester, find.text('新建常驻房间'));
      await tester.enterText(_field('房间名称'), '小厅');

      await tap(tester, _save);

      expect(find.text('提交的内容不符合要求，请检查后再试。'), findsOneWidget);
      expect(find.textContaining('U+0000'), findsNothing);
    });

    testWidgets('a room being created keeps its sheet open until the answer', (
      tester,
    ) async {
      final gate = api.createRoomGate = Completer();
      await open(tester);
      await tap(tester, find.text('新建常驻房间'));
      await tester.enterText(_field('房间名称'), '小厅');
      await tester.ensureVisible(_save);
      await tester.pumpAndSettle();
      await tester.tap(_save);
      await tester.pump();

      await tester.tapAt(const Offset(20, 40));
      await tester.pump(const Duration(seconds: 1));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('新建常驻房间'), findsNWidgets(2));

      gate.complete();
      await tester.pumpAndSettle();
      expect(notices, [(ToastKind.success, '已保存')]);
      expect(_field('房间名称'), findsNothing);
    });

    testWidgets('a save that ends under another page still closes the '
        'sheet', (tester) async {
      final gate = api.createRoomGate = Completer();
      await open(tester);
      await tap(tester, find.text('新建常驻房间'));
      await tester.enterText(_field('房间名称'), '小厅');
      await tester.ensureVisible(_save);
      await tester.pumpAndSettle();
      await tester.tap(_save);
      await tester.pump();
      final navigator = Navigator.of(tester.element(_field('房间名称')));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('邀请确认')),
        ),
      );
      // 保存中的忙碌指示一直在动，不能 pumpAndSettle。
      await tester.pump(const Duration(seconds: 1));

      gate.complete();
      await tester.pump(const Duration(seconds: 1));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('邀请确认'), findsNothing);
      expect(_field('房间名称'), findsNothing);
      expect(notices, [(ToastKind.success, '已保存')]);
    });
  });

  testWidgets('a room is deleted only after a confirmation that says who '
      'is disconnected', (tester) async {
    await open(tester);

    await act(tester, '删除');
    expect(find.text('删除常驻房间？'), findsOneWidget);
    expect(find.text('删除「大厅」后，房间里的所有人都会断开连接。'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(api.deletedRoomIds, isEmpty);

    await act(tester, '删除');
    await tap(tester, find.text('删除'));

    expect(api.deletedRoomIds, ['r1']);
    expect(find.text('大厅'), findsNothing);
  });

  testWidgets('a new room without an answer closes its sheet and asks for the '
      'list to be checked before trying again', (tester) async {
    api.createRoomError = _network;
    await open(tester);
    await tap(tester, find.text('新建常驻房间'));
    await tester.enterText(_field('房间名称'), '小厅');

    await tap(tester, _save);

    expect(api.createdDrafts, hasLength(1));
    expect(_field('房间名称'), findsNothing);
    expect(notices, [(ToastKind.warning, '结果未知，请查看列表确认后再决定是否重试。')]);
  });

  testWidgets('a deletion without an answer asks for the list to be checked', (
    tester,
  ) async {
    api.deleteRoomError = _network;
    await open(tester);

    await act(tester, '删除');
    await tap(tester, find.text('删除'));

    expect(notices, [(ToastKind.warning, '结果未知，请查看列表确认房间是否已删除。')]);
  });

  testWidgets('deleting again a room already gone says it is deleted and the '
      'list follows', (tester) async {
    await open(tester);
    api
      ..deleteRoomError = const ApiException(
        code: 'NOT_FOUND',
        message: '房间不存在',
        status: 404,
      )
      ..rooms = [];

    await act(tester, '删除');
    await tap(tester, find.text('删除'));

    expect(notices, [(ToastKind.success, '已删除「大厅」')]);
    expect(find.text('大厅'), findsNothing);
  });

  group('the API key', () {
    Future<void> showNewKey(WidgetTester tester) async {
      await act(tester, 'API Key');
      await tap(tester, find.text('重置 API Key'));
      await tap(tester, find.text('重置'));
      expect(find.text('k-new'), findsOneWidget);
    }

    Future<void> reset(WidgetTester tester, {required String label}) async {
      await act(tester, 'API Key');
      await tap(tester, find.text('$label API Key'));
      await tap(tester, find.text(label));
    }

    testWidgets(
      'the selection menu copies the key marked sensitive and '
      'offers nothing that hands it to another app',
      (tester) async {
        await open(tester);
        await showNewKey(tester);

        await tester.longPress(find.text('k-new'));
        await tester.pumpAndSettle();
        for (final label in ['Share', 'Share...', 'Look Up', 'Search Web']) {
          expect(find.text(label), findsNothing, reason: label);
        }
        if (find.text('Select all').evaluate().isNotEmpty) {
          await tap(tester, find.text('Select all'));
        } else if (find.text('Select All').evaluate().isNotEmpty) {
          await tap(tester, find.text('Select All'));
        }
        for (final label in ['Share', 'Share...', 'Look Up', 'Search Web']) {
          expect(find.text(label), findsNothing, reason: label);
        }
        await tap(tester, find.text('Copy'));

        expect(sensitive.copied, ['k-new']);
        expect(copied, isEmpty);
        expect(notices, [(ToastKind.success, 'API Key 已复制')]);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );

    testWidgets('a key copied from the keyboard is marked sensitive too', (
      tester,
    ) async {
      await open(tester);
      await showNewKey(tester);
      await tester.tap(find.text('k-new'));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(sensitive.copied, ['k-new']);
      expect(copied, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('even after the sensitive copy has failed, copying from the '
        'menu never puts the key on the plain clipboard', (tester) async {
      sensitive.error = StateError('clipboard unavailable');
      await open(tester);
      await showNewKey(tester);
      await tap(tester, find.text('复制'));
      expect(notices, [(ToastKind.failure, '没能复制，请重试。')]);

      await tester.longPress(find.text('k-new'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Select all'));
      await tap(tester, find.text('Copy'));

      expect(copied, isEmpty);
      expect(sensitive.copied, isEmpty);
      expect(notices, [
        (ToastKind.failure, '没能复制，请重试。'),
        (ToastKind.failure, '没能复制，请重试。'),
      ]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a key not yet copied is not let go without a confirmation', (
      tester,
    ) async {
      await open(tester);
      await showNewKey(tester);

      await closeSheet(tester);
      expect(find.text('还没有复制 Key，关闭后不能再查看。确定关闭？'), findsOneWidget);
      await tap(tester, find.text('取消'));
      expect(find.text('k-new'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('还没有复制 Key，关闭后不能再查看。确定关闭？'), findsOneWidget);
      await tap(tester, find.text('关闭'));

      expect(find.text('k-new'), findsNothing);
      expect(find.text('重置 API Key'), findsNothing);
    });

    testWidgets('dragging away a key not yet copied asks first', (
      tester,
    ) async {
      await open(tester);
      await showNewKey(tester);

      await tester.timedDrag(
        find.bySemanticsLabel(
          const DefaultMaterialLocalizations().closeButtonLabel,
        ),
        const Offset(0, 600),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有复制 Key，关闭后不能再查看。确定关闭？'), findsOneWidget);
      expect(find.text('k-new'), findsOneWidget);
    });

    testWidgets('a key not yet copied goes without a question when the '
        'session ends', (tester) async {
      await open(tester);
      await showNewKey(tester);

      container.read(adminSessionProvider.notifier).end();
      await tester.pumpAndSettle();

      expect(find.text('k-new'), findsNothing);
      expect(find.text('还没有复制 Key，关闭后不能再查看。确定关闭？'), findsNothing);
      expect(find.text('进入后台'), findsOneWidget);
    });

    // 服务端重置 Key 后若通知断开事件流失败，会回复 UNAVAILABLE：Key 已更换，
    // 用旧 Key 打开的事件流却未断开。
    testWidgets('a reset the server could not finish after the key was reset '
        'says the old key takes no new requests, bots still connected may '
        'stay, and to reset again', (tester) async {
      await open(tester);
      await act(tester, 'API Key');
      api
        ..resetApiKeyError = const ApiException(
          code: 'UNAVAILABLE',
          message: '房间暂时不可用，请稍后再试。',
          status: 503,
        )
        ..apiKeyStatus = const ApiKeyStatus(
          generated: true,
          createdAtMs: 1800000000000,
        );

      await tap(tester, find.text('重置 API Key'));
      await tap(tester, find.text('重置'));

      expect(find.text(_resetLost), findsOneWidget);
      expect(find.textContaining('旧 Key 已失效'), findsNothing);
      expect(find.textContaining('房间暂时不可用'), findsNothing);
    });

    testWidgets('a reset without an answer after which the key was reset says '
        'so for certain', (tester) async {
      await open(tester);
      await act(tester, 'API Key');
      api
        ..resetApiKeyError = _network
        ..apiKeyStatus = const ApiKeyStatus(
          generated: true,
          createdAtMs: 1800000000000,
        );

      await tap(tester, find.text('重置 API Key'));
      await tap(tester, find.text('重置'));

      expect(find.text(_resetLost), findsOneWidget);
    });

    testWidgets('a reset the server could not finish that leaves the '
        'generation time alone says the result is unknown', (tester) async {
      api.resetApiKeyError = _internal;
      await open(tester);

      await reset(tester, label: '重置');

      expect(find.text('结果未知，旧 Key 可能已经失效。请确认生成时间后再决定是否重置。'), findsOneWidget);
      expect(find.textContaining('服务器出错了'), findsNothing);
    });

    testWidgets('a reset turned away for coming too often says so, with no '
        'old key to worry about', (tester) async {
      api.resetApiKeyError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
      );
      await open(tester);

      await reset(tester, label: '重置');

      expect(find.text('请求太频繁，请稍后再试。'), findsOneWidget);
      expect(find.textContaining('旧 Key'), findsNothing);
    });

    testWidgets('a room that no longer exists has no key to lose', (
      tester,
    ) async {
      api.resetApiKeyError = const ApiException(
        code: 'NOT_FOUND',
        message: '房间不存在',
        status: 404,
      );
      await open(tester);

      await reset(tester, label: '重置');

      expect(find.textContaining('房间不存在'), findsOneWidget);
      expect(find.textContaining('旧 Key'), findsNothing);
    });

    testWidgets('a first key generated without reaching the sheet asks to '
        'generate again, with no old key to speak of', (tester) async {
      api.apiKeyStatus = const ApiKeyStatus(generated: false, createdAtMs: 0);
      await open(tester);
      await act(tester, 'API Key');
      api
        ..resetApiKeyError = _internal
        ..apiKeyStatus = const ApiKeyStatus(
          generated: true,
          createdAtMs: 1800000000000,
        );

      await tap(tester, find.text('生成 API Key'));
      await tap(tester, find.text('生成'));

      expect(find.text('Key 已生成，但没有收到它，请再生成一次。'), findsOneWidget);
      expect(find.textContaining('旧 Key'), findsNothing);
    });

    testWidgets('a reset sent before the session ended warns, after the sheet '
        'is gone, that the old key may be gone', (tester) async {
      final gate = api.resetApiKeyGate = Completer();
      await open(tester);
      await act(tester, 'API Key');
      await tap(tester, find.text('重置 API Key'));
      await tester.tap(find.text('重置'));
      await tester.pump(const Duration(seconds: 1));

      container.read(adminSessionProvider.notifier).end();
      await tester.pump(const Duration(seconds: 1));
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('进入后台'), findsOneWidget);
      expect(notices, [(ToastKind.warning, 'Key 可能已经重置，旧 Key 可能已失效。')]);
    });

    testWidgets('a new key is shown once: copied marked sensitive, and gone '
        'once the sheet closes', (tester) async {
      await open(tester);

      await act(tester, 'API Key');
      expect(
        find.text('已生成，生成于 ${formatAdminTime(1700000000000)}'),
        findsOneWidget,
      );

      await tap(tester, find.text('重置 API Key'));
      expect(find.text('重置 API Key？'), findsOneWidget);
      expect(find.text('重置后旧 Key 立即失效，正在使用它的 bot 需要换成新 Key。'), findsOneWidget);
      await tap(tester, find.text('重置'));

      expect(find.text('k-new'), findsOneWidget);
      expect(find.text('关闭后不能再查看，请现在复制'), findsOneWidget);
      expect(
        find.text('已生成，生成于 ${formatAdminTime(1800000000000)}'),
        findsOneWidget,
      );

      await tap(tester, find.text('复制'));
      expect(sensitive.copied, ['k-new']);
      expect(copied, isEmpty);
      expect(notices, [(ToastKind.success, 'API Key 已复制')]);

      await closeSheet(tester);
      expect(find.text('k-new'), findsNothing);

      await act(tester, 'API Key');
      expect(find.text('k-new'), findsNothing);
      expect(find.textContaining('已生成'), findsOneWidget);
      expect(find.text('关闭后不能再查看，请现在复制'), findsNothing);
    });

    testWidgets('a first key is generated after a confirmation that it shows '
        'only once', (tester) async {
      api.apiKeyStatus = const ApiKeyStatus(generated: false, createdAtMs: 0);
      await open(tester);

      await act(tester, 'API Key');
      expect(find.text('还没有生成 API Key'), findsOneWidget);

      await tap(tester, find.text('生成 API Key'));
      expect(find.text('生成 API Key？'), findsOneWidget);
      expect(find.text('新 Key 只显示一次，生成后请立即复制。'), findsOneWidget);
      await tap(tester, find.text('生成'));

      expect(api.resetApiKeyCalls, 1);
      expect(find.text('k-new'), findsOneWidget);
    });

    testWidgets('a key that cannot be copied asks for another try and stays '
        'off the plain clipboard', (tester) async {
      sensitive.error = StateError('clipboard unavailable');
      await open(tester);
      await act(tester, 'API Key');
      await tap(tester, find.text('重置 API Key'));
      await tap(tester, find.text('重置'));

      await tap(tester, find.text('复制'));

      expect(notices, [(ToastKind.failure, '没能复制，请重试。')]);
      expect(copied, isEmpty);
      expect(find.text('k-new'), findsOneWidget);
    });

    testWidgets('a reset without an answer says the old key may be gone and '
        'reads the status again', (tester) async {
      await open(tester);
      await act(tester, 'API Key');
      final read = api.getApiKeyStatusCalls;
      api.resetApiKeyError = const ApiException(
        code: 'NETWORK',
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await tap(tester, find.text('重置 API Key'));
      await tap(tester, find.text('重置'));

      expect(find.text('结果未知，旧 Key 可能已经失效。请确认生成时间后再决定是否重置。'), findsOneWidget);
      expect(api.getApiKeyStatusCalls, read + 1);
      expect(find.text('k-new'), findsNothing);
    });

    testWidgets('the sheet stays open while a key is being reset', (
      tester,
    ) async {
      final gate = api.resetApiKeyGate = Completer();
      await open(tester);
      await act(tester, 'API Key');
      await tap(tester, find.text('重置 API Key'));
      await tester.tap(find.text('重置'));
      await tester.pump(const Duration(seconds: 1));

      await tester.tapAt(const Offset(20, 40));
      await tester.pump(const Duration(seconds: 1));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('重置 API Key'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('k-new'), findsOneWidget);
    });
  });
}
