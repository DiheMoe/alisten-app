import 'dart:async';

import 'package:alisten/app/router.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';

final class _FlakyLicenses extends OpenSourceLicenses {
  static int reads = 0;
  static late Completer<void> firstRead;

  @override
  Future<List<PackageLicenses>> build() async {
    if (reads++ == 0) {
      await firstRead.future;
      throw StateError('NOTICES unreadable');
    }
    return _packages;
  }
}

final _packages = [
  PackageLicenses('dio', [
    LicenseEntryWithLineBreaks(const ['dio'], 'MIT License\n\nCopyright dio'),
  ]),
];

void main() {
  testWidgets('the licenses show progress while read, a failure to read them '
      'can be retried, and a package expands to its license text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    _FlakyLicenses.reads = 0;
    _FlakyLicenses.firstRead = Completer();
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(
      tester,
      overrides: [openSourceLicensesProvider.overrideWith(_FlakyLicenses.new)],
    );
    appContainer(tester).read(routerProvider).go('/settings/licenses');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);

    _FlakyLicenses.firstRead.complete();
    await tester.pumpAndSettle();
    expect(find.text('没能读取开源许可'), findsOneWidget);
    expect(find.text('dio'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('没能读取开源许可'), findsNothing);
    expect(find.text('1 份许可'), findsOneWidget);
    final header = find.ancestor(
      of: find.text('dio'),
      matching: find.byType(Pressable),
    );
    expect(
      tester.getSemantics(header),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
    );
    expect(find.text('MIT License'), findsNothing);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(header), isSemantics(isExpanded: true));
    expect(find.text('MIT License'), findsOneWidget);
    expect(find.text('Copyright dio'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('licenses that never finish reading end in the error state '
      'after 15 seconds, which a retry recovers from', (tester) async {
    final semantics = tester.ensureSemantics();
    var reads = 0;
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(
      () => reads++ == 0
          ? StreamController<LicenseEntry>().stream
          : Stream.value(_packages.single.licenses.single),
    );
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(tester);
    appContainer(tester).read(routerProvider).go('/settings/licenses');
    await tester.pump();

    await tester.pump(const Duration(seconds: 14));
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);
    expect(find.text('没能读取开源许可'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('没能读取开源许可'), findsOneWidget);
    expect(find.bySemanticsLabel('加载中'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('没能读取开源许可'), findsNothing);
    expect(find.text('1 份许可'), findsOneWidget);
    semantics.dispose();
  });
}
