import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a toast shows an icon and text, is announced, and leaves after 3 s',
    (tester) async {
      final toasts = ToastController();
      addTearDown(toasts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          builder: (context, child) =>
              ToastHost(controller: toasts, child: child!),
          home: const AlistenScaffold(
            topBar: AlistenTopBar(title: '周五晚自习', subtitle: '4 人在线'),
            body: SizedBox.expand(),
          ),
        ),
      );

      toasts.show(ToastKind.failure, '点歌失败');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final text = find.text('点歌失败');
      expect(text, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ToastHost),
          matching: find.byIcon(Icons.error_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(text),
        isSemantics(label: '点歌失败', isLiveRegion: true),
      );
      // 提示不遮挡页面标题。
      expect(
        tester.getRect(text).top,
        greaterThanOrEqualTo(tester.getRect(find.text('4 人在线')).bottom),
      );

      await tester.pump(const Duration(milliseconds: 2600));
      expect(text, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(text, findsNothing);
      expect(toasts.current, isNull);
    },
  );

  testWidgets('a new toast replaces the shown one and restarts its time', (
    tester,
  ) async {
    final toasts = ToastController();
    addTearDown(toasts.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ToastHost(controller: toasts, child: child!),
        home: const SizedBox.expand(),
      ),
    );

    toasts.show(ToastKind.info, '第一条');
    await tester.pump(const Duration(seconds: 2));
    toasts.show(ToastKind.success, '第二条');
    await tester.pump();
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('第二条'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('第二条'), findsNothing);
  });

  testWidgets('a toast with an action stays longer, and its action runs once '
      'and takes the toast away', (tester) async {
    final toasts = ToastController();
    addTearDown(toasts.dispose);
    var undone = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ToastHost(controller: toasts, child: child!),
        home: const SizedBox.expand(),
      ),
    );

    toasts.show(
      ToastKind.info,
      '已删除《晴天》',
      action: ToastAction(label: '撤销', onPressed: () => undone++),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('已删除《晴天》'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('撤销')),
      isSemantics(label: '撤销', isButton: true, hasTapAction: true),
    );

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('已删除《晴天》'), findsNothing);
    expect(toasts.current, isNull);
  });

  testWidgets('with a screen reader on, a toast with an action stays until '
      'it is used or replaced', (tester) async {
    final toasts = ToastController();
    addTearDown(toasts.dispose);
    var undone = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: ToastHost(controller: toasts, child: child!),
        ),
        home: const SizedBox.expand(),
      ),
    );

    toasts.show(
      ToastKind.info,
      '已删除《晴天》',
      action: ToastAction(label: '撤销', onPressed: () => undone++),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('已删除《晴天》'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(toasts.current, isNull);

    toasts.show(
      ToastKind.info,
      '已删除《七里香》',
      action: ToastAction(label: '撤销', onPressed: () => undone++),
    );
    await tester.pump(const Duration(seconds: 30));
    toasts.show(ToastKind.success, '已点歌');
    await tester.pump();
    expect(find.text('已删除《七里香》'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('已点歌'), findsNothing, reason: 'no action, so it leaves');
  });

  testWidgets('a toast with an action kept for a screen reader leaves on its '
      'own once the screen reader is turned off', (tester) async {
    final toasts = ToastController();
    addTearDown(toasts.dispose);
    final accessible = ValueNotifier(true);
    addTearDown(accessible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder(
          valueListenable: accessible,
          builder: (context, on, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: on),
            child: ToastHost(controller: toasts, child: child!),
          ),
        ),
        home: const SizedBox.expand(),
      ),
    );

    toasts.show(
      ToastKind.info,
      '已删除《晴天》',
      action: ToastAction(label: '撤销', onPressed: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('已删除《晴天》'), findsOneWidget);

    accessible.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('已删除《晴天》'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('已删除《晴天》'), findsNothing);
    expect(toasts.current, isNull);
  });

  testWidgets('a screen reader can dismiss a toast that waits for its '
      'action', (tester) async {
    final semantics = tester.ensureSemantics();
    final toasts = ToastController();
    addTearDown(toasts.dispose);
    var undone = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: ToastHost(controller: toasts, child: child!),
        ),
        home: const SizedBox.expand(),
      ),
    );

    toasts.show(
      ToastKind.info,
      '已删除《晴天》',
      action: ToastAction(label: '撤销', onPressed: () => undone++),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final toast = find.semantics.byLabel(RegExp('已删除《晴天》'));
    expect(
      tester.getSemantics(find.text('已删除《晴天》')),
      isSemantics(isLiveRegion: true, hasDismissAction: true),
    );

    tester.semantics.performAction(toast, SemanticsAction.dismiss);
    await tester.pumpAndSettle();
    expect(find.text('已删除《晴天》'), findsNothing);
    expect(toasts.current, isNull);
    expect(undone, 0, reason: 'dismissing is not undoing');
    semantics.dispose();
  });

  test('a toast is withdrawn only while it is the one shown', () {
    final toasts = ToastController();
    addTearDown(toasts.dispose);

    final undo = toasts.show(ToastKind.info, '已删除《晴天》');
    final later = toasts.show(ToastKind.success, '已点歌');
    toasts.withdraw(undo);
    expect(toasts.current, same(later));

    toasts.withdraw(later);
    expect(toasts.current, isNull);
  });
}
