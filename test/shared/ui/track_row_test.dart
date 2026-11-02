import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a row offering only a long press answers it', (tester) async {
    var longPresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
        home: Material(
          child: Center(
            child: TrackRow(
              title: '晴天',
              subtitle: '周杰伦',
              onLongPress: () => longPresses++,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('晴天')),
      isSemantics(isEnabled: true, hasLongPressAction: true),
    );
    await tester.longPress(find.text('晴天'));
    expect(longPresses, 1);
  });
}
