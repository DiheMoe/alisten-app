import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lyrics/application/lyrics_controller.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _holdAfterDrag = Duration(seconds: 3);

const _currentScale = 1.08;

const _fadePerLine = 0.18;
const _minOpacity = 0.25;

/// 歌词跟随本机播放位置，只在播放中前进；拖动后在停下的位置保留
/// [_holdAfterDrag]，再回到当前行。
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  bool _started = false;
  List<LyricLine> _lines = const [];
  // 每行一个 key，无论其他行多高都能找到当前行实际布局的位置。
  List<GlobalKey> _keys = const [];
  PlaybackIdentity? _playback;
  int _index = -1;

  bool _dragging = false;
  Timer? _resume;
  bool _followQueued = false;
  bool _jumpQueued = false;
  Duration _scrollDuration = Duration.zero;

  @override
  void dispose() {
    _resume?.cancel();
    super.dispose();
  }

  void _begin(List<LyricLine> lines, PlaybackIdentity? playback) {
    final local = ref.read(playbackControllerProvider);
    final anew = !_started || playback != _playback;
    // 中途打开或换了歌词时，即使暂停也以当前位置所在行为当前行；新一次播放在
    // 真正开播前没有当前行。
    final atPosition =
        !anew || !_started || local.status == LocalPlaybackStatus.playing;
    _keys = List.generate(lines.length, (_) => GlobalKey());
    _started = true;
    _lines = lines;
    _playback = playback;
    _index = atPosition ? lineIndexAt(lines, local.positionMs) : -1;
    if (anew) {
      // 旧播放的滚动视图已销毁，未完成的拖动收不到结束通知，新播放从头跟随。
      // 同一次播放换歌词时，滚动视图和用户正在进行的操作保持不变。
      _dragging = false;
      _resume?.cancel();
      _resume = null;
    }
    _queueFollow(jump: true);
  }

  void _onPlayback(LocalPlaybackState? _, LocalPlaybackState next) {
    if (next.status != LocalPlaybackStatus.playing) return;
    final index = lineIndexAt(_lines, next.positionMs);
    if (index == _index) return;
    setState(() => _index = index);
    _queueFollow();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
      _resume?.cancel();
      _resume = null;
    } else if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      _resume = Timer(_holdAfterDrag, () {
        _resume = null;
        _follow();
      });
    }
    return false;
  }

  // 当前行要等本帧布局完成才有位置，所以在帧后跟随。
  void _queueFollow({bool jump = false}) {
    _jumpQueued |= jump;
    if (_followQueued) return;
    _followQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followQueued = false;
      final jump = _jumpQueued;
      _jumpQueued = false;
      if (mounted) _follow(jump: jump);
    });
  }

  void _follow({bool jump = false}) {
    if (!mounted || _dragging || _resume != null || _keys.isEmpty) return;
    // 首行开唱前停在中央等待。
    final line = _keys[math.max(_index, 0)].currentContext;
    if (line == null) return;
    // 减少动态效果时时长为零，即直接跳转。
    unawaited(
      Scrollable.ensureVisible(
        line,
        alignment: 0.5,
        duration: jump ? Duration.zero : _scrollDuration,
        curve: AlistenCurves.standard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(lyricsProvider);
    final playback = ref.watch(nowPlayingProvider.select(_identityOf));
    if (!_started || !identical(lines, _lines) || playback != _playback) {
      _begin(lines, playback);
    }
    ref.listen(playbackControllerProvider, _onPlayback);
    _scrollDuration = AlistenDurations.of(context, AlistenDurations.lyricLine);
    if (lines.isEmpty) {
      return const EmptyState(icon: Icons.lyrics_rounded, title: '暂无歌词');
    }
    return RepaintBoundary(
      child: EdgeFade(
        top: AlistenSpacing.xxxl,
        bottom: AlistenSpacing.xxxl,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // 每次播放用新的滚动视图，从顶部开始而非停在上一首的位置。
              key: ValueKey(playback),
              // primary 控制器属于另一个滚动视图，如交叉淡入淡出中的队列。
              primary: false,
              // 上下各留半个视口，首行和末行也能滚到中央（仅限高度有界时）。
              padding: EdgeInsets.symmetric(
                vertical: constraints.hasBoundedHeight
                    ? constraints.maxHeight / 2
                    : AlistenSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < lines.length; index++)
                    EdgeFadeItem(
                      child: _LyricRow(
                        key: _keys[index],
                        text: lines[index].text,
                        distance: (index - _index).abs(),
                        // 当前行的字重及其导致的本行和相邻行折行，要等过渡
                        // 结束才确定。
                        onSettled: index == _index ? _queueFollow : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static PlaybackIdentity? _identityOf(NowPlaying? nowPlaying) {
    if (nowPlaying == null) return null;
    return PlaybackIdentity(
      entryId: nowPlaying.entry.id,
      startedAtMs: nowPlaying.startedAtMs,
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    required this.text,
    required this.distance,
    required this.onSettled,
    super.key,
  });

  final String text;
  final int distance;
  final VoidCallback? onSettled;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox(height: AlistenSpacing.xl);
    final colors = AlistenColors.of(context);
    final duration = AlistenDurations.of(context, AlistenDurations.lyricLine);
    final current = distance == 0;
    final opacity = math.max(_minOpacity, 1 - _fadePerLine * distance);
    final style = current
        ? AlistenTypography.weighted(AlistenTypography.lyric, FontWeight.w800)
        : AlistenTypography.lyric;
    return Semantics(
      selected: current,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AlistenSpacing.page,
          vertical: AlistenSpacing.xs,
        ),
        // 按放大后的尺寸折行，放大时才不会超出边距。
        child: FractionallySizedBox(
          widthFactor: 1 / _currentScale,
          alignment: Alignment.centerLeft,
          child: AnimatedScale(
            scale: current ? _currentScale : 1,
            alignment: Alignment.centerLeft,
            duration: duration,
            curve: AlistenCurves.standard,
            child: AnimatedDefaultTextStyle(
              duration: duration,
              curve: AlistenCurves.standard,
              onEnd: onSettled,
              style: style.copyWith(
                color: colors.onGlass.withValues(alpha: opacity),
                shadows: current ? colors.glowTextShadows : const [],
              ),
              child: Text(text),
            ),
          ),
        ),
      ),
    );
  }
}
