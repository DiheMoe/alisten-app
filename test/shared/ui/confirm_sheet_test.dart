import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GlobalKey<NavigatorState> navigator;

  Future<BuildContext> pumpPages(WidgetTester tester) async {
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
        home: const Text('首页'),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('第二页')),
      ),
    );
    await tester.pumpAndSettle();
    return tester.element(find.text('第二页'));
  }

  ({Completer<bool> check, Future<bool> result}) open(BuildContext page) {
    final check = Completer<bool>();
    final result = showConfirmSheet(
      page,
      title: '添加 新站？',
      message: '服务器：new.example.org。',
      confirmLabel: '添加',
      busyLabel: '正在检查服务器…',
      onConfirm: () => check.future,
    );
    return (check: check, result: result);
  }

  testWidgets('confirming waits for the check, busy and pressed once', (
    tester,
  ) async {
    final page = await pumpPages(tester);
    var checks = 0;
    final check = Completer<bool>();
    bool? result;
    unawaited(
      showConfirmSheet(
        page,
        title: '添加 新站？',
        message: '服务器：new.example.org。',
        confirmLabel: '添加',
        busyLabel: '正在检查服务器…',
        onConfirm: () {
          checks++;
          return check.future;
        },
      ).then((value) => result = value),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加'));
    await tester.pump();
    expect(find.text('正在检查服务器…'), findsOneWidget);
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, '正在检查服务器…'))
          .busy,
      isTrue,
    );
    await tester.tap(find.text('正在检查服务器…'), warnIfMissed: false);
    await tester.pump();
    expect(checks, 1);

    check.complete(true);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('第二页'), findsOneWidget);
  });

  testWidgets('a check ending under another page closes the sheet with '
      'its result, leaving the page', (tester) async {
    final page = await pumpPages(tester);
    final (:check, result: showing) = open(page);
    bool? result;
    unawaited(showing.then((value) => result = value));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pump();
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('邀请确认')),
      ),
    );
    // 等待检查时的忙碌指示一直在动，不能 pumpAndSettle。
    await tester.pump(const Duration(seconds: 1));

    check.complete(true);
    await tester.pump(const Duration(seconds: 1));

    expect(result, isTrue);
    expect(find.text('邀请确认'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('添加 新站？'), findsNothing);
    expect(find.text('第二页'), findsOneWidget);
  });

  for (final (moment, wait) in [
    ('while the sheet is closing', const Duration(milliseconds: 40)),
    ('after the sheet closed', const Duration(seconds: 1)),
  ]) {
    testWidgets('a check ending $moment, after cancelling, closes nothing '
        'more', (tester) async {
      final page = await pumpPages(tester);
      final (:check, result: showing) = open(page);
      bool? result;
      unawaited(showing.then((value) => result = value));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pump();

      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(wait);
      check.complete(true);
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('第二页'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isTrue);
    });
  }
}
