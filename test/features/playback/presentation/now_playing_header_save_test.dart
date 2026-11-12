import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';
import '../../../domain/room/room_fixtures.dart';

const _longTitle = '一首名字很长很长很长很长很长很长很长的歌';
const _longArtist = '一位名字也很长很长很长很长很长很长的歌手';

const _longSong = NowPlaying(
  entry: QueueEntry(
    id: 'long',
    track: testTrack,
    meta: TrackMeta(
      title: _longTitle,
      artist: _longArtist,
      album: '专辑',
      coverUrl: '',
      pageUrl: '',
      durationMs: 180000,
    ),
    requestedBy: null,
    auto: false,
    likes: 0,
    status: QueueEntryStatus.ready,
  ),
  mediaUrl: '/media/netease/track-id',
  startedAtMs: 1000000,
  durationMs: 180000,
  gain: 1,
  lyric: '',
);

Widget _saveButton(Track track, String title) => IconCircleButton(
  icon: AlistenIcons.listPlus,
  semanticLabel: '把《$title》保存到歌单',
  style: IconCircleButtonStyle.plain,
  onPressed: () {},
);

Future<void> _stage(
  WidgetTester tester, {
  required Size size,
  required ValueListenable<bool> compact,
  NowPlaying? nowPlaying,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: await alistenAppOverrides(),
      child: MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: compact,
            builder: (context, compact, _) => NowPlayingHeader(
              nowPlaying: nowPlaying ?? testNowPlaying,
              compact: compact,
              connected: true,
              onAddSong: () {},
              onVoteSkipped: (_) {},
              body: const SizedBox.expand(),
              saveToPlaylist: _saveButton,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

void main() {
  late List<(Track, String)> asked;

  Future<void> pump(
    WidgetTester tester, {
    required bool compact,
    bool withSlot = true,
  }) async {
    asked = [];
    tester.view
      ..physicalSize = const Size(360, 700) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: NowPlayingHeader(
              nowPlaying: testNowPlaying,
              compact: compact,
              connected: true,
              onAddSong: () {},
              onVoteSkipped: (_) {},
              body: compact ? const SizedBox.expand() : null,
              saveToPlaylist: withSlot
                  ? (track, title) {
                      asked.add((track, title));
                      return Text('保存 $title');
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('the full player puts the slot at the end of the first title '
      'line, with the song playing', (tester) async {
    await pump(tester, compact: false);

    final title = tester.getRect(find.text('歌曲'));
    final save = tester.getRect(find.text('保存 歌曲'));
    expect(title.right, lessThanOrEqualTo(save.left));
    expect((save.center.dy - title.center.dy).abs(), lessThan(1));
    expect(asked.last.$1.id, testNowPlaying.entry.track.id);
    expect(asked.last.$2, '歌曲');
  });

  testWidgets('the collapsed player has no slot', (tester) async {
    await pump(tester, compact: true);

    expect(find.text('保存 歌曲'), findsNothing);
  });

  testWidgets('without a slot the player has nothing extra', (tester) async {
    await pump(tester, compact: false, withSlot: false);

    expect(find.textContaining('保存'), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(780, 360)]) {
    for (final scale in const [0.85, 1.0, 2.0, 3.0]) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()} and '
          '${scale}x text a long title and its subtitle stop before the slot, '
          'which stays on the first line and inside the player', (
        tester,
      ) async {
        final compact = ValueNotifier(false);
        addTearDown(compact.dispose);
        await _stage(
          tester,
          size: size,
          compact: compact,
          nowPlaying: _longSong,
          textScaler: TextScaler.linear(scale),
        );

        expect(tester.takeException(), isNull);
        final save = tester.getRect(find.byType(IconCircleButton));
        final title = find.text(_longTitle);
        final subtitle = find.textContaining(_longArtist);
        expect(
          tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
          isTrue,
        );
        expect(tester.getRect(title).right, lessThanOrEqualTo(save.left));
        expect(tester.getRect(subtitle).right, lessThanOrEqualTo(save.left));
        expect(
          (save.center.dy - tester.getRect(title).center.dy).abs(),
          lessThan(1),
        );
        expect(save.top, greaterThanOrEqualTo(0));
        expect(save.right, lessThanOrEqualTo(size.width));
      });
    }
  }

  testWidgets('collapsing the player takes the slot away from touch and the '
      'screen reader at once, then removes it; expanding brings it '
      'back', (tester) async {
    final semantics = tester.ensureSemantics();
    final compact = ValueNotifier(false);
    addTearDown(compact.dispose);
    await _stage(tester, size: const Size(360, 700), compact: compact);
    final save = find.byIcon(AlistenIcons.listPlus);

    expect(save.hitTestable(), findsOneWidget);
    expect(find.semantics.byLabel('把《歌曲》保存到歌单'), findsOne);

    compact.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(save, findsOneWidget);
    expect(save.hitTestable(), findsNothing);
    expect(find.semantics.byLabel('把《歌曲》保存到歌单'), findsNothing);

    await tester.pump(const Duration(seconds: 1));

    expect(save, findsNothing);

    compact.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(save.hitTestable(), findsOneWidget);
    expect(find.semantics.byLabel('把《歌曲》保存到歌单'), findsOne);
    semantics.dispose();
  });
}
