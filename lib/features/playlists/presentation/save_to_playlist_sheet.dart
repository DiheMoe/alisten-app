import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart'
    show doneOnOldServerText, serverChangedNotice, unsureOnOldServerText;
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/presentation/playlist_cover.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/animated_resize.dart';
import 'package:alisten/shared/ui/fade_leaving_inert.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class SaveTarget {
  const SaveTarget();
}

/// 面板记住打开时的那首歌：从播放器打开后换了歌，勾选仍作用于这首。
final class SaveOneTrack extends SaveTarget {
  const SaveOneTrack({required this.track, required this.title});

  final Track track;
  final String title;
}

final class SaveManyTracks extends SaveTarget {
  const SaveManyTracks({required this.from, required this.tracks});

  final MyPlaylist from;
  final List<Track> tracks;
}

Future<void> showSaveToPlaylistSheet(
  BuildContext context,
  SaveTarget target, {
  required VoidCallback onOpenAccount,
  required PlaylistNotice onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => SaveToPlaylistSheet(
      target: target,
      onOpenAccount: onOpenAccount,
      onNotice: onNotice,
    ),
  );
}

/// 保存走 REST，不需要房间连接，所以始终可用。
class SaveToPlaylistButton extends StatelessWidget {
  const SaveToPlaylistButton({
    required this.track,
    required this.title,
    required this.onOpenAccount,
    required this.onNotice,
    this.iconSize = AlistenSizes.icon,
    super.key,
  });

  final Track track;
  final String title;
  final VoidCallback onOpenAccount;
  final PlaylistNotice onNotice;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconCircleButton(
      icon: Icons.playlist_add_rounded,
      semanticLabel: title.isEmpty ? '保存到歌单' : '把《$title》保存到歌单',
      style: IconCircleButtonStyle.plain,
      iconSize: iconSize,
      onPressed: () => unawaited(
        showSaveToPlaylistSheet(
          context,
          SaveOneTrack(track: track, title: title),
          onOpenAccount: onOpenAccount,
          onNotice: onNotice,
        ),
      ),
    );
  }
}

const _switchNotices = {
  serverChangedNotice,
  doneOnOldServerText,
  unsureOnOldServerText,
};

/// 多首保存的提示：成功的合成一条，失败的各一条，语气与 [reportPlaylistResult]
/// 相同。被拒（UNAUTHORIZED）和服务器切换的文字每个目标都一样，只提示一次。
List<(ToastKind, String)> copySummary(
  List<(MyPlaylist, MutationResult<int>)> results,
  int trackCount,
) {
  final saved = [
    for (final (playlist, result) in results)
      if (result case MutationSucceeded(:final value)) (playlist, value),
  ];
  final notices = <(ToastKind, String)>[];
  if (saved.isNotEmpty) {
    final head = saved.length == 1
        ? '已保存到“${saved.single.$1.name}”'
        : '已保存到 ${saved.length} 个歌单';
    final already = saved.fold<int>(
      0,
      (sum, entry) => sum + trackCount - entry.$2,
    );
    notices.add((
      ToastKind.success,
      already > 0 ? '$head，其中 $already 首已经在里面' : head,
    ));
  }
  String? refused;
  final switched = <String>{};
  for (final (playlist, result) in results) {
    switch (result) {
      case MutationSucceeded():
        break;
      case MutationFailed(code: 'UNAUTHORIZED', :final message):
        refused ??= message;
      case MutationFailed(:final message):
        notices.add((ToastKind.failure, '没能保存到“${playlist.name}”：$message'));
      case MutationNotSent(:final message)
          when _switchNotices.contains(message):
        switched.add(message);
      case MutationNotSent(:final message):
        notices.add((ToastKind.warning, '没能保存到“${playlist.name}”：$message'));
      case MutationUnknown():
        notices.add((ToastKind.warning, '保存到“${playlist.name}”的结果未知，已重新读取'));
    }
  }
  for (final message in switched) {
    notices.add((ToastKind.warning, message));
  }
  if (refused != null) notices.add((ToastKind.failure, refused));
  return notices;
}

// 默认居中叠放：新旧内容高度不同时，切换途中两者都会上下跳动。
Widget _topAligned(Widget? current, List<Widget> previous) =>
    Stack(alignment: Alignment.topCenter, children: [...previous, ?current]);

const _newestFirst = PlaylistSort(
  PlaylistSortKey.updatedAt,
  SortOrder.descending,
);

class SaveToPlaylistSheet extends ConsumerStatefulWidget {
  const SaveToPlaylistSheet({
    required this.target,
    required this.onOpenAccount,
    required this.onNotice,
    super.key,
  });

  final SaveTarget target;
  final VoidCallback onOpenAccount;
  final PlaylistNotice onNotice;

  @override
  ConsumerState<SaveToPlaylistSheet> createState() =>
      _SaveToPlaylistSheetState();
}

class _SaveToPlaylistSheetState extends ConsumerState<SaveToPlaylistSheet> {
  final _newPlaylist = FocusNode(debugLabel: 'new playlist');
  final Map<String, FocusNode> _rows = {};
  final Set<String> _targets = {};
  List<String>? _order;

  // 打开时重新读取列表和这首歌在哪些歌单里，都读到之前显示读取中：控制器可能
  // 已经活着，手里是之前读到的列表和勾选。
  bool _listPending = true;
  late bool _membershipPending = widget.target is SaveOneTrack;
  int _membershipRead = 0;
  String? _membershipError;
  bool _creating = false;
  bool _saving = false;

  MyPlaylistsController get _playlists =>
      ref.read(myPlaylistsControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // 构建期间不能改 provider 状态。
    unawaited(Future.microtask(_open));
  }

  @override
  void dispose() {
    _newPlaylist.dispose();
    for (final node in _rows.values) {
      node.dispose();
    }
    super.dispose();
  }

  // 列表为空且没有失败时，控制器自己正在读取：刚建好，或者身份还没读到。
  Future<void> _open() async {
    if (!mounted) return;
    final target = widget.target;
    if (target is SaveOneTrack) unawaited(_readMembership(target));
    final list = ref.read(myPlaylistsControllerProvider);
    if (list.playlists != null || list.error != null) {
      await _playlists.retry();
    }
    if (mounted) setState(() => _listPending = false);
  }

  // 只有面板最后发起的那次读取能结束读取中：被重试取代的读取返回 null，再据此
  // 补读就会一次次地取代下一次。
  Future<void> _readMembership(SaveOneTrack target) async {
    final read = ++_membershipRead;
    setState(() {
      _membershipPending = true;
      _membershipError = null;
    });
    final error = await _playlists.containing(target.track);
    if (!mounted || read != _membershipRead) return;
    setState(() {
      _membershipPending = false;
      _membershipError = error;
    });
    _readMembershipIfMissing();
  }

  // 身份还没读到时读取什么也不做，归属重新开始时勾选也被清空：列表读到之后
  // 补读。
  void _readMembershipIfMissing() {
    final target = widget.target;
    if (!mounted ||
        target is! SaveOneTrack ||
        _membershipPending ||
        _membershipError != null) {
      return;
    }
    final list = ref.read(myPlaylistsControllerProvider);
    if (list.playlists == null ||
        list.memberships.containsKey(trackKey(target.track))) {
      return;
    }
    unawaited(_readMembership(target));
  }

  void _retry() {
    final target = widget.target;
    if (ref.read(myPlaylistsControllerProvider).playlists == null) {
      unawaited(_playlists.retry());
    }
    if (target is SaveOneTrack) unawaited(_readMembership(target));
  }

  FocusNode _rowFocus(String id) =>
      _rows.putIfAbsent(id, () => FocusNode(debugLabel: 'playlist $id'));

  bool _includes(SaveOneTrack target, MyPlaylist playlist) =>
      ref
          .read(myPlaylistsControllerProvider)
          .memberships[trackKey(target.track)]
          ?.contains(playlist.id) ??
      false;

  Future<void> _toggle(
    SaveOneTrack target,
    MyPlaylist playlist, {
    required bool included,
  }) async {
    final notice = widget.onNotice;
    final result = await _playlists.setMembership(
      playlist,
      target.track,
      included: included,
    );
    if (result != null) reportPlaylistResult(notice, result);
  }

  Future<void> _save(SaveManyTracks target, List<MyPlaylist> shown) async {
    final chosen = [
      for (final playlist in shown)
        if (_targets.contains(playlist.id)) playlist,
    ];
    if (chosen.isEmpty || _saving) return;
    final notice = widget.onNotice;
    final playlists = _playlists;
    setState(() => _saving = true);
    final results = await playlists.copyTracks(
      target.from,
      target.tracks,
      chosen,
    );
    // 提示一次只显示一条，后一条会盖掉前一条：合成一条，按最严重的那种显示。
    final summary = copySummary(results, target.tracks.length);
    if (summary.isNotEmpty) {
      final kinds = {for (final (kind, _) in summary) kind};
      final kind = kinds.contains(ToastKind.failure)
          ? ToastKind.failure
          : kinds.contains(ToastKind.warning)
          ? ToastKind.warning
          : ToastKind.success;
      notice(kind, [for (final (_, text) in summary) text].join('\n'));
    }
    if (mounted) dismissSheet(context);
  }

  void _created(MyPlaylist playlist) {
    final target = widget.target;
    setState(() {
      _creating = false;
      if (target is SaveManyTracks) _targets.add(playlist.id);
    });
    if (target is SaveOneTrack) {
      unawaited(_toggle(target, playlist, included: true));
    }
    _focusAfterFrame(_rowFocus(playlist.id));
  }

  // 表单比列表短：从长列表末尾点开时，原来的滚动位置会让它落在可见范围之外。
  void _startCreating() {
    setState(() => _creating = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: AlistenDurations.of(context, AlistenDurations.short),
        ),
      );
    });
  }

  void _cancelCreating() {
    setState(() => _creating = false);
    _focusAfterFrame(_newPlaylist);
  }

  // 新歌单排在最后，“新建歌单”也在末尾，列表长时都可能在面板的可见范围之外。
  void _focusAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      final row = node.context;
      if (row == null) return;
      unawaited(
        Scrollable.ensureVisible(
          row,
          alignment: 0.5,
          duration: AlistenDurations.of(context, AlistenDurations.short),
        ),
      );
    });
  }

  // 顺序在第一次显示列表时冻结：保存会推进更新时间，实时排序会让刚勾选的歌单
  // 跳走。之后才出现的歌单（比如刚新建的）排在最后。
  List<MyPlaylist> _ordered(List<MyPlaylist> playlists) {
    final sorted = sortPlaylists(playlists, _newestFirst);
    final order = _order ??= [for (final playlist in sorted) playlist.id];
    final known = order.toSet();
    final byId = {for (final playlist in playlists) playlist.id: playlist};
    return [
      for (final id in order) ?byId[id],
      for (final playlist in sorted)
        if (!known.contains(playlist.id)) playlist,
    ];
  }

  @override
  Widget build(BuildContext context) {
    dismissOnOwnerChange(ref, context);
    ref.listen(
      myPlaylistsControllerProvider.select((list) => list.playlists != null),
      (_, loaded) {
        // 监听可能在构建期间触发，此时不能 setState。
        if (loaded) unawaited(Future.microtask(_readMembershipIfMissing));
      },
    );
    // 面板在根导航器上，链接或通知可能换掉下面的页面：面板自己 watch，控制器
    // 才会在面板打开期间一直活着。
    final list = ref.watch(myPlaylistsControllerProvider);
    final target = widget.target;
    final playlists = list.playlists;
    final key = target is SaveOneTrack ? trackKey(target.track) : null;
    final ticked = key == null ? null : list.memberships[key];
    final error = (playlists == null ? list.error : null) ?? _membershipError;
    final motion = AlistenDurations.of(context, AlistenDurations.short);
    final Widget body;
    var titled = true;
    if (list.guest) {
      body = Padding(
        key: const ValueKey('guest'),
        padding: const EdgeInsets.only(top: AlistenSpacing.md),
        child: PlaylistGuestPrompt(
          message: '注册或登录之后就能把歌保存到歌单。',
          onOpenAccount: () {
            dismissSheet(context);
            widget.onOpenAccount();
          },
        ),
      );
    } else if (error != null) {
      body = PlaylistReadFailure(
        key: const ValueKey('failure'),
        message: error,
        onRetry: _retry,
      );
    } else if (playlists == null ||
        _listPending ||
        (key != null && (_membershipPending || ticked == null))) {
      body = const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.symmetric(vertical: AlistenSpacing.xxl),
        child: PlaylistLoading(),
      );
    } else if (_creating) {
      titled = false;
      body = PlaylistNameForm<MyPlaylist>(
        key: const ValueKey('create'),
        title: '新建歌单',
        confirmLabel: '创建',
        busyLabel: '创建',
        confirmIcon: Icons.add_rounded,
        onSubmit: (name) => _playlists.create(name),
        onSucceeded: _created,
        onCancel: _cancelCreating,
      );
    } else {
      body = _choices(target, _ordered(playlists), ticked ?? const {});
    }
    final content = titled
        ? Column(
            key: const ValueKey('titled'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '保存到歌单',
                  style: AlistenTypography.title.copyWith(
                    color: AlistenColors.of(context).onGlass,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: motion,
                transitionBuilder: fadeLeavingInert,
                layoutBuilder: _topAligned,
                child: body,
              ),
            ],
          )
        : body;
    return PopScope(
      canPop: !_saving,
      child: AnimatedResize(
        duration: motion,
        curve: AlistenCurves.standard,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: motion,
          transitionBuilder: fadeLeavingInert,
          layoutBuilder: _topAligned,
          child: content,
        ),
      ),
    );
  }

  Widget _choices(
    SaveTarget target,
    List<MyPlaylist> playlists,
    Set<String> ticked,
  ) {
    final colors = AlistenColors.of(context);
    final many = target is SaveManyTracks ? target : null;
    final shown = [
      for (final playlist in playlists)
        if (playlist.id != many?.from.id) playlist,
    ];
    final anyChosen = shown.any((playlist) => _targets.contains(playlist.id));
    final subtitle = switch (target) {
      SaveOneTrack(:final title) => title.isEmpty ? null : title,
      SaveManyTracks(:final tracks) => '已选 ${tracks.length} 首',
    };
    return Column(
      key: const ValueKey('choices'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subtitle != null) ...[
          const SizedBox(height: AlistenSpacing.xxs),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AlistenTypography.secondary.copyWith(
              color: colors.onGlassMuted,
            ),
          ),
        ],
        const SizedBox(height: AlistenSpacing.md),
        for (final playlist in shown)
          _Choice(
            key: ValueKey(playlist.id),
            playlist: playlist,
            checked: many == null
                ? ticked.contains(playlist.id)
                : _targets.contains(playlist.id),
            focusNode: _rowFocus(playlist.id),
            onToggle: _saving
                ? null
                : switch (target) {
                    // 在点击时读勾选：同一帧里连点两次也要各自取反。
                    final SaveOneTrack one => () => unawaited(
                      _toggle(
                        one,
                        playlist,
                        included: !_includes(one, playlist),
                      ),
                    ),
                    SaveManyTracks() => () => setState(() {
                      if (!_targets.remove(playlist.id)) {
                        _targets.add(playlist.id);
                      }
                    }),
                  },
          ),
        _NewPlaylistRow(
          focusNode: _newPlaylist,
          onPressed: _saving ? null : _startCreating,
        ),
        if (many != null) ...[
          const SizedBox(height: AlistenSpacing.lg),
          PillButton(
            label: '保存',
            icon: Icons.check_rounded,
            large: true,
            expand: true,
            busy: _saving,
            onPressed: !anyChosen || _saving
                ? null
                : () => unawaited(_save(many, shown)),
          ),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.playlist,
    required this.checked,
    required this.focusNode,
    required this.onToggle,
    super.key,
  });

  final MyPlaylist playlist;
  final bool checked;
  final FocusNode focusNode;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return MergeSemantics(
      child: Semantics(
        checked: checked,
        child: Pressable(
          focusNode: focusNode,
          onPressed: onToggle,
          button: false,
          semanticLabel: '${playlist.name}，${playlist.trackCount} 首',
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AlistenSizes.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AlistenSpacing.xs,
                ),
                child: Row(
                  children: [
                    PlaylistCover(
                      url: playlist.coverUrl,
                      favorites: playlist.favorites,
                      size: AlistenSizes.listAvatar,
                    ),
                    const SizedBox(width: AlistenSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PlaylistName(
                            name: playlist.name,
                            favorites: playlist.favorites,
                            style: AlistenTypography.bodyStrong.copyWith(
                              color: colors.onGlass,
                            ),
                          ),
                          Text(
                            '${playlist.trackCount} 首',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AlistenTypography.secondary.copyWith(
                              color: colors.onGlassMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AlistenSpacing.sm),
                    Icon(
                      checked
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: AlistenSizes.icon,
                      color: checked ? colors.success : colors.onGlassMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewPlaylistRow extends StatelessWidget {
  const _NewPlaylistRow({required this.focusNode, required this.onPressed});

  final FocusNode focusNode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Pressable(
      focusNode: focusNode,
      onPressed: onPressed,
      semanticLabel: '新建歌单',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlistenSizes.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AlistenSpacing.xs),
            child: Row(
              children: [
                Container(
                  width: AlistenSizes.listAvatar,
                  height: AlistenSizes.listAvatar,
                  decoration: BoxDecoration(
                    color: colors.glassFill,
                    borderRadius: BorderRadius.circular(AlistenRadii.sm),
                    border: Border.all(color: colors.glassStroke),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: AlistenSizes.iconSm,
                    color: colors.onGlass,
                  ),
                ),
                const SizedBox(width: AlistenSpacing.sm),
                Expanded(
                  child: Text(
                    '新建歌单',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AlistenTypography.bodyStrong.copyWith(
                      color: colors.onGlass,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
