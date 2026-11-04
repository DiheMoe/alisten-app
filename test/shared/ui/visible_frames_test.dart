import 'package:alisten/shared/ui/visible_frames.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe>
    with WidgetsBindingObserver, VisibleFrames {
  int changes = 0;

  @override
  void visibleFramesChanged() => changes++;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('a page on screen with nothing in the way may animate', (
    tester,
  ) async {
    final probe = GlobalKey<_ProbeState>();
    await tester.pumpWidget(MaterialApp(home: _Probe(key: probe)));

    expect(probe.currentState!.onScreen, isTrue);
    expect(probe.currentState!.keyboardUp, isFalse);
    expect(probe.currentState!.animationsRemoved, isFalse);
  });

  testWidgets('the keyboard is seen where MediaQuery hides it', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    final probe = GlobalKey<_ProbeState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // 两栏布局的左栏就是这样看不到键盘的。
          builder: (context) => MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: _Probe(key: probe),
          ),
        ),
      ),
    );
    final before = probe.currentState!.changes;

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    expect(probe.currentState!.keyboardUp, isTrue);
    expect(probe.currentState!.changes, before + 1);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    expect(probe.currentState!.keyboardUp, isFalse);
  });

  testWidgets('tickers off means off screen', (tester) async {
    final probe = GlobalKey<_ProbeState>();
    await tester.pumpWidget(
      TickerMode(
        enabled: false,
        child: MaterialApp(home: _Probe(key: probe)),
      ),
    );

    expect(probe.currentState!.onScreen, isFalse);
  });

  testWidgets('a page below another route is off screen', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final probe = GlobalKey<_ProbeState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: _Probe(key: probe),
      ),
    );

    final route = PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final pushed = navigator.currentState!.push(route);
    await tester.pump();

    expect(probe.currentState!.onScreen, isFalse);
    navigator.currentState!.pop();
    await pushed;
  });

  testWidgets('leaving the foreground stops it, and coming back resumes', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final probe = GlobalKey<_ProbeState>();
    await tester.pumpWidget(MaterialApp(home: _Probe(key: probe)));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(probe.currentState!.onScreen, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(probe.currentState!.onScreen, isTrue);
  });

  testWidgets('removed animations are reported', (tester) async {
    final probe = GlobalKey<_ProbeState>();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: _Probe(key: probe)),
      ),
    );

    expect(probe.currentState!.animationsRemoved, isTrue);
  });
}
