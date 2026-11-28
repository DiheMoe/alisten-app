import 'package:alisten/app/desktop/desktop_window_frame.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/window_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test_harness.dart';

void main() {
  testWidgets(
    'on Windows exposes WindowChrome without adding top padding and wires '
    'caption buttons + close corner clipping',
    (tester) async {
      final control = FakeWindowControl();
      double? childTopPadding;
      WindowChromeData? chrome;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: DesktopWindowFrame(
            control: control,
            child: Builder(
              builder: (context) {
                childTopPadding = MediaQuery.paddingOf(context).top;
                chrome = WindowChrome.of(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(childTopPadding, 0);
      expect(chrome?.titleBarHeight, desktopTitleBarHeight);
      expect(chrome?.rightInset, desktopCaptionButtonsWidth);
      expect(find.bySemanticsLabel('最小化'), findsOneWidget);
      expect(find.bySemanticsLabel('最大化'), findsOneWidget);
      expect(find.bySemanticsLabel('关闭'), findsOneWidget);

      BoxDecoration closeDecoration() =>
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(const ValueKey('window-close')),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      expect(
        closeDecoration().borderRadius,
        const BorderRadius.only(topRight: Radius.circular(8)),
      );

      await tester.tap(find.byKey(const ValueKey('window-minimize')));
      await tester.tap(find.byKey(const ValueKey('window-maximize')));
      await tester.tap(find.byKey(const ValueKey('window-close')));
      expect(control.minimizeCalls, 1);
      expect(control.toggleMaximizeCalls, 1);
      expect(control.closeCalls, 1);

      control.emitMaximized(true);
      await tester.pump();
      expect(find.bySemanticsLabel('还原'), findsOneWidget);
      expect(find.bySemanticsLabel('最大化'), findsNothing);
      expect(closeDecoration().borderRadius, BorderRadius.zero);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  group('the top bar of a page under the merged title bar', () {
    late FakeWindowControl control;
    late int pressed;

    Future<void> pump(WidgetTester tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
      control = FakeWindowControl();
      pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: DesktopWindowFrame(
            control: control,
            child: AlistenScaffold(
              contentMaxWidth: double.infinity,
              topBar: AlistenTopBar(
                title: '标题',
                actions: [
                  IconCircleButton(
                    icon: AlistenIcons.copy,
                    semanticLabel: '设置',
                    onPressed: () => pressed++,
                  ),
                ],
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // 标题和按钮之间的空白。
    const blank = Offset(400, 20);
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    testWidgets('keeps its buttons clear of the window buttons, and they '
        'still take clicks', (tester) async {
      await pump(tester);
      final action = find.byType(IconCircleButton);
      expect(
        tester.getRect(action).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('window-minimize'))).left,
        ),
      );

      await tester.tap(action);
      expect(pressed, 1);
      expect(control.startDraggingCalls, 0);
    }, variant: windows);

    testWidgets('moves the window when dragged by its blank part', (
      tester,
    ) async {
      await pump(tester);
      final drag = await tester.startGesture(
        blank,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(10, 0));
      await drag.up();
      expect(control.startDraggingCalls, 1);
    }, variant: windows);

    testWidgets('maximizes on a double click as slow as Windows allows, and '
        'not on two separate clicks', (tester) async {
      await pump(tester);
      Future<void> click(Duration at) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.down(blank, timeStamp: at);
        await mouse.up(timeStamp: at);
      }

      await click(Duration.zero);
      await click(const Duration(milliseconds: 450));
      expect(control.toggleMaximizeCalls, 1);

      await click(const Duration(seconds: 2));
      await click(const Duration(seconds: 3));
      expect(control.toggleMaximizeCalls, 1);
    }, variant: windows);

    testWidgets('opens the system menu on a right click', (tester) async {
      await pump(tester);
      final right = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.down(blank);
      await right.up();
      expect(control.showSystemMenuCalls, 1);
    }, variant: windows);
  });

  testWidgets('the window buttons are only there on Windows', (tester) async {
    await pumpAlistenApp(tester);
    expect(
      find.byKey(const ValueKey('window-close')),
      defaultTargetPlatform == TargetPlatform.windows
          ? findsOneWidget
          : findsNothing,
    );
  }, variant: TargetPlatformVariant.desktop());
}
