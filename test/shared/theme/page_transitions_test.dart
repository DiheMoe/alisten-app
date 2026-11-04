import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _below = Key('below');
const _above = Key('above');
const _top = Key('top');

Widget _page(Key key) => SizedBox.expand(key: key);

Future<GlobalKey<NavigatorState>> _app(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        navigatorKey: navigator,
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: _page(_below),
      ),
    ),
  );
  return navigator;
}

void _push(
  GlobalKey<NavigatorState> navigator,
  Key key, {
  bool fullscreenDialog = false,
}) {
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => _page(key),
        fullscreenDialog: fullscreenDialog,
      ),
    ),
  );
}

Offset _at(WidgetTester tester, Key key) {
  return tester.getTopLeft(find.byKey(key, skipOffstage: false));
}

const _midway = Duration(milliseconds: 120);

void main() {
  testWidgets('a new page slides in from the right over a page that recedes '
      'to the left', (tester) async {
    final navigator = await _app(tester);

    _push(navigator, _above);
    await tester.pump();
    await tester.pump(_midway);

    expect(_at(tester, _above).dx, inExclusiveRange(0, 800));
    expect(_at(tester, _above).dy, 0);
    expect(_at(tester, _below).dx, inExclusiveRange(-0.25 * 800, 0));

    await tester.pump(const Duration(milliseconds: 240));
    expect(_at(tester, _above), Offset.zero);
    expect(_at(tester, _below).dx, closeTo(-0.25 * 800, 0.01));
  });

  testWidgets('the page beneath dims while it is covered, and clears after', (
    tester,
  ) async {
    final navigator = await _app(tester);
    double dim() {
      return tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.ancestor(
                of: find.byKey(_below, skipOffstage: false),
                matching: find.byType(Stack, skipOffstage: false),
              ),
              matching: find.byType(FadeTransition, skipOffstage: false),
            ),
          )
          .opacity
          .value;
    }

    expect(dim(), 0);
    _push(navigator, _above);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    expect(dim(), greaterThan(0));

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 310));
    expect(dim(), 0);
  });

  testWidgets('a page leaves to the right, faster than it came', (
    tester,
  ) async {
    final navigator = await _app(tester);
    _push(navigator, _above);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(_midway);
    expect(_at(tester, _above).dx, inExclusiveRange(0, 800));
    expect(_at(tester, _below).dx, inExclusiveRange(-0.25 * 800, 0));

    await tester.pump(const Duration(milliseconds: 190));
    expect(find.byKey(_above), findsNothing);
    expect(_at(tester, _below), Offset.zero);
  });

  testWidgets('a task page rises from the bottom over a page that stays', (
    tester,
  ) async {
    final navigator = await _app(tester);

    _push(navigator, _above, fullscreenDialog: true);
    await tester.pump();
    await tester.pump(_midway);

    expect(_at(tester, _above).dx, 0);
    expect(_at(tester, _above).dy, inExclusiveRange(0, 600));
    expect(_at(tester, _below), Offset.zero);

    await tester.pump(const Duration(milliseconds: 240));
    expect(_at(tester, _above), Offset.zero);
    expect(_at(tester, _below), Offset.zero);
  });

  testWidgets('a task page sinks back to the bottom', (tester) async {
    final navigator = await _app(tester);
    _push(navigator, _above, fullscreenDialog: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(_midway);

    expect(_at(tester, _above).dx, 0);
    expect(_at(tester, _above).dy, inExclusiveRange(0, 600));
  });

  testWidgets('a page opened from a task page pushes it aside like any other', (
    tester,
  ) async {
    final navigator = await _app(tester);
    _push(navigator, _above, fullscreenDialog: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));

    _push(navigator, _top);
    await tester.pump();
    await tester.pump(_midway);

    expect(_at(tester, _top).dx, inExclusiveRange(0, 800));
    expect(_at(tester, _above).dx, lessThan(0));
    expect(_at(tester, _above).dy, 0);
  });

  testWidgets('without animations pages change at once', (tester) async {
    final navigator = await _app(tester, disableAnimations: true);

    _push(navigator, _above);
    await tester.pump();
    await tester.pump();

    expect(_at(tester, _above), Offset.zero);
    expect(_at(tester, _below), Offset.zero);
  });

  test('pages enter in 350 ms and leave in 300 ms', () {
    const builder = AlistenPageTransitionsBuilder();

    expect(builder.transitionDuration, const Duration(milliseconds: 350));
    expect(
      builder.reverseTransitionDuration,
      const Duration(milliseconds: 300),
    );
  });
}
