import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'pages appear at once when the system removes animations',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            navigatorKey: navigator,
            theme: buildAlistenTheme(
              AlistenColors.brandScheme(Brightness.light),
            ),
            home: const Scaffold(body: Text('first')),
          ),
        ),
      );

      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('second')),
          ),
        ),
      );
      // 新路由的第一帧在屏幕外布局。
      await tester.pump();
      await tester.pump();
      // 时间未推进，路由已在最终位置。
      expect(tester.getTopLeft(find.text('second')), Offset.zero);

      await tester.pumpAndSettle();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // 边缘滑动仍能返回。
        await tester.dragFrom(const Offset(5, 300), const Offset(500, 0));
        await tester.pumpAndSettle();
        expect(find.text('second'), findsNothing);
        expect(find.text('first'), findsOneWidget);
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
