import 'package:alisten/shared/ui/keyed_sliver_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rowHeight = 50.0;

Future<void> _pumpList(
  WidgetTester tester,
  List<String> items, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        disableAnimations: disableAnimations,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            KeyedSliverList<String>(
              items: items,
              keyOf: (item) => item,
              itemBuilder: (context, item, index) =>
                  _Row(key: ValueKey('row $item'), label: item),
            ),
          ],
        ),
      ),
    ),
  );
}

double _height(WidgetTester tester, String item) => tester
    .getSize(
      find
          .ancestor(
            of: find.byKey(ValueKey('row $item')),
            matching: find.byType(SizeTransition),
          )
          .first,
    )
    .height;

double _top(WidgetTester tester, String item) =>
    tester.getTopLeft(find.byKey(ValueKey('row $item'))).dy;

void main() {
  testWidgets('a new row grows in over 300 ms', (tester) async {
    await _pumpList(tester, ['a', 'b']);

    await _pumpList(tester, ['a', 'new', 'b']);
    await tester.pump();
    expect(_height(tester, 'new'), lessThan(_rowHeight * 0.2));

    await tester.pump(const Duration(milliseconds: 300));
    expect(_height(tester, 'new'), _rowHeight);
    expect(_top(tester, 'b'), _rowHeight * 2);
  });

  testWidgets('a removed row stays while it collapses, then goes', (
    tester,
  ) async {
    await _pumpList(tester, ['a', 'gone', 'b']);

    await _pumpList(tester, ['a', 'b']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('gone'), findsOneWidget);
    expect(_height(tester, 'gone'), inExclusiveRange(0, _rowHeight));

    await tester.pumpAndSettle();
    expect(find.text('gone'), findsNothing);
    expect(_top(tester, 'b'), _rowHeight);
  });

  testWidgets('rows that change places slide from where they were', (
    tester,
  ) async {
    await _pumpList(tester, ['a', 'b', 'c']);

    await _pumpList(tester, ['c', 'b', 'a']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_top(tester, 'c'), inExclusiveRange(0, _rowHeight * 2));
    expect(_top(tester, 'a'), inExclusiveRange(0, _rowHeight * 2));

    await tester.pumpAndSettle();
    expect(_top(tester, 'c'), 0);
    expect(_top(tester, 'a'), _rowHeight * 2);
  });

  testWidgets('more than 50 changes at once land at once', (tester) async {
    await _pumpList(tester, ['a']);

    await _pumpList(tester, ['a', for (var i = 0; i < 51; i++) 'n$i']);
    await tester.pump();
    expect(_height(tester, 'n0'), _rowHeight);
  });

  testWidgets('without animations changes land at once', (tester) async {
    await _pumpList(tester, ['a', 'gone'], disableAnimations: true);

    await _pumpList(tester, ['new', 'a'], disableAnimations: true);
    await tester.pump();

    expect(_height(tester, 'new'), _rowHeight);
    expect(find.text('gone'), findsNothing);
  });

  testWidgets('a row keeps its state when another is added above it', (
    tester,
  ) async {
    await _pumpList(tester, ['a', 'b']);
    await tester.tap(find.byKey(const ValueKey('row b')));
    await tester.pump();
    expect(find.text('b ✓'), findsOneWidget);

    await _pumpList(tester, ['new', 'a', 'b']);
    await tester.pumpAndSettle();

    expect(find.text('b ✓'), findsOneWidget);
  });
}

class _Row extends StatefulWidget {
  const _Row({required this.label, super.key});

  final String label;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _ticked = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _ticked = true),
      child: SizedBox(
        height: _rowHeight,
        child: Text(_ticked ? '${widget.label} ✓' : widget.label),
      ),
    );
  }
}
