import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
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
}
