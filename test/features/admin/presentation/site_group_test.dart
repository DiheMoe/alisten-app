import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/admin/presentation/site_group.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/settings_list.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

void main() {
  late FakeAdminApi api;
  late List<(ToastKind, String)> notices;

  setUp(() {
    api = FakeAdminApi();
    notices = [];
  });

  Finder field() => find.descendant(
    of: find.byType(AlistenTextField),
    matching: find.byType(EditableText),
  );

  Future<void> openSite(WidgetTester tester) async {
    final container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: SettingsGroup(
              children: [
                SiteGroup(onNotice: (kind, text) => notices.add((kind, text))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('a changed brand name is saved when the field is done, and '
      'says so in place for 2 seconds', (tester) async {
    await openSite(tester);
    await tester.enterText(field(), '周末听歌会');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(api.updatedBrandName, '周末听歌会');
    await tester.pumpAndSettle();
    expect(find.text('✓ 已保存'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('✓ 已保存'), findsNothing);
    expect(find.text('保存'), findsNothing);
  });

  testWidgets('leaving the field saves a change', (tester) async {
    await openSite(tester);
    await tester.enterText(field(), '周末听歌会');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(api.updatedBrandName, '周末听歌会');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('an unchanged name is not sent', (tester) async {
    await openSite(tester);
    await tester.tap(field());
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(api.updatedBrandName, isNull);
  });

  testWidgets('a refused name says why under the field and keeps the input', (
    tester,
  ) async {
    await openSite(tester);
    await tester.enterText(field(), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(brandNameRuleText), findsOneWidget);
    expect(api.updatedBrandName, isNull);
  });

  testWidgets('a lost answer reads the name again and says so', (tester) async {
    await openSite(tester);
    api.updateBrandError = const ApiException(
      code: 'UNAVAILABLE',
      message: 'gone',
      status: 503,
    );
    await tester.enterText(field(), '周末听歌会');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(notices.last, (ToastKind.warning, '没能确认是否保存，已重新读取'));
    expect(tester.widget<EditableText>(field()).controller.text, 'Alisten');
  });

  testWidgets('the saving spinner sits beside the field only while saving', (
    tester,
  ) async {
    final gate = api.updateBrandGate = Completer<void>();
    await openSite(tester);
    expect(find.bySemanticsLabel('正在保存'), findsNothing);
    await tester.enterText(field(), '周末听歌会');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.bySemanticsLabel('正在保存'), findsOneWidget);
    expect(find.text('正在保存…'), findsNothing);
    final spinner = tester.getCenter(find.byType(BusyIndicator));
    expect(spinner.dx, greaterThan(tester.getCenter(field()).dx));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('正在保存'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });
}
