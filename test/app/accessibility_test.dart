import 'package:alisten/app/app.dart';
import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import '../features/search/search_test_doubles.dart' show defaultSearchAnswers;
import 'app_test_harness.dart';

final _themes = ValueVariant({Brightness.light, Brightness.dark});

Future<void> _expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

// 应用默认跟随系统深浅模式。
MediaQueryData _system() =>
    MediaQueryData(platformBrightness: _themes.currentValue!);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('application text scale follows the system alone', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: await alistenAppOverrides(
        preferences: {'alisten.font-size': 18},
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: AlistenApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 旧版本保存的字号设置不再缩放文字。
    final context = tester.element(find.text('还没有可加入的房间'));
    expect(MediaQuery.textScalerOf(context).scale(1), 1.5);
    container.dispose();
  });

  testWidgets('the lobby meets the tap target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(
      tester,
      system: _system(),
      api: FakeAlistenApi()
        ..rooms = [
          roomListing(),
          roomListing(id: 'locked', slug: null, hasPassword: true),
        ],
    );

    await _expectAccessible(tester);
    semantics.dispose();
  }, variant: _themes);

  testWidgets('every mode of the room meets the tap target, label and '
      'contrast guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    final (rooms: _, :router, :settle) = await enterRoom(
      tester,
      system: _system(),
    );

    for (final mode in RoomMode.values) {
      router.go(mode.routeIn('listen'));
      await settle();
      await _expectAccessible(tester);
    }
    semantics.dispose();
  }, variant: _themes);

  testWidgets('song search meets the tap target, label and contrast '
      'guidelines, before and after a search', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:rooms, :router, :settle) = await enterRoom(
      tester,
      system: _system(),
    );
    rooms.last.responses.addAll(defaultSearchAnswers());
    router.go('/r/listen/search');
    await settle();
    await _expectAccessible(tester);

    await tester.enterText(find.byType(EditableText), '夜曲');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle();
    expect(find.bySemanticsLabel(RegExp('^点歌《')), findsWidgets);
    await _expectAccessible(tester);
    semantics.dispose();
  }, variant: _themes);

  testWidgets('settings meet the tap target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(tester, system: _system());
    appContainer(tester).read(routerProvider).go('/settings');
    await tester.pumpAndSettle();

    await _expectAccessible(tester);
    semantics.dispose();
  }, variant: _themes);

  testWidgets('at twice the text size the lobby, the player and song search '
      'fit a phone, and the player keeps 48 by 48 controls clear of the '
      'bars', (tester) async {
    final semantics = tester.ensureSemantics();
    const twice = MediaQueryData(textScaler: TextScaler.linear(2));
    final (rooms: _, :router, :settle) = await enterRoom(tester, system: twice);
    expect(tester.takeException(), isNull);

    for (final label in ['暂停本机播放', '投票切歌', '调节本机音量']) {
      final control = find.bySemanticsLabel(label);
      final size = tester.getSize(control);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      expectBetween(
        tester,
        control,
        above: find.bySemanticsLabel('收起房间'),
        below: find.bySemanticsLabel('歌词'),
      );
    }

    router.go('/r/listen/search');
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('返回房间'), findsOneWidget);

    router.go('/');
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.text('Alisten'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('with animations removed, no mode of the room keeps drawing '
      'frames', (tester) async {
    final (rooms: _, :router, :settle) = await enterRoom(
      tester,
      system: const MediaQueryData(disableAnimations: true),
    );

    for (final mode in RoomMode.values) {
      router.go(mode.routeIn('listen'));
      await settle();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: '$mode');
    }
  });
}
