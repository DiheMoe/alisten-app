import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext pageContext;

  Future<void> pumpPage(WidgetTester tester, {double textScale = 1}) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const ColoredBox(color: Colors.transparent);
          },
        ),
      ),
    );
  }

  Future<void> systemBack() {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.navigation.name,
          const JSONMessageCodec().encodeMessage(<String, Object?>{
            'method': 'popRoute',
          }),
          (_) {},
        );
  }

  testWidgets('a sheet that may not be dismissed ignores the scrim and back', (
    tester,
  ) async {
    await pumpPage(tester);
    Object? result = 'pending';
    unawaited(
      showSheetPanel<String>(
        pageContext,
        dismissible: false,
        builder: (_) => const Text('提交中'),
      ).then((value) => result = value),
    );
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsOneWidget);

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsOneWidget);

    await systemBack();
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsOneWidget);
    expect(result, 'pending');

    Navigator.of(tester.element(find.text('提交中'))).pop('done');
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsNothing);
    expect(result, 'done');
  });

  testWidgets('content that refuses to close, such as a form being '
      'submitted, keeps the sheet against the scrim, back and its handle', (
    tester,
  ) async {
    await pumpPage(tester);
    final submitting = ValueNotifier(true);
    addTearDown(submitting.dispose);
    unawaited(
      showSheetPanel<void>(
        pageContext,
        builder: (_) => ValueListenableBuilder(
          valueListenable: submitting,
          builder: (context, busy, _) => PopScope(
            canPop: !busy,
            child: const SizedBox(height: 160, child: Text('表单')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = find.bySemanticsLabel(
      const DefaultMaterialLocalizations().closeButtonLabel,
    );

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    await systemBack();
    await tester.pumpAndSettle();
    await tester.timedDrag(
      handle,
      const Offset(0, 400),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('表单'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('表单')).dy,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
      reason: 'the sheet does not stay dragged away',
    );

    submitting.value = false;
    await tester.pump();
    await tester.timedDrag(
      handle,
      const Offset(0, 400),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('表单'), findsNothing);
  });

  testWidgets('content that refuses to close is asked when its handle is '
      'dragged far enough, and the sheet stays where it is', (tester) async {
    await pumpPage(tester);
    var asked = 0;
    unawaited(
      showSheetPanel<void>(
        pageContext,
        builder: (_) => PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) asked++;
          },
          child: const SizedBox(height: 160, child: Text('新 Key')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = find.bySemanticsLabel(
      const DefaultMaterialLocalizations().closeButtonLabel,
    );
    final top = tester.getTopLeft(find.text('新 Key')).dy;

    await tester.timedDrag(
      handle,
      const Offset(0, 20),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(asked, 0);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(tester.getTopLeft(find.text('新 Key')).dy, top);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(find.text('新 Key'), findsOneWidget);
    expect(tester.getTopLeft(find.text('新 Key')).dy, top);
  });

  testWidgets('a dismissible sheet closes from the scrim', (tester) async {
    await pumpPage(tester);
    unawaited(
      showSheetPanel<void>(pageContext, builder: (_) => const Text('内容')),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text('内容'), findsNothing);
  });

  testWidgets('tall content scrolls at 200 percent text without overflow', (
    tester,
  ) async {
    await pumpPage(tester, textScale: 2);
    unawaited(
      showSheetPanel<void>(
        pageContext,
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (var line = 0; line < 40; line++) Text('第 $line 行')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final last = find.text('第 39 行');
    expect(last.hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      last,
      300,
      scrollable: find.descendant(
        of: find.byType(SheetPanel),
        matching: find.byType(Scrollable),
      ),
    );
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a short sheet closes once dragged down 30 percent of its own height',
    (tester) async {
      await pumpPage(tester);
      unawaited(
        showSheetPanel<void>(
          pageContext,
          builder: (_) => const SizedBox(height: 160, child: Text('短弹层')),
        ),
      );
      await tester.pumpAndSettle();
      final card = find
          .descendant(
            of: find.byType(SheetPanel),
            matching: find.byType(Material),
          )
          .first;
      final height = tester.getSize(card).height;
      final handle = find.bySemanticsLabel(
        const DefaultMaterialLocalizations().closeButtonLabel,
      );
      expect(tester.getSize(handle).height, greaterThanOrEqualTo(48));

      // 慢速拖动，只让距离起作用；最初在触摸容差内的一段拖动不会移动面板。
      await tester.timedDrag(
        handle,
        Offset(0, height * 0.2),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('短弹层'), findsOneWidget);

      await tester.timedDrag(
        handle,
        Offset(0, height * 0.3 + 2 * kTouchSlop),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('短弹层'), findsNothing);
    },
  );
}
