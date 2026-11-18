import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/tap_origin.dart';
import 'package:alisten/shared/ui/zoom_frame.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext pageContext;

  Future<void> pumpPage(WidgetTester tester, {double textScale = 1}) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const ColoredBox(color: Colors.transparent);
          },
        ),
      ),
    );
  }

  Future<void> systemBack() {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.navigation.name,
          const JSONMessageCodec().encodeMessage(<String, Object?>{
            'method': 'popRoute',
          }),
          (_) {},
        );
  }

  testWidgets('a sheet that may not be dismissed ignores the scrim and back', (
    tester,
  ) async {
    await pumpPage(tester);
    Object? result = 'pending';
    unawaited(
      showSheetPanel<String>(
        pageContext,
        dismissible: false,
        builder: (_) => const Text('提交中'),
      ).then((value) => result = value),
    );
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsOneWidget);

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsOneWidget);

    await systemBack();
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsOneWidget);
    expect(result, 'pending');

    Navigator.of(tester.element(find.text('提交中'))).pop('done');
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsNothing);
    expect(result, 'done');
  });

  testWidgets('content that refuses to close, such as a form being '
      'submitted, keeps the sheet against the scrim, back and its handle', (
    tester,
  ) async {
    await pumpPage(tester);
    final submitting = ValueNotifier(true);
    addTearDown(submitting.dispose);
    unawaited(
      showSheetPanel<void>(
        pageContext,
        builder: (_) => ValueListenableBuilder(
          valueListenable: submitting,
          builder: (context, busy, _) => PopScope(
            canPop: !busy,
            child: const SizedBox(height: 160, child: Text('表单')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = find.bySemanticsLabel(
      const DefaultMaterialLocalizations().closeButtonLabel,
    );

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    await systemBack();
    await tester.pumpAndSettle();
    await tester.timedDrag(
      handle,
      const Offset(0, 400),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('表单'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('表单')).dy,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
      reason: 'the sheet does not stay dragged away',
    );

    submitting.value = false;
    await tester.pump();
    await tester.timedDrag(
      handle,
      const Offset(0, 400),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('表单'), findsNothing);
  });

  testWidgets('content that refuses to close is asked when its handle is '
      'dragged far enough, and the sheet stays where it is', (tester) async {
    await pumpPage(tester);
    var asked = 0;
    unawaited(
      showSheetPanel<void>(
        pageContext,
        builder: (_) => PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) asked++;
          },
          child: const SizedBox(height: 160, child: Text('新 Key')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = find.bySemanticsLabel(
      const DefaultMaterialLocalizations().closeButtonLabel,
    );
    final top = tester.getTopLeft(find.text('新 Key')).dy;

    await tester.timedDrag(
      handle,
      const Offset(0, 20),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(asked, 0);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(tester.getTopLeft(find.text('新 Key')).dy, top);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(find.text('新 Key'), findsOneWidget);
    expect(tester.getTopLeft(find.text('新 Key')).dy, top);
  });

  testWidgets('a dismissible sheet closes from the scrim', (tester) async {
    await pumpPage(tester);
    unawaited(
      showSheetPanel<void>(pageContext, builder: (_) => const Text('内容')),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text('内容'), findsNothing);
  });

  testWidgets('tall content scrolls at 200 percent text without overflow', (
    tester,
  ) async {
    await pumpPage(tester, textScale: 2);
    unawaited(
      showSheetPanel<void>(
        pageContext,
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (var line = 0; line < 40; line++) Text('第 $line 行')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final last = find.text('第 39 行');
    expect(last.hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      last,
      300,
      scrollable: find.descendant(
        of: find.byType(SheetPanel),
        matching: find.byType(Scrollable),
      ),
    );
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a short sheet closes once a slow drag passes half its own height',
    (tester) async {
      await pumpPage(tester);
      unawaited(
        showSheetPanel<void>(
          pageContext,
          builder: (_) => const SizedBox(height: 160, child: Text('短弹层')),
        ),
      );
      await tester.pumpAndSettle();
      final card = find
          .descendant(
            of: find.byType(SheetPanel),
            matching: find.byType(Material),
          )
          .first;
      final height = tester.getSize(card).height;
      final handle = find.bySemanticsLabel(
        const DefaultMaterialLocalizations().closeButtonLabel,
      );
      expect(tester.getSize(handle).height, greaterThanOrEqualTo(48));

      // 慢速拖动，只让距离起作用。
      await tester.timedDrag(
        handle,
        Offset(0, height * 0.4),
        const Duration(seconds: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('短弹层'), findsOneWidget);

      await tester.timedDrag(
        handle,
        Offset(0, height * 0.5 + 2 * kTouchSlop),
        const Duration(seconds: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('短弹层'), findsNothing);
    },
  );

  group('the sheet moves on a spring and follows the finger', () {
    Finder handle() => find.bySemanticsLabel(
      const DefaultMaterialLocalizations().closeButtonLabel,
    );
    double top(WidgetTester tester) => tester.getTopLeft(find.text('面板内容')).dy;

    Future<void> open(WidgetTester tester) async {
      await pumpPage(tester);
      unawaited(
        showSheetPanel<void>(
          pageContext,
          builder: (_) => const SizedBox(height: 300, child: Text('面板内容')),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> drag(
      WidgetTester tester,
      double distance, {
      double speed = 200,
    }) async {
      final gesture = await tester.startGesture(tester.getCenter(handle()));
      const steps = 20;
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(0, distance / steps));
        await tester.pump(
          Duration(microseconds: (distance / steps / speed * 1e6).round()),
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('it rises most of the way in a tenth of a second and settles', (
      tester,
    ) async {
      await pumpPage(tester);
      unawaited(
        showSheetPanel<void>(
          pageContext,
          builder: (_) => const SizedBox(height: 300, child: Text('面板内容')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final rising = top(tester);
      await tester.pumpAndSettle();
      final rest = top(tester);

      expect(rising, greaterThan(rest));
      expect(rising - rest, lessThan(780 * 0.5));
    });

    testWidgets('a drag moves it with the finger, one to one', (tester) async {
      await open(tester);
      final rest = top(tester);

      final gesture = await tester.startGesture(tester.getCenter(handle()));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(top(tester), closeTo(rest + 200, 1));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a short slow drag puts it back, a long drag closes it', (
      tester,
    ) async {
      await open(tester);
      final rest = top(tester);

      await drag(tester, 120);
      expect(find.text('面板内容'), findsOneWidget);
      expect(top(tester), rest);

      await drag(tester, 300);
      expect(find.text('面板内容'), findsNothing);
    });

    testWidgets('a short flick closes it', (tester) async {
      await open(tester);

      await tester.fling(handle(), const Offset(0, 80), 2000);
      await tester.pumpAndSettle();

      expect(find.text('面板内容'), findsNothing);
    });

    testWidgets('dragged up it stretches a little and comes back', (
      tester,
    ) async {
      await open(tester);
      final rest = top(tester);

      final gesture = await tester.startGesture(tester.getCenter(handle()));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 拉了 300，橡皮筋只让它上移六十来像素。
      expect(rest - top(tester), closeTo(rubberBand(300, 100), 1));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(top(tester), rest);
    });
  });

  group('a sheet opened by a button', () {
    const button = Key('button');

    Future<void> pumpButton(
      WidgetTester tester, {
      required Alignment at,
    }) async {
      await pumpPage(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
          home: Builder(
            builder: (context) => Align(
              alignment: at,
              child: Pressable(
                key: button,
                focusRadius: const BorderRadius.all(Radius.circular(14)),
                onPressed: () => unawaited(
                  showSheetPanel<void>(
                    context,
                    builder: (_) =>
                        const SizedBox(height: 300, child: Text('面板内容')),
                  ),
                ),
                child: const SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      );
    }

    Rect card(WidgetTester tester) {
      final frame = tester.renderObject<RenderZoomFrame>(
        find.ancestor(
          of: find.text('面板内容', skipOffstage: false),
          matching: find.byType(ZoomFrame),
        ),
      );
      return MatrixUtils.transformRect(frame.getTransformTo(null), frame.shape);
    }

    Future<void> pullDown(WidgetTester tester) async {
      final handle = find.bySemanticsLabel(
        const DefaultMaterialLocalizations().closeButtonLabel,
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
    }

    tearDown(TapOrigin.reset);

    testWidgets('in the lower half, the sheet grows out of it and a pull '
        'down shrinks it back in', (tester) async {
      await pumpButton(tester, at: const Alignment(0.6, 0.8));
      final from = tester.getRect(find.byKey(button));

      await tester.tap(find.byKey(button));
      await tester.pump();
      await tester.pump();
      expect(card(tester), rectMoreOrLessEquals(from, epsilon: 1));
      await tester.pumpAndSettle();
      expect(card(tester).width, greaterThan(from.width));

      await pullDown(tester);
      await tester.pump(const Duration(milliseconds: 250));
      final shrinking = card(tester);
      expect(shrinking.width, lessThan(from.width * 3));
      expect((shrinking.center - from.center).distance, lessThan(150));
      await tester.pumpAndSettle();
      expect(find.text('面板内容'), findsNothing);
    });

    testWidgets('in the upper half, the sheet still rises from the bottom and '
        'a pull down drops it down, never up to the button', (tester) async {
      await pumpButton(tester, at: const Alignment(0.6, -0.6));
      const screenHeight = 2340 / 3;

      await tester.tap(find.byKey(button));
      await tester.pump();
      await tester.pump();
      expect(card(tester).top, greaterThanOrEqualTo(screenHeight - 1));
      await tester.pumpAndSettle();
      final rest = card(tester);

      await pullDown(tester);
      var lowest = rest.top;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('面板内容').evaluate().isEmpty) break;
        final now = card(tester).top;
        expect(now, greaterThanOrEqualTo(lowest - 1));
        lowest = now;
      }
      await tester.pumpAndSettle();
      expect(find.text('面板内容'), findsNothing);
    });
  });
}
