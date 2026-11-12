import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/lyric_timing.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lyrics/application/lyric_clock.dart';
import 'package:alisten/features/lyrics/application/lyrics_controller.dart';
import 'package:alisten/features/lyrics/application/screen_awake.dart';
import 'package:alisten/features/lyrics/presentation/lyric_line_layout.dart';
import 'package:alisten/features/lyrics/presentation/lyric_motion.dart';
import 'package:alisten/features/lyrics/presentation/lyric_snapshots.dart';
import 'package:alisten/features/lyrics/presentation/render_lyric_line.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/visible_frames.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _holdAfterDrag = Duration(seconds: 3);

// 用定时器而非 Ticker：Ticker 按屏幕刷新率出帧，120 Hz 屏上点亮歌词时要多画一倍。
const _frameInterval = Duration(milliseconds: 16);

// 强调字唱完后还要回落。
const _settleAfterLastWordMs = 2000;

// 换行时跳到下一行要有最短时长，否则行距一跳就像闪了一下。
const _shortestLineChangeMs = 350;

const _rowHeightEm = 1.3;

/// 歌词跟随本机播放位置，只在播放中前进；拖动后在停下的位置保留
/// [_holdAfterDrag]，再回到当前行。
///
/// 逐帧的变化都走绘制阶段：列表不重建，只有当前行和过渡中的行重绘。
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView>
    with WidgetsBindingObserver, VisibleFrames {
  final _clock = LyricFrameClock();
  final _motion = LyricMotion();
  final _snapshots = LyricSnapshotCache();
  final _position = LyricClock();
  late final _screen = ref.read(screenAwakeProvider);
  bool _holdingScreen = false;

  bool _started = false;
  List<LyricLine> _lines = const [];
  LyricTimeline _timeline = LyricTimeline(const []);
  // 每行一个 key，无论其他行多高都能找到当前行实际布局的位置。
  List<GlobalKey> _keys = const [];
  PlaybackIdentity? _playback;
  int _focus = -1;

  bool _dragging = false;
  Timer? _resume;
  bool _resuming = false;
  bool _alignQueued = false;

  Timer? _frames;
  Timer? _nextEvent;
  bool _frameQueued = false;
  bool _smoothShown = true;

  LyricTextStyles? _styles;
  double? _width;
  double _contentInset = 0;

  bool get _smooth => !animationsRemoved && !keyboardUp;
  bool get _scrolling => _dragging || _resume != null;

  bool get _playing {
    return ref.read(playbackControllerProvider).status ==
        LocalPlaybackStatus.playing;
  }

  // 应用在后台时引擎不出帧，定时器要在这里停，等不到下一帧。
  @override
  void visibleFramesChanged() {
    if (!_started) return;
    _arm();
    if (onScreen) _requestFrame();
  }

  @override
  void dispose() {
    if (_holdingScreen) _screen.release();
    _resume?.cancel();
    _frames?.cancel();
    _nextEvent?.cancel();
    _clock.dispose();
    _motion.dispose();
    _snapshots.clear();
    super.dispose();
  }

  void _begin(List<LyricLine> lines, PlaybackIdentity? playback) {
    final anew = !_started || playback != _playback;
    // 中途打开或换了歌词时，即使暂停也以当前位置所在行为当前行；新一次播放在
    // 真正开播前按歌曲开头计算，此时读到的还是上一首的位置。
    final atPosition = !anew || !_started || _playing;
    _keys = List.generate(lines.length, (_) => GlobalKey());
    _started = true;
    _lines = lines;
    _timeline = LyricTimeline(lines);
    _playback = playback;
    if (anew) {
      // 旧播放的滚动视图已销毁，未完成的拖动收不到结束通知，新播放从头跟随。
      // 同一次播放换歌词时，滚动视图和用户正在进行的操作保持不变。
      _dragging = false;
      _resume?.cancel();
      _resume = null;
    }
    final positionMs = atPosition ? ref.read(livePositionProvider)() : 0;
    // 暂停时换了歌，恢复时位置已在歌曲中段，要算作跳转。
    _position.startAt(positionMs);
    _focus = _timeline.focusAt(positionMs);
    _clock.tick(positionMs: positionMs, nowSeconds: _clock.nowSeconds);
    _motion.configure(lines.length);
    _snapshots.clear();
    _queueAlign();
    _requestFrame();
  }

  void _onPlayback(LocalPlaybackState? _, LocalPlaybackState next) {
    if (next.status == LocalPlaybackStatus.playing && onScreen) {
      _requestFrame();
    } else {
      _arm();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _resume?.cancel();
      _resume = null;
      setState(() => _dragging = true);
      _requestFrame();
    } else if (notification is ScrollEndNotification && _dragging) {
      setState(() {
        _dragging = false;
        _resume = Timer(_holdAfterDrag, () {
          _resume = null;
          _resuming = true;
          _requestFrame();
        });
      });
      _requestFrame();
    }
    return false;
  }

  void _requestFrame() {
    if (_frameQueued) return;
    _frameQueued = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  // 定时器只决定何时要帧，时间戳取自帧本身：单调且与屏幕同步，滚动和重绘也落在
  // 同一帧内。
  void _onFrame(Duration stamp) {
    _frameQueued = false;
    if (!mounted) return;
    final nowSeconds = stamp.inMicroseconds / Duration.microsecondsPerSecond;
    if (_smoothShown != _smooth) setState(() {});
    var positionMs = _clock.positionMs;
    if (_playing) {
      final sample = _position.advance(ref.read(livePositionProvider)());
      positionMs = sample.positionMs;
      final focus = _timeline.focusAt(positionMs);
      if (focus != _focus) {
        setState(() => _focus = focus);
        if (!_scrolling && !_resuming) {
          _follow(nowSeconds: nowSeconds, stagger: !sample.jumped);
        }
      }
    }
    if (_resuming) {
      _resuming = false;
      setState(() {});
      _follow(nowSeconds: nowSeconds, stagger: false);
    }
    _clock.tick(positionMs: positionMs, nowSeconds: nowSeconds);
    _motion.advance(nowSeconds);
    // 行在本帧构建时才声明自己要过渡。
    SchedulerBinding.instance.addPostFrameCallback((_) => _arm());
  }

  void _arm() {
    _nextEvent?.cancel();
    _nextEvent = null;
    if (mounted) _syncScreen();
    if (!mounted || !onScreen) {
      _frames?.cancel();
      _frames = null;
      return;
    }
    final positionMs = _clock.positionMs;
    final continuous =
        _clock.busy ||
        _motion.active ||
        (_playing && _smooth && _animating(positionMs));
    if (continuous) {
      _frames ??= Timer.periodic(_frameInterval, (_) => _requestFrame());
      return;
    }
    _frames?.cancel();
    _frames = null;
    if (!_playing) return;
    var nextMs = _timeline.nextFocusChangeMs(positionMs);
    if (!_smooth) {
      final wordMs = _nextWordMs(positionMs);
      if (wordMs != null && (nextMs == null || wordMs < nextMs)) {
        nextMs = wordMs;
      }
    }
    if (nextMs == null) return;
    _nextEvent = Timer(
      Duration(milliseconds: math.max(nextMs - positionMs, 1)),
      _requestFrame,
    );
  }

  // 暂停时不留着：人可能已经走开，屏幕一直亮着既耗电又灼屏。
  void _syncScreen() {
    final wanted = onScreen && _playing;
    if (wanted == _holdingScreen) return;
    _holdingScreen = wanted;
    if (wanted) {
      _screen.hold();
    } else {
      _screen.release();
    }
  }

  bool _animating(int positionMs) {
    if (_focus < 0) return false;
    if (_timeline.breakAt(_focus) != null) return true;
    final words = _lines[_focus].words;
    if (words == null) return false;
    return positionMs <= words.last.endMs + _settleAfterLastWordMs;
  }

  int? _nextWordMs(int positionMs) {
    final words = _focus >= 0 ? _lines[_focus].words : null;
    if (words == null) return null;
    for (final word in words) {
      if (word.startMs >= positionMs) return word.startMs + 1;
    }
    return null;
  }

  double get _gapExtent {
    final gap = _focus >= 0 ? _timeline.breakAt(_focus) : null;
    return gap == null ? 0 : lyricBreakHeightEm * (_styles?.em ?? 0);
  }

  // 行的高度不随当前行变化，上一帧的布局仍然有效。
  void _follow({required double nowSeconds, required bool stagger}) {
    final target = _revealOffset();
    if (target == null) return;
    final (:position, :offset) = target;
    final gapRow = _gapExtent > 0 ? _focus : null;
    final from = position.pixels;
    if (!_smooth) {
      _motion
        ..clear()
        ..openGap(gapRow, _gapExtent);
      position.jumpTo(offset);
      return;
    }
    final moved = offset - from;
    final extras = [
      for (var row = 0; row < _keys.length; row++) _motion.extraOf(row),
    ];
    _motion.openGap(gapRow, _gapExtent);
    final range = stagger ? _visibleRows(position, from, offset) : null;
    final index = math.max(_focus, 0);
    final spring = _timeline.springInto(index);
    final remainingMs = _timeline.releaseMs(index) - _clock.positionMs;
    final allowedMs = math.max(remainingMs, _shortestLineChangeMs);
    _motion.shift(
      delta: (row) => moved + extras[row] - _motion.extraOf(row),
      delay: range == null
          ? null
          : (row) => staggerDelay(
              row: row,
              first: range.$1,
              last: range.$2,
              forward: moved >= 0,
            ),
      spring: spring,
      speed: allowedMs < spring.settleMs ? spring.settleMs / allowedMs : 1,
      nowSeconds: nowSeconds,
    );
    position.jumpTo(offset);
  }

  ({ScrollPosition position, double offset})? _revealOffset() {
    if (_keys.isEmpty) return null;
    // 首行开唱前停在中央等待。
    final index = math.max(_focus, 0);
    final context = _keys[index].currentContext;
    final row = context?.findRenderObject();
    if (context == null || row == null) return null;
    final position = Scrollable.of(context).position;
    final reveal = RenderAbstractViewport.of(row).getOffsetToReveal(row, 0.5);
    final offset = reveal.offset + _gapExtent / 2;
    return (
      position: position,
      offset: offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  (int, int)? _visibleRows(ScrollPosition position, double from, double to) {
    final top = math.min(from, to) - _contentInset;
    final bottom =
        math.max(from, to) + position.viewportDimension - _contentInset;
    int? first;
    int? last;
    for (var row = 0; row < _keys.length; row++) {
      final box = _keys[row].currentContext?.findRenderObject();
      if (box is! RenderBox) continue;
      final parentData = box.parentData;
      if (parentData is! BoxParentData) continue;
      final rowTop = parentData.offset.dy;
      if (rowTop + box.size.height < top || rowTop > bottom) continue;
      first ??= row;
      last = row;
    }
    return first == null ? null : (first, last!);
  }

  // 当前行要等本帧布局完成才有位置，所以在帧后对齐。
  void _queueAlign() {
    if (_alignQueued) return;
    _alignQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignQueued = false;
      if (!mounted || _scrolling) return;
      final target = _revealOffset();
      if (target == null) return;
      _motion
        ..clear()
        ..openGap(_gapExtent > 0 ? _focus : null, _gapExtent);
      target.position.jumpTo(target.offset);
    });
  }

  void _resetStyles(LyricTextStyles styles) {
    if (styles == _styles) return;
    _styles = styles;
    _snapshots.clear();
  }

  void _resetWidth(double width) {
    if (width == _width) return;
    final resized = _width != null;
    _width = width;
    if (!resized) return;
    _snapshots.clear();
    _queueAlign();
  }

  // 绘制范围是三屏，每行最多同时缓存两级模糊；放不下时顺序访问会次次未命中。
  void _sizeSnapshots(double viewportHeight) {
    final em = _styles?.em;
    if (em == null || !viewportHeight.isFinite) return;
    final rowHeight = em * _rowHeightEm + 2 * AlistenSpacing.sm;
    final rows = (3 * viewportHeight / rowHeight).ceil();
    _snapshots.capacity = math.max(_snapshots.capacity, 2 * rows);
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(lyricsProvider);
    final playback = ref.watch(nowPlayingProvider.select(_identityOf));
    final colors = AlistenColors.of(context);
    _resetStyles(
      LyricTextStyles(
        main: AlistenTypography.lyric.copyWith(color: colors.onGlass),
        translation: AlistenTypography.lyricTranslation.copyWith(
          color: colors.onGlass,
        ),
        scaler: MediaQuery.textScalerOf(context),
      ),
    );
    if (!_started || !identical(lines, _lines) || playback != _playback) {
      _begin(lines, playback);
    }
    ref.listen(playbackControllerProvider, _onPlayback);
    _smoothShown = _smooth;
    if (lines.every((line) => line.isBlank)) {
      return const EmptyState(
        icon: AlistenIcons.microphoneStage,
        title: '暂无歌词',
      );
    }
    return RepaintBoundary(
      child: EdgeFade(
        top: AlistenSpacing.xxxl,
        bottom: AlistenSpacing.xxxl,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _resetWidth(constraints.maxWidth);
              _sizeSnapshots(constraints.maxHeight);
              _contentInset = constraints.hasBoundedHeight
                  ? constraints.maxHeight / 2
                  : AlistenSpacing.xl;
              return SingleChildScrollView(
                // 每次播放用新的滚动视图，从顶部开始而非停在上一首的位置。
                key: ValueKey(playback),
                // 可能与队列或聊天同时显示（如滑动切换途中、两栏布局），不能
                // 共用 primary 控制器。
                primary: false,
                // 上下各留半个视口，首行和末行也能滚到中央（仅限高度有界时）。
                padding: EdgeInsets.symmetric(vertical: _contentInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < lines.length; index++)
                      _row(index, constraints.maxHeight),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _row(int index, double viewportHeight) {
    final line = _lines[index];
    final focused = index == _focus;
    Widget row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AlistenSpacing.page,
        vertical: line.isBlank ? 0 : AlistenSpacing.sm,
      ),
      child: LyricLineRow(
        index: index,
        line: line,
        gap: _timeline.breakAt(index),
        styles: _styles!,
        phase: focused
            ? LyricLinePhase.focused
            : index < _focus
            ? LyricLinePhase.past
            : LyricLinePhase.upcoming,
        distance: (index - _focus).abs(),
        prepared: index == _focus + 1,
        scrolling: _scrolling,
        smooth: _smooth,
        clock: _clock,
        snapshots: _snapshots,
      ),
    );
    if (!line.isBlank) {
      row = Semantics(
        container: true,
        selected: focused,
        label: switch (line.translation) {
          final translation? => '${line.text}\n$translation',
          null => line.text,
        },
        child: row,
      );
    }
    return _LagBox(
      key: _keys[index],
      row: index,
      motion: _motion,
      viewportHeight: viewportHeight,
      child: EdgeFadeItem(child: RepaintBoundary(child: row)),
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

/// 在绘制阶段按 [LyricMotion] 移动一行，并跳过屏幕外的行：它们不绘制，也就不会
/// 生成模糊快照。偏移计入绘制变换，边缘渐隐才能按行实际的位置计算。
class _LagBox extends SingleChildRenderObjectWidget {
  const _LagBox({
    required this.row,
    required this.motion,
    required this.viewportHeight,
    required Widget super.child,
    super.key,
  });

  final int row;
  final LyricMotion motion;
  final double viewportHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLagBox(row, motion, viewportHeight);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderLagBox renderObject) {
    renderObject
      ..row = row
      ..motion = motion
      ..viewportHeight = viewportHeight;
  }
}

class _RenderLagBox extends RenderProxyBox {
  _RenderLagBox(this.row, this._motion, this.viewportHeight);

  int row;
  double viewportHeight;
  LyricMotion _motion;

  set motion(LyricMotion value) {
    if (identical(value, _motion)) return;
    if (attached) _motion.removeListener(markNeedsPaint);
    _motion = value;
    if (attached) _motion.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _motion.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _motion.offsetOf(row), 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final y = offset.dy + _motion.offsetOf(row);
    final margin = viewportHeight;
    if (y + size.height < -margin || y > viewportHeight + margin) return;
    context.paintChild(child!, Offset(offset.dx, y));
  }
}
