import 'dart:async';
import 'dart:convert';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/presentation/playlist_cover.dart';
import 'package:alisten/features/playlists/presentation/playlist_header.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
import 'package:alisten/features/playlists/presentation/playlist_song.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playlists_page_harness.dart';

void main() {
  group('pickBlockedReason', () {
    const link = Track(
      source: TrackSource.link,
      id: 'https://example.com/a.mp3',
    );
    const bilibili = Track(
      source: TrackSource.link,
      id: 'https://www.bilibili.com/video/BV1xx411c7mD',
    );
    const netease = Track(source: TrackSource.netease, id: '1');

    test('only a link that is not Bilibili, in an ephemeral room', () {
      expect(pickBlockedReason(link, RoomKind.ephemeral), '临时房间不能点链接里的歌');
      expect(pickBlockedReason(bilibili, RoomKind.ephemeral), isNull);
      expect(pickBlockedReason(link, RoomKind.persistent), isNull);
      expect(pickBlockedReason(link, null), isNull);
      expect(pickBlockedReason(netease, RoomKind.ephemeral), isNull);
    });
  });

  test('a song subtitle leaves out what is empty', () {
    TrackMeta meta(String artist, String album) => TrackMeta(
      title: '晴天',
      artist: artist,
      album: album,
      coverUrl: '',
      pageUrl: '',
      durationMs: 0,
    );

    expect(playlistSongSubtitle(meta('周杰伦', '叶惠美')), '周杰伦 · 叶惠美');
    expect(playlistSongSubtitle(meta('周杰伦', '')), '周杰伦');
    expect(playlistSongSubtitle(meta('', '叶惠美')), '叶惠美');
    expect(playlistSongSubtitle(meta('', '')), isNull);
  });

  testWidgets('favorites without a cover show a star, others a note', (
    tester,
  ) async {
    await pumpPlaylistsPage(
      tester,
      const Scaffold(
        body: Row(
          children: [
            PlaylistCover(url: null, favorites: true, size: 52),
            PlaylistCover(url: null, favorites: false, size: 52),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  group('the name form', () {
    late List<String> submitted;
    late List<String> succeeded;
    late MutationResult<String> answer;

    Widget form() => Scaffold(
      body: PlaylistNameForm<String>(
        title: '新建歌单',
        confirmLabel: '创建',
        busyLabel: '正在创建…',
        onSubmit: (name) async {
          submitted.add(name);
          return answer;
        },
        onSucceeded: succeeded.add,
        onCancel: () {},
      ),
    );

    setUp(() {
      submitted = [];
      succeeded = [];
      answer = const MutationSucceeded('pl-1');
    });

    testWidgets('a blank name cannot be confirmed', (tester) async {
      await pumpPlaylistsPage(tester, form());

      await tester.enterText(find.byType(EditableText), '   ');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await tester.pump();

      expect(submitted, isEmpty);
    });

    testWidgets('a refusal is shown under the field and the form stays', (
      tester,
    ) async {
      answer = const MutationFailed('INVALID_ARGUMENT', '歌单名要 1 到 50 个字。');
      await pumpPlaylistsPage(tester, form());

      await tester.enterText(find.byType(EditableText), '夜跑');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await tester.pump();

      expect(submitted, ['夜跑']);
      expect(find.text('歌单名要 1 到 50 个字。'), findsOneWidget);
      expect(succeeded, isEmpty);
    });

    testWidgets('success hands on the result', (tester) async {
      await pumpPlaylistsPage(tester, form());

      await tester.enterText(find.byType(EditableText), '夜跑');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await tester.pump();

      expect(succeeded, ['pl-1']);
    });

    testWidgets(
      'the field does not take the focus, and takes at most 50 characters',
      (tester) async {
        await pumpPlaylistsPage(tester, form());

        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.focusNode.hasFocus, isFalse);
        await tester.enterText(find.byType(EditableText), 'x' * 60);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          hasLength(50),
        );
      },
    );
  });

  testWidgets('a sheet for guests asks them to sign in instead', (
    tester,
  ) async {
    var opened = 0;
    await pumpPlaylistsPage(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showPlaylistNameSheet<String>(
                context,
                title: '复制到我的歌单',
                confirmLabel: '复制',
                busyLabel: '正在复制…',
                guestMessage: '注册或登录之后就能把这个歌单复制到自己的歌单。',
                onOpenAccount: () => opened++,
                onSubmit: (_) async => const MutationSucceeded('x'),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
      signedIn: false,
    );

    await tester.tap(find.text('打开'));
    await settlePage(tester);
    expect(find.text('注册或登录之后就能把这个歌单复制到自己的歌单。'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);

    await tester.tap(find.text('去账号设置'));
    await settlePage(tester);
    expect(opened, 1);
    expect(find.text('去账号设置'), findsNothing);
  });

  testWidgets('a menu lists its entries and closes once one is picked', (
    tester,
  ) async {
    final picked = <String>[];
    await pumpPlaylistsPage(
      tester,
      Scaffold(
        body: Center(
          child: ActionMenuButton(
            semanticLabel: '“夜跑”的更多操作',
            entries: [
              ActionMenuEntry(
                icon: Icons.edit_rounded,
                label: '重命名',
                onSelected: () => picked.add('重命名'),
              ),
              ActionMenuEntry(
                icon: Icons.delete_outline_rounded,
                label: '删除',
                danger: true,
                onSelected: () => picked.add('删除'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await settlePage(tester);
    expect(find.text('重命名'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await settlePage(tester);
    expect(picked, ['删除']);
    expect(find.text('重命名'), findsNothing);
  });

  group('reportPlaylistResult', () {
    final cases =
        <(String, MutationResult<Object?>, String?, List<(ToastKind, String)>)>[
          ('success without text', const MutationSucceeded('x'), null, []),
          (
            'success with text',
            const MutationSucceeded('x'),
            '已删除',
            [(ToastKind.success, '已删除')],
          ),
          (
            'failed gives the server message',
            const MutationFailed('NOT_FOUND', '歌单不存在。'),
            '已删除',
            [(ToastKind.failure, '歌单不存在。')],
          ),
          (
            'not sent warns with its message',
            const MutationNotSent('服务器已切换'),
            '已删除',
            [(ToastKind.warning, '服务器已切换')],
          ),
          (
            'unknown warns that the result is unknown',
            const MutationUnknown(),
            '已删除',
            [(ToastKind.warning, unknownResultText)],
          ),
        ];
    for (final (name, result, success, expected) in cases) {
      test(name, () {
        final noticed = <(ToastKind, String)>[];
        reportPlaylistResult(
          (kind, text) => noticed.add((kind, text)),
          result,
          success: success,
        );
        expect(noticed, expected);
      });
    }
  });

  testWidgets('the guest state asks to go to the account settings', (
    tester,
  ) async {
    var opened = 0;
    await pumpPlaylistsPage(
      tester,
      Scaffold(body: PlaylistGuestState(onOpenAccount: () => opened++)),
    );

    expect(find.text('收藏你喜欢的歌'), findsOneWidget);
    expect(find.text('注册账号之后，就能收藏歌曲、建自己的歌单。'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('the guest prompt shows its message and opens the account', (
    tester,
  ) async {
    var opened = 0;
    await pumpPlaylistsPage(
      tester,
      Scaffold(
        body: PlaylistGuestPrompt(
          message: '先登录。',
          onOpenAccount: () => opened++,
        ),
      ),
    );

    expect(find.text('先登录。'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('loading is announced', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPlaylistsPage(tester, const Scaffold(body: PlaylistLoading()));

    expect(find.bySemanticsLabel('正在加载歌单'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a read failure is a live region and can be retried', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var retried = 0;
    await pumpPlaylistsPage(
      tester,
      Scaffold(
        body: PlaylistReadFailure(message: '网络不通', onRetry: () => retried++),
      ),
    );

    expect(find.text('读取失败：网络不通'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(PlaylistReadFailure)),
      isSemantics(isLiveRegion: true),
    );
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retried, 1);
    semantics.dispose();
  });

  group('the name form, more', () {
    Widget form({
      required Future<MutationResult<String>> Function(String) onSubmit,
      void Function(String)? onSucceeded,
    }) => Scaffold(
      body: PlaylistNameForm<String>(
        title: '新建歌单',
        confirmLabel: '创建',
        busyLabel: '正在创建…',
        onSubmit: onSubmit,
        onSucceeded: onSucceeded ?? (_) {},
        onCancel: () {},
      ),
    );

    Future<void> submit(WidgetTester tester, String typed) async {
      await tester.enterText(find.byType(EditableText), typed);
      await tester.pump();
      await tester.tap(find.text('创建'));
      await tester.pump();
    }

    testWidgets('the name is submitted exactly as typed', (tester) async {
      final submitted = <String>[];
      await pumpPlaylistsPage(
        tester,
        form(
          onSubmit: (name) async {
            submitted.add(name);
            return const MutationFailed('X', '不行');
          },
        ),
      );

      await submit(tester, '  夜跑  ');

      expect(submitted, ['  夜跑  ']);
    });

    testWidgets('an unknown result warns and keeps the form', (tester) async {
      final succeeded = <String>[];
      await pumpPlaylistsPage(
        tester,
        form(
          onSubmit: (_) async => const MutationUnknown(),
          onSucceeded: succeeded.add,
        ),
      );

      await submit(tester, '夜跑');

      expect(find.text(unknownResultText), findsOneWidget);
      expect(succeeded, isEmpty);
    });

    testWidgets('a request that was not sent shows its message', (
      tester,
    ) async {
      await pumpPlaylistsPage(
        tester,
        form(onSubmit: (_) async => const MutationNotSent('服务器已切换')),
      );

      await submit(tester, '夜跑');

      expect(find.text('服务器已切换'), findsOneWidget);
    });

    testWidgets('while sending: busy label, no second send, no cancel', (
      tester,
    ) async {
      final pending = Completer<MutationResult<String>>();
      var sent = 0;
      var cancelled = 0;
      await pumpPlaylistsPage(
        tester,
        Scaffold(
          body: PlaylistNameForm<String>(
            title: '新建歌单',
            confirmLabel: '创建',
            busyLabel: '正在创建…',
            onSubmit: (_) {
              sent++;
              return pending.future;
            },
            onSucceeded: (_) {},
            onCancel: () => cancelled++,
          ),
        ),
      );

      await submit(tester, '夜跑');
      expect(find.text('正在创建…'), findsOneWidget);
      expect(find.text('创建'), findsNothing);

      await tester.tap(find.text('正在创建…'));
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(sent, 1);
      expect(cancelled, 0);

      pending.complete(const MutationFailed('X', '不行'));
      await tester.pump();
      expect(find.text('创建'), findsOneWidget);
      await tester.tap(find.text('取消'));
      expect(cancelled, 1);
    });

    testWidgets('the sheet cannot be dismissed while sending', (tester) async {
      final pending = Completer<MutationResult<String>>();
      String? closedWith = 'open';
      await pumpPlaylistsPage(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showPlaylistNameSheet<String>(
                  context,
                  title: '新建歌单',
                  confirmLabel: '创建',
                  busyLabel: '正在创建…',
                  onSubmit: (_) => pending.future,
                ).then((value) => closedWith = value),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await settlePage(tester);

      await submit(tester, '夜跑');
      await tester.binding.handlePopRoute();
      await settlePage(tester);
      expect(find.byType(PlaylistNameForm<String>), findsOneWidget);
      expect(closedWith, 'open');

      pending.complete(const MutationSucceeded('pl-1'));
      await settlePage(tester);
      expect(find.byType(PlaylistNameForm<String>), findsNothing);
      expect(closedWith, 'pl-1');
    });
  });

  group('the menu, more', () {
    testWidgets('a menu at either edge of the screen stays on screen', (
      tester,
    ) async {
      ActionMenuButton menu(IconData icon) => ActionMenuButton(
        semanticLabel: '导入',
        icon: icon,
        entries: [
          ActionMenuEntry(
            icon: Icons.file_open_rounded,
            label: '从文件导入',
            onSelected: () {},
          ),
        ],
      );
      await pumpPlaylistsPage(
        tester,
        Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              menu(Icons.more_horiz_rounded),
              menu(Icons.more_vert_rounded),
            ],
          ),
        ),
      );
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final panel = find.ancestor(
        of: find.text('从文件导入'),
        matching: find.byType(IntrinsicWidth),
      );

      for (final icon in [Icons.more_horiz_rounded, Icons.more_vert_rounded]) {
        await tester.tap(find.byIcon(icon));
        await settlePage(tester);
        final rect = tester.getRect(panel);
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$icon');
        expect(rect.right, lessThanOrEqualTo(screen.width), reason: '$icon');

        await tester.tapAt(screen.center(Offset.zero));
        await settlePage(tester);
        expect(find.text('从文件导入'), findsNothing);
      }
    });

    testWidgets('a disabled entry does not fire and keeps the menu open', (
      tester,
    ) async {
      final picked = <String>[];
      await pumpPlaylistsPage(
        tester,
        Scaffold(
          body: Center(
            child: ActionMenuButton(
              semanticLabel: '更多',
              entries: [
                ActionMenuEntry(
                  icon: Icons.edit_rounded,
                  label: '重命名',
                  enabled: false,
                  onSelected: () => picked.add('重命名'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settlePage(tester);
      await tester.tap(find.text('重命名'));
      await settlePage(tester);

      expect(picked, isEmpty);
      expect(find.text('重命名'), findsOneWidget);
    });

    testWidgets('a checked entry shows a check and is selected in a group', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpPlaylistsPage(
        tester,
        Scaffold(
          body: Center(
            child: ActionMenuButton(
              semanticLabel: '排序',
              entries: [
                ActionMenuEntry(
                  icon: Icons.schedule_rounded,
                  label: '最近',
                  checked: true,
                  onSelected: () {},
                ),
                ActionMenuEntry(
                  icon: Icons.sort_by_alpha_rounded,
                  label: '名称',
                  checked: false,
                  onSelected: () {},
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settlePage(tester);

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('最近'))),
        isSemantics(
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('名称'))),
        isSemantics(
          isSelected: false,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the trigger is labelled and reports whether it is open', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpPlaylistsPage(
        tester,
        Scaffold(
          body: Center(
            child: ActionMenuButton(
              semanticLabel: '“夜跑”的更多操作',
              entries: [
                ActionMenuEntry(
                  icon: Icons.edit_rounded,
                  label: '重命名',
                  onSelected: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final trigger = find.bySemanticsLabel('“夜跑”的更多操作');
      expect(
        tester.getSemantics(trigger),
        isSemantics(isExpanded: false, hasExpandedState: true, isButton: true),
      );
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await settlePage(tester);
      expect(
        tester.getSemantics(trigger),
        isSemantics(isExpanded: true, hasExpandedState: true, isButton: true),
      );
      semantics.dispose();
    });
  });

  group('the favorites badge', () {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
      '60e6kgAAAABJRU5ErkJggg==',
    );

    Widget cover({
      required String? url,
      required bool favorites,
      required double size,
    }) => CoverImages(
      resolve: (_) => MemoryImage(png),
      child: Scaffold(
        body: PlaylistCover(url: url, favorites: favorites, size: size),
      ),
    );

    testWidgets('only favorites with an image larger than a row get it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpPlaylistsPage(
        tester,
        cover(url: 'https://c/a', favorites: true, size: 120),
      );
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      // 星标只作装饰，读屏不读。
      expect(
        find.ancestor(
          of: find.byIcon(Icons.star_rounded),
          matching: find.byWidgetPredicate(
            (widget) => widget is ExcludeSemantics && widget.excluding,
          ),
        ),
        findsWidgets,
      );
      expect(
        find.semantics.byPredicate(
          (node) => node.label.contains('星') || node.label.contains('star'),
        ),
        findsNothing,
      );
      semantics.dispose();

      await pumpPlaylistsPage(
        tester,
        cover(url: 'https://c/a', favorites: false, size: 120),
      );
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('a row-sized cover has no badge', (tester) async {
      await pumpPlaylistsPage(
        tester,
        cover(url: 'https://c/a', favorites: true, size: AlistenSizes.rowCover),
      );
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });
  });

  testWidgets('the header names the playlist as a heading', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPlaylistsPage(
      tester,
      const Scaffold(
        body: PlaylistHeader(
          coverUrl: null,
          favorites: false,
          name: '夜跑',
          facts: '3 首歌',
        ),
      ),
    );

    expect(find.text('3 首歌'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('夜跑')),
      isSemantics(isHeader: true),
    );
    semantics.dispose();
  });
}
