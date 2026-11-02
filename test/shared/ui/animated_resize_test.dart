import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/animated_resize.dart';
import 'package:alisten/shared/ui/collapsible.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page(Widget child, {required bool still}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 200, child: child),
      ),
    ),
  );
}

Widget _box(double height) => SizedBox(height: height);

void main() {
  for (final still in [false, true]) {
    testWidgets('a resize ${still ? 'is immediate' : 'eases'} when animations '
        'are ${still ? 'removed' : 'on'}', (tester) async {
      Widget resize(double height) => _page(
        AnimatedResize(
          duration: still ? Duration.zero : AlistenDurations.short,
          child: _box(height),
        ),
        still: still,
      );
      await tester.pumpWidget(resize(40));
      final box = find.byType(AnimatedResize);
      expect(tester.getSize(box).height, 40);

      await tester.pumpWidget(resize(100));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(box).height,
        still ? 100 : allOf(greaterThanOrEqualTo(40), lessThan(100)),
      );
      await tester.pump(AlistenDurations.short);
      expect(tester.getSize(box).height, 100);
    });

    final closing = still
        ? 'opens and closes at once'
        : 'keeps its content while it closes';
    testWidgets('a collapsible $closing when animations are '
        '${still ? 'removed' : 'on'}', (tester) async {
      Widget collapsible({required bool open}) => _page(
        Collapsible(open: open, child: _box(60)),
        still: still,
      );
      await tester.pumpWidget(collapsible(open: false));
      final box = find.byType(Collapsible);
      expect(tester.getSize(box).height, 0);

      await tester.pumpWidget(collapsible(open: true));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(box).height, still ? 60 : lessThan(60));
      await tester.pump(AlistenDurations.short);
      expect(tester.getSize(box).height, 60);

      final content = find.descendant(
        of: box,
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 60,
        ),
      );
      await tester.pumpWidget(collapsible(open: false));
      await tester.pump(AlistenDurations.short ~/ 2);
      expect(tester.takeException(), isNull);
      if (still) {
        expect(tester.getSize(box).height, 0);
        expect(content, findsNothing);
      } else {
        // 收起过程中内容仍在，随高度一同被裁掉，而不是先变成空白再收缩。
        expect(content, findsOneWidget);
        expect(tester.getSize(box).height, allOf(greaterThan(0), lessThan(60)));
      }
      await tester.pump(AlistenDurations.short);
      expect(tester.getSize(box).height, 0);
      expect(content, findsNothing);
    });
  }

  testWidgets('a collapsible opened again while it closes keeps its one '
      'content and grows back from where it was', (tester) async {
    final probe = GlobalKey<_ProbeState>();
    Widget collapsible({required bool open}) => _page(
      Collapsible(
        open: open,
        child: _Probe(key: probe),
      ),
      still: false,
    );
    await tester.pumpWidget(collapsible(open: true));
    final box = find.byType(Collapsible);
    final state = probe.currentState;

    await tester.pumpWidget(collapsible(open: false));
    await tester.pump(AlistenDurations.short ~/ 2);
    final halfway = tester.getSize(box).height;
    expect(halfway, allOf(greaterThan(0), lessThan(_Probe.height)));

    await tester.pumpWidget(collapsible(open: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(_Probe), findsOneWidget);
    expect(probe.currentState, same(state));
    expect(
      tester.getSize(box).height,
      allOf(greaterThan(halfway - 1), lessThan(_Probe.height)),
    );
    await tester.pump(AlistenDurations.short);
    expect(tester.getSize(box).height, _Probe.height);
    expect(probe.currentState, same(state));
  });

  testWidgets('content that is closing takes no taps and no focus', (
    tester,
  ) async {
    final probe = GlobalKey<_ProbeState>();
    Widget collapsible({required bool open}) => _page(
      Collapsible(
        open: open,
        child: _Probe(key: probe),
      ),
      still: false,
    );
    await tester.pumpWidget(collapsible(open: true));
    final focus = probe.currentState!.focus;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.pumpWidget(collapsible(open: false));
    await tester.pump(AlistenDurations.short ~/ 4);
    expect(find.byType(_Probe), findsOneWidget);
    expect(focus.hasFocus, isFalse);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    // 点在尚未裁掉的顶部。
    await tester.tapAt(
      tester.getTopLeft(find.byType(_Probe)) + const Offset(10, 2),
    );
    expect(probe.currentState!.taps, 0);

    await tester.pumpWidget(collapsible(open: true));
    await tester.pump(AlistenDurations.short);
    await tester.tap(find.byType(_Probe));
    expect(probe.currentState!.taps, 1);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  static const height = 60.0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final focus = FocusNode();
  int taps = 0;

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focus,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const SizedBox(width: double.infinity, height: _Probe.height),
      ),
    );
  }
}
