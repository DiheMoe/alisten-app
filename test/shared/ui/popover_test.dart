import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/morph_panel.dart';
import 'package:alisten/shared/ui/popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an open popover offers screen readers a button that closes '
      'it', (tester) async {
    final semantics = tester.ensureSemantics();
    var open = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: StatefulBuilder(
          builder: (context, setState) => Center(
            child: Popover(
              open: open,
              onClose: () => setState(() => open = false),
              content: const Text('音量'),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final close = find.bySemanticsLabel('关闭');
    expect(
      tester.getSemantics(close),
      isSemantics(label: '关闭', isButton: true, hasTapAction: true),
    );

    tester.semantics.tap(find.semantics.byLabel('关闭'));
    await tester.pumpAndSettle();
    expect(open, isFalse);
    expect(find.text('音量'), findsNothing);
    semantics.dispose();
  });

  group('the panel', () {
    late ValueNotifier<bool> open;
    const triggerKey = Key('trigger');
    const contentKey = Key('content');

    Future<void> pumpPopover(
      WidgetTester tester, {
      bool disableAnimations = false,
    }) async {
      open = ValueNotifier(false);
      addTearDown(open.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: disableAnimations,
          ),
          child: MaterialApp(
            theme: buildAlistenTheme(
              AlistenColors.brandScheme(Brightness.dark),
            ),
            home: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: open,
                builder: (context, shown, _) => Popover(
                  open: shown,
                  onClose: () => open.value = false,
                  content: const SizedBox(
                    key: contentKey,
                    width: 200,
                    height: 100,
                    child: Text('音量'),
                  ),
                  child: const SizedBox(key: triggerKey, width: 40, height: 40),
                ),
              ),
            ),
          ),
        ),
      );
    }

    RenderMorphPanel panel(WidgetTester tester) =>
        tester.renderObject(find.byType(MorphPanel));

    Rect shape(WidgetTester tester) {
      final box = panel(tester);
      return MatrixUtils.transformRect(box.getTransformTo(null), box.shape);
    }

    Rect trigger(WidgetTester tester) => tester.getRect(find.byKey(triggerKey));

    double scale(WidgetTester tester) =>
        tester.getRect(find.byKey(contentKey)).width / 200;

    double contentOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(contentKey),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    testWidgets('grows out of its trigger and springs a little past its '
        'size', (tester) async {
      await pumpPopover(tester);

      open.value = true;
      await tester.pump();
      expect(shape(tester), rectMoreOrLessEquals(trigger(tester), epsilon: 1));

      // 液滴阶段外框离开按钮、高度会先变扁，宽度一直在长。
      await tester.pump(const Duration(milliseconds: 50));
      expect(shape(tester).width, inExclusiveRange(40, 216));

      await tester.pump(const Duration(milliseconds: 190));
      expect(scale(tester), greaterThan(1));

      await tester.pumpAndSettle();
      expect(scale(tester), 1);
      expect(contentOpacity(tester), 1);
      // 面板在按钮上方，左边对齐，内边距 8。
      expect(
        tester.getBottomLeft(find.byKey(contentKey)),
        trigger(tester).topLeft + const Offset(8, -8),
      );
    });

    testWidgets('turning solid, it fades in from nothing at the trigger and '
        'never looks darker or lighter than the card it becomes', (
      tester,
    ) async {
      await pumpPopover(tester);
      final colors = AlistenColors.of(tester.element(find.byType(Popover)));
      final tint = colors.raised.withValues(alpha: 0);

      open.value = true;
      await tester.pump();
      expect(panel(tester).fill.a, 0, reason: 'nothing grey on the trigger');
      open.value = false;
      await tester.pumpAndSettle();

      open.value = true;
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        for (final page in [Colors.white, Colors.black]) {
          final from = Color.alphaBlend(tint, page);
          final to = Color.alphaBlend(colors.raised, page);
          final now = Color.alphaBlend(panel(tester).fill, page);
          for (final (a, b, c) in [
            (from.r, to.r, now.r),
            (from.g, to.g, now.g),
            (from.b, to.b, now.b),
          ]) {
            expect(
              c,
              inInclusiveRange(math.min(a, b) - 0.01, math.max(a, b) + 0.01),
            );
          }
        }
      }
    });

    testWidgets('casts no shadow while it is about the size of its trigger, '
        'so nothing grey lingers under the button as it opens or closes', (
      tester,
    ) async {
      await pumpPopover(tester);

      open.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 8));
      expect(panel(tester).shadow?.color.a ?? 0, 0);

      await tester.pumpAndSettle();
      expect(panel(tester).shadow?.color.a ?? 0, greaterThan(0));

      open.value = false;
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (find.byType(MorphPanel).evaluate().isEmpty) break;
        final shape = MatrixUtils.transformRect(
          panel(tester).getTransformTo(null),
          panel(tester).shape,
        );
        if (shape.height < 60) {
          expect(panel(tester).shadow?.color.a ?? 0, 0);
        }
      }
    });

    testWidgets('its corners go from a capsule to a card without a jump', (
      tester,
    ) async {
      await pumpPopover(tester);

      open.value = true;
      await tester.pump();
      expect(panel(tester).radius.topLeft.x, 20);

      // 圆角在 0.07 秒的延迟之后才开始收，逐帧走才能让它跑起来。
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final now = shape(tester);
      final capsule = now.shortestSide / 2;
      final span = capsule - AlistenRadii.md;
      expect(
        panel(tester).radius.topLeft.x,
        inExclusiveRange(AlistenRadii.md + span * 0.2, capsule - span * 0.2),
      );

      await tester.pumpAndSettle();
      expect(panel(tester).radius.topLeft.x, AlistenRadii.md);
    });

    testWidgets('closing hides the content first, shrinks back into the '
        'trigger and fades out within half a second', (tester) async {
      await pumpPopover(tester);
      open.value = true;
      await tester.pumpAndSettle();

      open.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(contentOpacity(tester), 0);

      await tester.pump(const Duration(milliseconds: 200));
      expect(shape(tester), rectMoreOrLessEquals(trigger(tester), epsilon: 6));

      await tester.pump(const Duration(milliseconds: 220));
      expect(find.byType(MorphPanel), findsNothing);
    });

    testWidgets('without animations it appears and goes at once', (
      tester,
    ) async {
      await pumpPopover(tester, disableAnimations: true);

      open.value = true;
      await tester.pump();
      await tester.pump();
      expect(scale(tester), 1);

      open.value = false;
      await tester.pump();
      await tester.pump();
      expect(find.text('音量'), findsNothing);
    });
  });
}
