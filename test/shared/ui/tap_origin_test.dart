import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/tap_origin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _button = Key('button');

Future<void> _pump(WidgetTester tester, VoidCallback onPressed) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: Align(
        alignment: const Alignment(0.5, -0.5),
        child: Pressable(
          key: _button,
          focusRadius: const BorderRadius.all(Radius.circular(12)),
          onPressed: onPressed,
          child: const SizedBox(width: 100, height: 40),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(TapOrigin.reset);

  testWidgets('a tap on a pressable is the origin of what opens next', (
    tester,
  ) async {
    LaunchOrigin? origin;
    await _pump(tester, () => origin = TapOrigin.take());

    await tester.tap(find.byKey(_button));
    await tester.pump();

    expect(origin?.rect, tester.getRect(find.byKey(_button)));
    expect(origin?.radius, 12);
    expect(TapOrigin.take(), isNull);
  });

  testWidgets('an origin older than a second is ignored', (tester) async {
    var now = Duration.zero;
    TapOrigin.now = () => now;
    await _pump(tester, () {});

    await tester.tap(find.byKey(_button));
    now += const Duration(milliseconds: 1001);

    expect(TapOrigin.take(), isNull);
  });

  testWidgets('an origin whose element has left the tree is ignored', (
    tester,
  ) async {
    await _pump(tester, () {});
    await tester.tap(find.byKey(_button));

    await tester.pumpWidget(const SizedBox());

    expect(TapOrigin.take(), isNull);
  });

  testWidgets('an origin follows its element when it moves', (tester) async {
    late StateSetter move;
    var right = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: StatefulBuilder(
          builder: (context, setState) {
            move = setState;
            return Align(
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              child: Pressable(
                key: _button,
                onPressed: () {},
                child: const SizedBox(width: 100, height: 40),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(_button));
    final origin = TapOrigin.take()!;

    move(() => right = true);
    await tester.pump();

    expect(origin.current, tester.getRect(find.byKey(_button)));
    expect(origin.rect, isNot(origin.current));
  });

  testWidgets('a zoom target reports where it is now, and nothing once gone', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ZoomTarget(
            tag: 'room',
            child: SizedBox(key: _button, width: 300, height: 60),
          ),
        ),
      ),
    );

    expect(ZoomTarget.rectOf('room'), tester.getRect(find.byKey(_button)));

    await tester.pumpWidget(const SizedBox());
    expect(ZoomTarget.rectOf('room'), isNull);
  });
}
