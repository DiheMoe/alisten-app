import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';

void main() {
  testWidgets('the app is shown in Simplified Chinese', (tester) async {
    await pumpAlistenApp(tester);

    final context = tester.element(find.text(emptyLobbyText));
    expect(Localizations.localeOf(context), const Locale('zh', 'CN'));
    expect(MaterialLocalizations.of(context).backButtonTooltip, '返回');
  });

  testWidgets('text is scaled exactly as the system scales it', (tester) async {
    const system = _SystemScaler();
    await pumpAlistenApp(
      tester,
      system: const MediaQueryData(textScaler: system),
    );

    // 不能换成线性或带上限的缩放：Android 14 起大字放大的比例比小字小。
    final context = tester.element(find.text(emptyLobbyText));
    expect(MediaQuery.textScalerOf(context), same(system));
  });
}

// 与 Android 14 起的系统一样，小字放大的比例比大字大。
final class _SystemScaler extends TextScaler {
  const _SystemScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.3 : fontSize * 1.1;

  @override
  double get textScaleFactor => 1.3;
}
