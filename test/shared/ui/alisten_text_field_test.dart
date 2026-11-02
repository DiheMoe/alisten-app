import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> copied;

  setUp(() => copied = []);

  Future<TextEditingController> pump(
    WidgetTester tester, {
    required bool sensitive,
  }) async {
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          case 'Clipboard.hasStrings':
            return {'value': true};
          case 'Clipboard.getData':
            return {'text': 'pasted'};
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: Material(
          type: MaterialType.transparency,
          child: Center(
            child: AlistenTextField(
              controller: controller,
              hint: 'cookies',
              maxLines: 8,
              sensitive: sensitive,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'SID=secret one');
    await tester.pump();
    return controller;
  }

  Future<void> selectAll(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    await tester.pump();
  }

  // 长按开头的词，使菜单出现时有选中的文字。
  Future<void> longPressText(WidgetTester tester) async {
    await tester.longPressAt(
      tester.getTopLeft(find.byType(EditableText)) + const Offset(6, 10),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressWithControl(
    WidgetTester tester,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('a sensitive field offers only paste and select all in its '
      'menu', (tester) async {
    final controller = await pump(tester, sensitive: true);

    await longPressText(tester);

    expect(controller.selection.isCollapsed, isFalse);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('an ordinary field keeps the whole menu', (tester) async {
    final controller = await pump(tester, sensitive: false);

    await longPressText(tester);

    expect(controller.selection.isCollapsed, isFalse);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets('copy and cut keys do not take text out of a sensitive '
      'field', (tester) async {
    final controller = await pump(tester, sensitive: true);
    await selectAll(tester, controller);

    await pressWithControl(tester, LogicalKeyboardKey.keyC);
    await pressWithControl(tester, LogicalKeyboardKey.keyX);

    expect(copied, isEmpty);
    expect(controller.text, 'SID=secret one');
  });

  testWidgets('copy keys still copy from an ordinary field', (tester) async {
    final controller = await pump(tester, sensitive: false);
    await selectAll(tester, controller);

    await pressWithControl(tester, LogicalKeyboardKey.keyC);

    expect(copied, ['SID=secret one']);
  });

  testWidgets('pasting into a sensitive field still works', (tester) async {
    final controller = await pump(tester, sensitive: true);
    controller.clear();
    await tester.pump();

    await pressWithControl(tester, LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();

    expect(controller.text, 'pasted');
  });

  testWidgets('a sensitive field keeps the keyboard from learning, suggesting '
      'or correcting what goes in', (tester) async {
    await pump(tester, sensitive: true);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
  });

  testWidgets('a hint wraps over the lines of a multi-line field instead of '
      'being cut', (tester) async {
    const hint = '粘贴 cookies.txt 的内容，或请求头里 cookie 的值';
    tester.view
      ..physicalSize = const Size(200, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: Material(
          type: MaterialType.transparency,
          child: Center(
            child: AlistenTextField(
              controller: controller,
              hint: hint,
              maxLines: 8,
            ),
          ),
        ),
      ),
    );

    final text = tester.renderObject<RenderParagraph>(find.text(hint));
    expect(text.didExceedMaxLines, isFalse);
  });

  testWidgets('an ordinary field leaves the keyboard as it is', (tester) async {
    await pump(tester, sensitive: false);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.enableIMEPersonalizedLearning, isTrue);
    expect(field.enableSuggestions, isTrue);
    expect(field.autocorrect, isTrue);
  });
}
