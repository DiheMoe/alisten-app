import 'dart:async';

import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/my_playlist_controller.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/playlist_view_controller.dart';
import 'package:alisten/features/playlists/presentation/playlist_song.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/chip_pill.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/features/playlists/presentation/playlist_cover.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 点歌页“我的歌单”来源的内容，是一个 sliver：一排歌单标签，下面是选中歌单里的
/// 歌，每首可以直接点。歌单顺序与“我的歌单”页相同，默认选第一个。[filter] 按
/// 歌名、歌手和专辑筛选选中歌单里的歌。
class MyPlaylistsPicker extends ConsumerStatefulWidget {
  const MyPlaylistsPicker({
    required this.filter,
    required this.onPick,
    required this.onOpenAccount,
    super.key,
  });

  final String filter;
  final PickSong onPick;
  final VoidCallback onOpenAccount;

  @override
  ConsumerState<MyPlaylistsPicker> createState() => _MyPlaylistsPickerState();
}

class _MyPlaylistsPickerState extends ConsumerState<MyPlaylistsPicker> {
  String? _chosen;

  static const _chipWidth = 200.0;

  final _chipKeys = <String, GlobalKey>{};

  void _choose(String id) {
    setState(() => _chosen = id);
    // 从“全部歌单”里选的标签可能还在屏幕外，等这一帧排好再滚过去。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _chipKeys[id]?.currentContext;
      if (!mounted || chip == null) return;
      unawaited(
        Scrollable.ensureVisible(
          chip,
          alignment: 0.5,
          duration: AlistenDurations.of(context, AlistenDurations.medium),
          curve: AlistenCurves.standard,
        ),
      );
    });
  }

  Future<void> _chooseFromAll(List<MyPlaylist> shown, String chosen) async {
    final picked = await showSheetPanel<String>(
      context,
      builder: (_) => _AllPlaylists(playlists: shown, chosen: chosen),
    );
    if (picked != null && mounted) _choose(picked);
  }

  static const _statePadding = EdgeInsets.symmetric(
    vertical: AlistenSpacing.xxxl,
  );

  Widget _state(Widget child) {
    return SliverToBoxAdapter(
      child: Padding(padding: _statePadding, child: child),
    );
  }

  Widget _note(String text) {
    return _state(
      Center(
        child: Text(
          text,
          style: AlistenTypography.secondary.copyWith(
            color: AlistenColors.of(context).onGlassMuted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myPlaylistsControllerProvider);
    final playlists = list.playlists;
    if (list.guest) {
      return _state(PlaylistGuestState(onOpenAccount: widget.onOpenAccount));
    }
    if (playlists == null) {
      final error = list.error;
      return _state(
        error == null
            ? const PlaylistLoading()
            : PlaylistReadFailure(
                message: error,
                onRetry: () => unawaited(
                  ref.read(myPlaylistsControllerProvider.notifier).retry(),
                ),
              ),
      );
    }
    if (playlists.isEmpty) return _note('还没有歌单');
    final sort = ref.watch(playlistViewProvider.select((view) => view.sort));
    final shown = sortPlaylists(playlists, sort);
    final chosen = shown.any((playlist) => playlist.id == _chosen)
        ? _chosen!
        : shown.first.id;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Semantics(
            container: true,
            label: '歌单',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AlistenSpacing.md,
                AlistenSpacing.xs,
                AlistenSpacing.md,
                AlistenSpacing.xs,
              ),
              child: Row(
                spacing: AlistenSpacing.xs,
                children: [
                  // 标签只有一行，歌单多了要横着滑很久；这里一次看全。
                  IconCircleButton(
                    icon: Icons.format_list_bulleted_rounded,
                    semanticLabel: '全部歌单',
                    diameter: AlistenSizes.chipHeight,
                    iconSize: AlistenSizes.iconSm,
                    onPressed: () => unawaited(_chooseFromAll(shown, chosen)),
                  ),
                  for (final playlist in shown)
                    // 名字很长的歌单不独占一屏；歌单多时选中的那个滚到看得见的
                    // 位置。
                    ConstrainedBox(
                      key: _chipKeys.putIfAbsent(playlist.id, GlobalKey.new),
                      constraints: const BoxConstraints(maxWidth: _chipWidth),
                      child: Builder(
                        builder: (chip) => ChipPill(
                          label: playlist.name,
                          icon: playlist.favorites ? Icons.star_rounded : null,
                          selected: playlist.id == chosen,
                          onPressed: () => _choose(playlist.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _songs(chosen),
      ],
    );
  }

  Widget _songs(String id) {
    final detail = ref.watch(myPlaylistControllerProvider(id));
    final items = detail.items;
    if (items == null) {
      final error = detail.error;
      return _state(
        error == null
            ? const PlaylistLoading()
            : PlaylistReadFailure(
                message: error,
                onRetry: () => unawaited(
                  ref.read(myPlaylistControllerProvider(id).notifier).load(),
                ),
              ),
      );
    }
    if (items.isEmpty) return _note('这个歌单还是空的');
    final words = widget.filter.trim().toLowerCase();
    final matched = words.isEmpty
        ? items
        : [
            for (final item in items)
              if (_matches(item.meta, words)) item,
          ];
    if (matched.isEmpty) return _note('这个歌单里没有匹配的歌');
    return SliverList.builder(
      itemCount: matched.length,
      itemBuilder: (context, index) {
        final item = matched[index];
        final meta = item.meta;
        return TrackRow(
          key: ValueKey(trackKey(item.track)),
          title: meta.title,
          subtitle: playlistSongSubtitle(meta),
          coverUrl: meta.coverUrl,
          trailing: PlaylistPickControl(
            track: item.track,
            title: meta.title,
            onPick: widget.onPick,
          ),
        );
      },
    );
  }

  static bool _matches(TrackMeta meta, String words) {
    return meta.title.toLowerCase().contains(words) ||
        meta.artist.toLowerCase().contains(words) ||
        meta.album.toLowerCase().contains(words);
  }
}

class _AllPlaylists extends StatelessWidget {
  const _AllPlaylists({required this.playlists, required this.chosen});

  final List<MyPlaylist> playlists;
  final String chosen;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '全部歌单',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.sm),
        for (final playlist in playlists)
          Pressable(
            onPressed: () => dismissSheet(context, playlist.id),
            selected: playlist.id == chosen,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AlistenSpacing.xs),
              child: Row(
                children: [
                  PlaylistCover(
                    url: playlist.coverUrl,
                    favorites: playlist.favorites,
                    size: AlistenSizes.rowCover,
                  ),
                  const SizedBox(width: AlistenSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AlistenTypography.bodyStrong.copyWith(
                            color: colors.onGlass,
                          ),
                        ),
                        Text(
                          '${playlist.trackCount} 首',
                          style: AlistenTypography.secondary.copyWith(
                            color: colors.onGlassMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (playlist.id == chosen)
                    Icon(Icons.check_rounded, color: colors.onGlass),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
