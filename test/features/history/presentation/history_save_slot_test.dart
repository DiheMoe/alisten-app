import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/pick_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';
import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';

const _song = Track(source: TrackSource.qq, id: '001');

void main() {
  late List<(Track, String)> asked;

  Future<void> pump(
    WidgetTester tester, {
    required bool withSlot,
    Size size = const Size(360, 780),
    TextScaler textScaler = TextScaler.noScaling,
    PickStatus? picked,
  }) async {
    asked = [];
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = FakeAlistenApi()
      ..listens.add(
        Listen(
          track: _song,
          meta: const TrackMeta(
            title: '晴天',
            artist: '周杰伦',
            album: '叶惠美',
            coverUrl: '',
            pageUrl: '',
            durationMs: 269000,
          ),
          heardAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await alistenAppOverrides(
            api: api,
            credentials: FakeCredentialStore()..memberToken = 'member-token',
          ),
          if (picked != null)
            pickControllerProvider.overrideWithBuild(
              (ref, _) => Picks(statuses: {trackKey(_song): picked}),
            ),
          // 点歌按钮只在房间里显示。
          roomControllerProvider.overrideWithBuild(
            (ref, _) => RoomState(
              status: RoomConnectionStatus.open,
              activeRoomId: 'room-id',
              snapshot: testRoomSnapshot().copyWith(term: 1, seq: 1),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: HistoryScreen(
            onResult: (_, _) {},
            onNotice: (_, _) {},
            onCopyTitle: (_) {},
            saveToPlaylist: withSlot
                ? (context, track, title) {
                    expect(context.mounted, isTrue);
                    asked.add((track, title));
                  }
                : null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('《晴天》的更多操作'));
    await tester.pumpAndSettle();
  }

  testWidgets('without a slot the menu of a row has no save entry', (
    tester,
  ) async {
    await pump(tester, withSlot: false);
    await openMenu(tester);

    expect(find.text('复制歌名'), findsOneWidget);
    expect(find.text('保存到歌单'), findsNothing);
  });

  testWidgets('with a slot the pick button stays on the row, and saving from '
      'the menu is given the song of the record', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, withSlot: true);

    expect(find.byIcon(AlistenIcons.listPlus), findsNothing);
    expect(
      tester.getRect(find.bySemanticsLabel('再点一次《晴天》')).right,
      lessThanOrEqualTo(
        tester.getRect(find.bySemanticsLabel('《晴天》的更多操作')).left,
      ),
    );
    await openMenu(tester);
    await tester.tap(find.text('保存到歌单'));
    await tester.pumpAndSettle();

    expect(asked, hasLength(1));
    expect(trackKey(asked.single.$1), 'qq:001');
    expect(asked.single.$2, '晴天');
    expect(find.text('保存到歌单'), findsNothing, reason: 'the menu closed');
    semantics.dispose();
  });

  testWidgets('the smallest phone at 3x text keeps a row with the menu and a '
      'spelled-out pick result inside its width', (tester) async {
    await pump(
      tester,
      withSlot: true,
      size: const Size(320, 760),
      textScaler: const TextScaler.linear(3),
      picked: PickStatus.unknown,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('结果未知'), findsOneWidget);
    expect(
      find.byIcon(AlistenIcons.dotsThreeBold).hitTestable(),
      findsOneWidget,
    );
    expect(find.byIcon(AlistenIcons.questionBold).hitTestable(), findsOne);
  });
}
