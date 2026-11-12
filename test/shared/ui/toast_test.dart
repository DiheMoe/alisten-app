import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
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
          matching: find.byIcon(AlistenIcons.warningCircleFill),
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

  testWidgets('a toast given its own time stays that long, and the next one '
      'is back to 3 s', (tester) async {
    final toasts = ToastController();
    addTearDown(toasts.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ToastHost(controller: toasts, child: child!),
        home: const SizedBox.expand(),
      ),
    );

    toasts.show(ToastKind.success, '长提示', duration: const Duration(seconds: 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5900));
    expect(find.text('长提示'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('长提示'), findsNothing);
    expect(toasts.current, isNull);

    toasts.show(ToastKind.info, '短提示');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('短提示'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('短提示'), findsNothing);
  });
}
