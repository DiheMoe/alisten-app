import 'package:alisten/shared/ui/cover_flight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const song = SizedBox.square(
    dimension: 52,
    child: ColoredBox(color: Color(0xFFCC3344)),
  );
  const queued = SizedBox.square(
    dimension: 52,
    child: ColoredBox(color: Color(0xFF3344CC)),
  );

  Future<void> pump(
    WidgetTester tester, {
    bool area = true,
    bool entry = true,
    double entryTop = 100,
    bool reduced = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Stack(
            children: [
              const Positioned(
                left: 20,
                top: 300,
                child: FlightMark(tag: 'song', child: song),
              ),
              if (area)
                Positioned(
                  left: 400,
                  top: 50,
                  width: 300,
                  height: 300,
                  child: FlightMark(
                    tag: 'queue',
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        maxHeight: 1000,
                        child: Stack(
                          children: [
                            if (entry)
                              Positioned(
                                left: 10,
                                top: entryTop,
                                child: const FlightMark(
                                  tag: 'entry',
                                  child: queued,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void fly() => FlightMark.fly(from: 'song', to: 'entry', area: 'queue');

  Finder flying() => find.byWidget(song);

  double shownOf(WidgetTester tester, Finder what) => tester
      .widget<Opacity>(
        find.ancestor(of: what, matching: find.byType(Opacity)).first,
      )
      .opacity;

  testWidgets('a copy of the song flies to where it landed in the queue, '
      'which stays empty until it arrives', (tester) async {
    await pump(tester);
    final from = tester.getRect(flying());
    final to = tester.getRect(find.byWidget(queued));

    fly();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(flying(), findsNWidgets(2));
    final midway = tester.getRect(flying().last).center;
    expect(midway.dx, greaterThan(from.center.dx));
    expect(midway.dx, lessThan(to.center.dx));
    expect(tester.getRect(flying().first), from);
    expect(shownOf(tester, find.byWidget(queued)), 0);

    await tester.pumpAndSettle();
    expect(flying(), findsOneWidget);
    expect(shownOf(tester, find.byWidget(queued)), 1);
  });

  testWidgets('it waits a few frames for the queue to show the new song', (
    tester,
  ) async {
    await pump(tester, entry: false);
    fly();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await pump(tester);
    final to = tester.getRect(find.byWidget(queued));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 380));
    expect(flying(), findsNWidgets(2));
    expect(
      (tester.getRect(flying().last).center - to.center).distance,
      lessThan(20),
    );
    await tester.pumpAndSettle();
    expect(flying(), findsOneWidget);
  });

  testWidgets('a song that landed below what the queue shows drops into its '
      'lower edge and fades', (tester) async {
    await pump(tester, entryTop: 600);
    final area = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is FlightMark && widget.tag == 'queue',
      ),
    );
    fly();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(flying(), findsNWidgets(2));
    final late = tester.getRect(flying().last);
    expect(late.bottom, lessThanOrEqualTo(area.bottom + 1));
    expect(late.top, greaterThan(area.center.dy));
    expect(shownOf(tester, flying().last), lessThan(1));
    await tester.pumpAndSettle();
    expect(flying(), findsOneWidget);
    expect(shownOf(tester, find.byWidget(queued)), 1);
  });

  testWidgets('nothing flies when the queue is not on screen', (tester) async {
    await pump(tester, area: false);
    fly();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(flying(), findsOneWidget);
  });

  testWidgets('nothing flies when the queue is folded away out of sight', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 20,
              top: 300,
              child: FlightMark(tag: 'song', child: song),
            ),
            Positioned(
              left: 400,
              top: 50,
              width: 0,
              height: 300,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 300,
                  maxWidth: 300,
                  child: FlightMark(
                    tag: 'queue',
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FlightMark(tag: 'entry', child: queued),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    fly();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(flying(), findsOneWidget);
    expect(shownOf(tester, find.byWidget(queued)), 1);
  });

  testWidgets('nothing flies when motion is reduced', (tester) async {
    await pump(tester, reduced: true);
    fly();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(flying(), findsOneWidget);
    expect(shownOf(tester, find.byWidget(queued)), 1);
  });
}
