import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/search/application/pick_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';
import '../../lobby/lobby_test_doubles.dart';

const _song = Track(source: TrackSource.qq, id: '001');

void main() {
  late List<(Track, String)> asked;
  late List<Track> tapped;

  Future<void> pump(
    WidgetTester tester, {
    required bool withSlot,
    Size size = const Size(360, 780),
    TextScaler textScaler = TextScaler.noScaling,
    PickStatus? picked,
  }) async {
    asked = [];
    tapped = [];
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
                ? (track, title) {
                    asked.add((track, title));
                    return IconCircleButton(
                      icon: Icons.playlist_add_rounded,
                      semanticLabel: '把《$title》保存到歌单',
                      style: IconCircleButtonStyle.plain,
                      iconSize: AlistenSizes.iconSm,
                      onPressed: () => tapped.add(track),
                    );
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

  testWidgets('without a slot a row has no save button', (tester) async {
    await pump(tester, withSlot: false);

    expect(find.text('晴天'), findsOneWidget);
    expect(find.byIcon(Icons.playlist_add_rounded), findsNothing);
  });

  testWidgets('with a slot the save button comes before the pick button and '
      'is given the song of the record', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, withSlot: true);

    expect(find.bySemanticsLabel('把《晴天》保存到歌单'), findsOneWidget);
    expect(
      tester.getRect(find.bySemanticsLabel('把《晴天》保存到歌单')).right,
      lessThanOrEqualTo(tester.getRect(find.bySemanticsLabel('再点一次《晴天》')).left),
    );
    expect(trackKey(asked.last.$1), 'qq:001');
    expect(asked.last.$2, '晴天');

    await tester.tap(find.byIcon(Icons.playlist_add_rounded));
    await tester.pump();

    expect([for (final track in tapped) trackKey(track)], ['qq:001']);
    semantics.dispose();
  });

  testWidgets('the smallest phone at 3x text keeps a row with the save '
      'button and a spelled-out pick result inside its width', (tester) async {
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
      find.byIcon(Icons.playlist_add_rounded).hitTestable(),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.question_mark_rounded).hitTestable(), findsOne);
  });
}
