import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/aurora_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _cover = ColorScheme.fromSeed(
  seedColor: const Color(0xFF2E9E48),
  brightness: Brightness.dark,
  dynamicSchemeVariant: AlistenColors.schemeVariant,
);

void main() {
  const second = Duration(seconds: 1);

  Widget aurora({
    bool disableAnimations = false,
    bool tickers = true,
    GlobalKey<NavigatorState>? navigator,
    ColorScheme? scheme,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        navigatorKey: navigator,
        theme: buildAlistenTheme(scheme ?? _cover),
        home: TickerMode(enabled: tickers, child: const AuroraBackground()),
      ),
    );
  }

  testWidgets('the aurora drifts at about 30 frames a second', (tester) async {
    await tester.pumpWidget(aurora());
    expect(await _framesIn(tester, second), inInclusiveRange(25, 31));
  });

  testWidgets('an aurora without colour, as in a room with no cover, draws '
      'no frames: its drift cannot be seen', (tester) async {
    await tester.pumpWidget(
      aurora(scheme: AlistenColors.brandScheme(Brightness.dark)),
    );
    expect(await _framesIn(tester, second), 0);
  });

  testWidgets('a loop of the aurora takes 24 seconds', (tester) async {
    await tester.pumpWidget(aurora());
    final start = _lights(tester);

    await tester.pump(AlistenDurations.auroraLoop ~/ 4);
    expect(_farthestMove(start, _lights(tester)), greaterThan(100));

    await tester.pump(AlistenDurations.auroraLoop * 3 ~/ 4);
    expect(_farthestMove(start, _lights(tester)), lessThan(2));
  });

  testWidgets('the aurora stands still when the system removes animations', (
    tester,
  ) async {
    await tester.pumpWidget(aurora(disableAnimations: true));
    expect(await _framesIn(tester, second), 0);

    await tester.pumpWidget(aurora());
    expect(await _framesIn(tester, second), greaterThan(0));
  });

  testWidgets('the aurora stands still while tickers are off', (tester) async {
    await tester.pumpWidget(aurora(tickers: false));
    expect(await _framesIn(tester, second), 0);
  });

  testWidgets('the aurora stands still while another page is above it', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(aurora(navigator: navigator));

    // 上层页面透明，极光仍在绘制，只是所在路由已不是当前路由。
    unawaited(
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(second);
    expect(await _framesIn(tester, second), 0);

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(second);
    expect(await _framesIn(tester, second), greaterThan(0));
  });

  testWidgets('the aurora stands still while the keyboard is up, and goes on '
      'from where it stood once it is down', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(aurora());
    await tester.pump(AlistenDurations.auroraLoop ~/ 4);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final before = _lights(tester);
    expect(await _framesIn(tester, second), 0);
    await tester.pump(AlistenDurations.auroraLoop ~/ 4);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 键盘显示期间的时间不计入，极光从停下的位置继续。
    expect(
      _farthestMove(before, _lights(tester)),
      allOf(greaterThan(0), lessThan(20)),
    );
  });

  testWidgets('back from the background, the aurora goes on from where it '
      'stood', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(aurora());
    await tester.pump(AlistenDurations.auroraLoop ~/ 4);
    final before = _lights(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(AlistenDurations.auroraLoop ~/ 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));

    // 后台期间的时间不计入，极光从停下的位置继续，不会跳过一大段。
    expect(_farthestMove(before, _lights(tester)), lessThan(20));
  });
}

// 以 120 Hz 屏幕的节奏推进时间，统计其间实际画出的帧。
Future<int> _framesIn(WidgetTester tester, Duration span) async {
  // 先画掉已排定的帧，例如 MaterialApp 首帧之后自行补的一帧。
  await tester.pump();
  const vsync = Duration(microseconds: 8333);
  var frames = 0;
  var counting = true;
  void count(Duration _) {
    if (!counting) return;
    frames++;
    tester.binding.addPostFrameCallback(count);
  }

  tester.binding.addPostFrameCallback(count);
  for (var elapsed = Duration.zero; elapsed < span; elapsed += vsync) {
    await tester.pump(vsync);
  }
  counting = false;
  return frames;
}

List<Offset> _lights(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  tester
      .renderObject(
        find.descendant(
          of: find.byType(AuroraBackground),
          matching: find.byType(CustomPaint),
        ),
      )
      .paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return [
    for (final call in canvas.invocations)
      if (call.invocation.memberName == #drawCircle)
        call.invocation.positionalArguments.first as Offset,
  ];
}

double _farthestMove(List<Offset> from, List<Offset> to) {
  expect(to, hasLength(from.length));
  return [
    for (var light = 0; light < from.length; light++)
      (to[light] - from[light]).distance,
  ].reduce(math.max);
}
