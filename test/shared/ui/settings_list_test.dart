import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool alert}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: SettingsGroup(
              children: [
                CategoryRow(
                  icon: AlistenIcons.musicNote,
                  title: '音源',
                  summary: '2 个未登录',
                  alert: alert,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

  Finder dot() => find.byKey(const ValueKey('category-alert'));

  testWidgets('a row that needs attention shows a red dot before its summary '
      'and still reads as its title and summary', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, alert: true);
    expect(dot(), findsOneWidget);
    expect(
      tester.getTopRight(dot()).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.text('2 个未登录')).dx),
    );
    expect(
      find.bySemanticsLabel(RegExp('音源.*2 个未登录', dotAll: true)),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('a pressed row', () {
    BorderRadius shape(WidgetTester tester) =>
        tester.widget<Pressable>(find.byType(Pressable)).focusRadius;

    testWidgets('on a phone is tinted with rounded corners', (tester) async {
      await pump(tester, alert: false);
      expect(shape(tester), BorderRadius.circular(AlistenRadii.sm));
    });

    testWidgets('in a desktop window lights up to the edges of its panel', (
      tester,
    ) async {
      await pump(tester, alert: false);
      expect(shape(tester), BorderRadius.zero);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  testWidgets('a row without anything to attend to has no dot', (tester) async {
    await pump(tester, alert: false);
    expect(dot(), findsNothing);
  });

  testWidgets('a section page has a back button and its title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: const SectionPage(title: '站点', children: [Text('内容')]),
      ),
    );
    expect(find.text('站点'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    expect(find.bySemanticsLabel('返回'), findsOneWidget);
  });
}
