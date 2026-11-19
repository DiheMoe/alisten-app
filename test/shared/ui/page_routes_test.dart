import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/ui/page_routes.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/tap_origin.dart';
import 'package:alisten/shared/ui/zoom_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _a = Key('a');
const _b = Key('b');
const _t = Key('t');
const _p = Key('p');
const _width = 800.0;
const _openPage = Key('open page');
const _openTask = Key('open task');
const _openTaskHigh = Key('open task high');
const _openPush = Key('open push');
const _openSmall = Key('open small');

Widget _filled(Key key, [Widget? child]) => ColoredBox(
  key: key,
  color: Colors.black,
  child: child ?? const SizedBox.expand(),
);

Future<GoRouter> _app(
  WidgetTester tester, {
  bool disableAnimations = false,
  Widget Function()? second,
  Widget Function()? task,
  ValueListenable<bool>? cardShown,
}) async {
  late final GoRouter router;
  Widget button(Key key, String to) => Pressable(
    key: key,
    focusRadius: const BorderRadius.all(Radius.circular(12)),
    onPressed: () => router.go(to),
    child: const SizedBox(width: 60, height: 40),
  );
  router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (_, state) => AlistenPage<void>(
          key: state.pageKey,
          child: _filled(
            _a,
            Stack(
              children: [
                // 入口卡片：页面从它长出。
                Positioned(
                  right: 20,
                  top: 40,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: cardShown ?? ValueNotifier(true),
                    builder: (context, shown, _) => shown
                        ? ZoomSource(
                            child: Pressable(
                              key: _openPage,
                              focusRadius: const BorderRadius.all(
                                Radius.circular(12),
                              ),
                              onPressed: () => router.go('/b'),
                              child: const ColoredBox(
                                color: Colors.white,
                                child: SizedBox(width: 160, height: 80),
                              ),
                            ),
                          )
                        : const SizedBox(width: 160, height: 80),
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 160,
                  child: button(_openSmall, '/b'),
                ),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: button(_openTask, '/t'),
                ),
                Positioned(
                  left: 20,
                  top: 40,
                  child: button(_openTaskHigh, '/t'),
                ),
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: button(_openPush, '/p'),
                ),
              ],
            ),
          ),
        ),
        routes: [
          GoRoute(
            path: 'b',
            pageBuilder: (_, state) => AlistenPage<void>(
              key: state.pageKey,
              child: second?.call() ?? _filled(_b),
            ),
          ),
          GoRoute(
            path: 't',
            pageBuilder: (_, state) => AlistenPage<void>(
              key: state.pageKey,
              task: true,
              child: task?.call() ?? _filled(_t),
            ),
          ),
          GoRoute(
            path: 'p',
            pageBuilder: (_, state) => AlistenPage<void>(
              key: state.pageKey,
              push: true,
              child: _filled(_p),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(_width, 600),
        disableAnimations: disableAnimations,
      ),
      child: MaterialApp.router(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        routerConfig: router,
      ),
    ),
  );
  return router;
}

double _left(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key, skipOffstage: false)).dx;

RenderZoomFrame _frame(WidgetTester tester, Key key) => tester.renderObject(
  find
      .ancestor(
        of: find.byKey(key, skipOffstage: false),
        matching: find.byType(ZoomFrame),
      )
      .first,
);

/// 外框在屏幕上的位置。
Rect _shape(WidgetTester tester, Key key) {
  final frame = _frame(tester, key);
  return MatrixUtils.transformRect(frame.getTransformTo(null), frame.shape);
}

Rect _button(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

// 入口卡片画出来的东西；飞行期间它什么都不画。
RenderObject _card(WidgetTester tester) =>
    tester.renderObject(find.byType(ZoomSource));

Route<dynamic>? _routeOf(WidgetTester tester, Key key) =>
    ModalRoute.of(tester.element(find.byKey(key, skipOffstage: false)));

Future<void> _open(WidgetTester tester, GoRouter router) async {
  await tester.tap(find.byKey(_openPage));
  await tester.pumpAndSettle();
}

Future<void> _drag(
  WidgetTester tester,
  double distance, {
  Offset from = const Offset(300, 300),
  double speed = 200,
}) async {
  final gesture = await tester.startGesture(from);
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(distance / steps, 0));
    await tester.pump(
      Duration(microseconds: (distance / steps / speed * 1e6).round()),
    );
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  tearDown(TapOrigin.reset);

  group('a drag back', () {
    test('pops when the distance and the speed carried on reach 0.4665', () {
      expect(dragBackPops(fraction: 0.47, velocity: 0), isTrue);
      expect(dragBackPops(fraction: 0.3, velocity: 0), isFalse);
      expect(dragBackPops(fraction: 0.3, velocity: 0.5), isTrue);
      expect(dragBackPops(fraction: 0.5, velocity: -2), isFalse);
    });

    test('lets a flick past 1.5 widths a second speed up to 4.25 times', () {
      expect(dragBackReleaseVelocity(1), 1);
      expect(dragBackReleaseVelocity(3), closeTo(12.75, 1e-9));
      expect(dragBackReleaseVelocity(-3), closeTo(-12.75, 1e-9));
    });
  });

  testWidgets('a page grows out of the card that opened it, showing the '
      'card at first and itself as it grows, and settles full screen, '
      'unclipped, over a page that stays and darkens; the card is not drawn '
      'while the page flies', (tester) async {
    await _app(tester);
    final button = _button(tester, _openPage);
    expect(_card(tester), paints..rect());

    await tester.tap(find.byKey(_openPage));
    await tester.pump();
    await tester.pump();
    expect(_shape(tester, _b), rectMoreOrLessEquals(button, epsilon: 1));
    expect(_frame(tester, _b).picture, isNotNull);
    expect(_frame(tester, _b).pictured, closeTo(1, 0.05));
    expect(_card(tester), paintsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    final growing = _shape(tester, _b);
    expect(growing.width, inExclusiveRange(button.width, _width));
    expect(_frame(tester, _b).pictured, lessThan(1));
    expect(_left(tester, _a), 0);

    await tester.pumpAndSettle();
    expect(_shape(tester, _b), const Offset(0, 0) & const Size(_width, 600));
    expect(_frame(tester, _b).atRest, isTrue);
    expect(_left(tester, _a), 0);
    expect(_dim(tester), closeTo(AlistenMotion.coveredDim, 1e-6));
  });

  testWidgets('closing shrinks it back into its card, the card\'s picture '
      'coming back as it lands, and the card is drawn again', (tester) async {
    final router = await _app(tester);
    final button = _button(tester, _openPage);
    await tester.tap(find.byKey(_openPage));
    await tester.pumpAndSettle();

    router.go('/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final shrinking = _shape(tester, _b);
    expect(shrinking.width, lessThan(_width / 2));
    expect((shrinking.center - button.center).distance, lessThan(120));
    expect(_frame(tester, _b).pictured, greaterThan(0));
    expect(_card(tester), paintsNothing);

    await tester.pumpAndSettle();
    expect(find.byKey(_b), findsNothing);
    expect(_card(tester), paints..rect());
  });

  testWidgets('a card no longer on screen: the page slides out to the right '
      'instead of shrinking somewhere', (tester) async {
    final cardShown = ValueNotifier(true);
    addTearDown(cardShown.dispose);
    final router = await _app(tester, cardShown: cardShown);
    await tester.tap(find.byKey(_openPage));
    await tester.pumpAndSettle();
    cardShown.value = false;
    await tester.pump();

    router.go('/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final leaving = _shape(tester, _b);
    expect(leaving.width, closeTo(_width, 0.5));
    expect(leaving.left, inExclusiveRange(0, _width));

    await tester.pumpAndSettle();
    expect(find.byKey(_b), findsNothing);
  });

  testWidgets('a page opened without a tap, or from a small button outside '
      'any card, is pushed in instead', (tester) async {
    final router = await _app(tester);

    router.go('/b');
    await tester.pumpAndSettle();
    expect(_routeOf(tester, _b), isA<PushPageRoute<dynamic>>());

    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_openSmall));
    await tester.pumpAndSettle();
    expect(_routeOf(tester, _b), isA<PushPageRoute<dynamic>>());

    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_openPage));
    await tester.pumpAndSettle();
    expect(_routeOf(tester, _b), isA<ZoomPageRoute<dynamic>>());
  });

  testWidgets('a drag past the middle takes the page back, a short slow one '
      'returns it, a short flick takes it back', (tester) async {
    final router = await _app(tester);

    await _open(tester, router);
    await _drag(tester, _width * 0.6);
    expect(find.byKey(_b), findsNothing);
    expect(_left(tester, _a), 0);

    await _open(tester, router);
    await _drag(tester, _width * 0.2);
    expect(find.byKey(_b), findsOneWidget);
    expect(_frame(tester, _b).atRest, isTrue);

    await tester.fling(find.byKey(_b), const Offset(_width * 0.2, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.byKey(_b), findsNothing);
  });

  testWidgets('a page dragged away is gone for the router too, and does not '
      'come back with the next page', (tester) async {
    final router = await _app(tester);
    await _open(tester, router);

    await _drag(tester, _width * 0.6);
    expect(router.state.uri.path, '/');

    router.go('/t');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_b, skipOffstage: false), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('dragged right and down the page follows the finger both ways '
      'one to one and shrinks, with the page below in sight; let go early it '
      'settles back', (tester) async {
    final router = await _app(tester);
    await _open(tester, router);

    final gesture = await tester.startGesture(const Offset(300, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 第二步越过 30 的起拖距离时开始跟手，之前的移动不计入。
    final frame = _frame(tester, _b);
    expect(frame.offset.dx, closeTo(160, 1));
    expect(frame.offset.dy, closeTo(80, 1));
    expect(
      frame.scale,
      closeTo(
        1 - AlistenMotion.dragShrink * const Offset(160, 80).distance / _width,
        0.01,
      ),
    );
    expect(find.byKey(_a), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_frame(tester, _b).atRest, isTrue);
  });

  testWidgets('a mostly vertical drag is not a drag back', (tester) async {
    final router = await _app(tester);
    await _open(tester, router);

    final gesture = await tester.startGesture(const Offset(300, 200));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(10, 25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_frame(tester, _b).offset, Offset.zero);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the page keeps up with a finger that reports a move every '
      'frame', (tester) async {
    final router = await _app(tester);
    await _open(tester, router);

    // 真机上每帧之间至少有一次移动，跟手的弹簧不能因此每帧从头开始。
    final gesture = await tester.startGesture(const Offset(300, 300));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }

    expect(_frame(tester, _b).offset.dx, closeTo(200, 1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('let go far enough, a dragged page flies back into its '
      'card', (tester) async {
    await _app(tester);
    final button = _button(tester, _openPage);
    await tester.tap(find.byKey(_openPage));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(300, 300));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final flying = _shape(tester, _b);
    expect(flying.width, lessThan(_width / 2));
    expect((flying.center - button.center).distance, lessThan(150));
    await tester.pumpAndSettle();
    expect(find.byKey(_b), findsNothing);
  });

  testWidgets('a page that may not leave stays and is asked', (tester) async {
    final asked = <bool>[];
    final router = await _app(
      tester,
      second: () => PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => asked.add(didPop),
        child: _filled(_b),
      ),
    );
    await _open(tester, router);

    await _drag(tester, _width * 0.6);

    expect(find.byKey(_b), findsOneWidget);
    expect(_frame(tester, _b).atRest, isTrue);
    expect(asked, [false]);
  });

  testWidgets('a horizontal scroll inside the page keeps its drag', (
    tester,
  ) async {
    final router = await _app(
      tester,
      second: () => _filled(
        _b,
        Column(
          children: [
            const SizedBox(height: 200),
            SizedBox(
              height: 200,
              child: PageView(
                children: const [
                  ColoredBox(color: Colors.red),
                  SizedBox(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await _open(tester, router);

    await _drag(tester, _width * 0.6);
    expect(find.byKey(_b), findsOneWidget);

    await _drag(tester, _width * 0.6, from: const Offset(300, 100));
    expect(find.byKey(_b), findsNothing);
  });

  testWidgets('without animations pages change at once, and a drag still '
      'follows the finger', (tester) async {
    await _app(tester, disableAnimations: true);

    await tester.tap(find.byKey(_openPage));
    await tester.pump();
    await tester.pump();
    expect(_frame(tester, _b).atRest, isTrue);

    final gesture = await tester.startGesture(const Offset(300, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    expect(_frame(tester, _b).offset.dx, closeTo(160, 1));
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(_frame(tester, _b).atRest, isTrue);
  });

  group('a pushed page', () {
    Rect page(WidgetTester tester) =>
        tester.getRect(find.byKey(_p, skipOffstage: false));
    const parallax = -0.3 * _width;

    testWidgets('slides in from the right at full size, not out of the button '
        'that opened it, while the page below moves left a little and '
        'darkens; closing slides it back out', (tester) async {
      final router = await _app(tester);

      await tester.tap(find.byKey(_openPush));
      await tester.pump();
      await tester.pump();
      expect(page(tester).size, const Size(_width, 600));
      expect(page(tester).left, closeTo(_width, 1));

      await tester.pump(const Duration(milliseconds: 100));
      expect(page(tester).left, inExclusiveRange(0, _width));
      expect(page(tester).size, const Size(_width, 600));
      expect(_left(tester, _a), inExclusiveRange(parallax, 0));

      await tester.pumpAndSettle();
      expect(page(tester).topLeft, Offset.zero);
      expect(_left(tester, _a), closeTo(parallax, 0.5));
      expect(_dim(tester), closeTo(AlistenMotion.coveredDim, 1e-6));

      router.go('/');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(page(tester).left, inExclusiveRange(0, _width));
      expect(_left(tester, _a), inExclusiveRange(parallax, 0));

      await tester.pumpAndSettle();
      expect(find.byKey(_p), findsNothing);
      expect(_left(tester, _a), 0);
    });

    testWidgets('dragged right it follows the finger one to one with the page '
        'below following along; a short slow drag puts it back, a long one '
        'takes it back', (tester) async {
      final router = await _app(tester);
      router.go('/p');
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(300, 300));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 第二步越过 30 的起拖距离时开始跟手，之前的 40 不计入。
      expect(page(tester).left, closeTo(160, 1));
      expect(_left(tester, _a), closeTo(parallax * (1 - 160 / _width), 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(page(tester).left, 0);

      await _drag(tester, _width * 0.6);
      expect(find.byKey(_p), findsNothing);
      expect(router.state.uri.path, '/');
      expect(_left(tester, _a), 0);
    });

    testWidgets('without animations it is simply there and simply gone', (
      tester,
    ) async {
      final router = await _app(tester, disableAnimations: true);

      router.go('/p');
      await tester.pump();
      await tester.pump();
      expect(page(tester).topLeft, Offset.zero);

      router.go('/');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_p), findsNothing);
      expect(_left(tester, _a), 0);
    });
  });

  group('a task page', () {
    double top(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(_t, skipOffstage: false)).dy;

    Future<void> pull(
      WidgetTester tester,
      double distance, {
      Offset from = const Offset(400, 40),
      double speed = 200,
    }) async {
      final gesture = await tester.startGesture(from);
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

    test('closes when the drag thrown on reaches past half its height', () {
      expect(sheetCloses(drag: 300, velocity: 0, height: 500), isTrue);
      expect(sheetCloses(drag: 200, velocity: 0, height: 500), isFalse);
      expect(sheetCloses(drag: 200, velocity: 600, height: 500), isTrue);
      expect(sheetCloses(drag: 300, velocity: -1000, height: 500), isFalse);
    });

    testWidgets('opened without a tap it rises from the bottom over a page '
        'that stays and darkens, with rounded top corners and the page above '
        'it still in sight', (tester) async {
      final router = await _app(tester);

      router.go('/t');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(top(tester), greaterThan(10));

      await tester.pumpAndSettle();
      expect(top(tester), 10);
      expect(_left(tester, _a), 0);
      expect(find.byType(AnimatedModalBarrier), findsOneWidget);
      expect(
        _frame(tester, _t).radius,
        const BorderRadius.vertical(top: Radius.circular(38)),
      );
      expect(
        find.ancestor(of: find.byKey(_t), matching: find.byType(ZoomFrame)),
        paints..clipRRect(),
      );
      final route = ModalRoute.of(tester.element(find.byKey(_t)))!;
      expect((route as PageRoute<void>).fullscreenDialog, isTrue);
    });

    testWidgets('grows out of the button that opened it and shrinks back '
        'into it', (tester) async {
      final router = await _app(tester);
      final button = _button(tester, _openTask);

      await tester.tap(find.byKey(_openTask));
      await tester.pump();
      await tester.pump();
      expect(_shape(tester, _t), rectMoreOrLessEquals(button, epsilon: 1));
      await tester.pumpAndSettle();
      expect(top(tester), 10);

      router.go('/');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final shrinking = _shape(tester, _t);
      expect(shrinking.width, lessThan(_width / 2));
      expect((shrinking.center - button.center).distance, lessThan(150));
      await tester.pumpAndSettle();
      expect(find.byKey(_t), findsNothing);
    });

    testWidgets('opened by a button in the upper half it rises from the '
        'bottom instead, so pulling it down sends it the way it came', (
      tester,
    ) async {
      await _app(tester);

      await tester.tap(find.byKey(_openTaskHigh));
      await tester.pump();
      await tester.pump();
      expect(_shape(tester, _t).top, greaterThanOrEqualTo(600 - 1));
      await tester.pumpAndSettle();
      expect(top(tester), 10);
    });

    testWidgets('a long pull down closes it, a short slow one puts it back', (
      tester,
    ) async {
      final router = await _app(tester);
      router.go('/t');
      await tester.pumpAndSettle();

      await pull(tester, 120);
      expect(find.byKey(_t), findsOneWidget);
      expect(top(tester), 10);

      await pull(tester, 400);
      expect(find.byKey(_t), findsNothing);
    });

    testWidgets('a pull on a list inside only scrolls the list', (
      tester,
    ) async {
      final router = await _app(
        tester,
        task: () => _filled(
          _t,
          Column(
            children: [
              const SizedBox(height: 80),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 50, child: Text('$i')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      router.go('/t');
      await tester.pumpAndSettle();

      await pull(tester, 400, from: const Offset(400, 300));
      expect(find.byKey(_t), findsOneWidget);
      expect(top(tester), 10);
    });

    testWidgets('a page above it opens as usual and the task page stays '
        'under it', (tester) async {
      final router = await _app(tester);
      router.go('/t');
      await tester.pumpAndSettle();

      router.go('/b');
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_b)), Offset.zero);

      router.go('/t');
      await tester.pumpAndSettle();
      expect(top(tester), 10);
    });

    testWidgets('the page below stops its animations while the task page is '
        'open, and starts them again once it closes', (tester) async {
      final router = await _app(tester);
      expect(
        TickerMode.valuesOf(tester.element(find.byKey(_a))).enabled,
        isTrue,
      );

      router.go('/t');
      await tester.pumpAndSettle();
      expect(
        TickerMode.valuesOf(tester.element(find.byKey(_a, skipOffstage: false)))
            .enabled,
        isFalse,
      );

      router.go('/');
      await tester.pump();
      expect(
        TickerMode.valuesOf(tester.element(find.byKey(_a))).enabled,
        isTrue,
      );
      await tester.pumpAndSettle();
    });
  });
}

/// 页面 a 上叠的黑色有多深。
double _dim(WidgetTester tester) {
  final boxes = find.descendant(
    of: find.ancestor(
      of: find.byKey(_a, skipOffstage: false),
      matching: find.byType(Stack, skipOffstage: false),
    ),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox && widget.color.r == 0 && widget.color.a < 0.5,
      skipOffstage: false,
    ),
  );
  return tester
      .widgetList<ColoredBox>(boxes)
      .fold(
        0.0,
        (deepest, box) => box.color.a > deepest ? box.color.a : deepest,
      );
}
