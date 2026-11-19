import 'dart:math' as math;

import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/room/song_buttons.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 播放器没有标签：再次点选当前模式时，以 [RoomMode.player] 回调 [onSelect]。
class RoomModeBar extends StatelessWidget {
  const RoomModeBar({
    required this.mode,
    required this.position,
    required this.onSelect,
    required this.onSearch,
    required this.onPickFromPlaylists,
    super.key,
  });

  static final modes = List<RoomMode>.unmodifiable([
    for (final (mode, _, _) in _tabs) mode,
  ]);

  final RoomMode mode;

  /// 滑块的位置，以 [modes] 中的序号计，可为小数。只在绘制时读取。
  final ValueListenable<double> position;
  final ValueChanged<RoomMode> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onPickFromPlaylists;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.sm,
        AlistenSpacing.xs,
        AlistenSpacing.sm,
        AlistenSpacing.sm,
      ),
      // 两个点歌按钮和模式条一样高。
      child: Row(
        children: [
          PickFromPlaylistsButton(
            diameter: PillButton.heightOf(context, large: true),
            onPressed: onPickFromPlaylists,
          ),
          const SizedBox(width: AlistenSpacing.sm),
          Expanded(
            child: _ModeTabs(
              mode: mode,
              position: position,
              onSelect: (chosen) =>
                  onSelect(chosen == mode ? RoomMode.player : chosen),
            ),
          ),
          const SizedBox(width: AlistenSpacing.sm),
          SearchSongsButton(
            diameter: PillButton.heightOf(context, large: true),
            onPressed: onSearch,
          ),
        ],
      ),
    );
  }
}

const _tabs = [
  (RoomMode.lyrics, AlistenIcons.microphoneStage, '歌词'),
  (RoomMode.queue, AlistenIcons.queue, '队列'),
  (RoomMode.chat, AlistenIcons.chatsCircle, '聊天'),
];

const _tabPadding = AlistenSpacing.xs;

const _stroke = 1.0;

// 选中的格子展开、露出文字，其余收起只剩图标；减速停稳，不冲过头。
const _expand = Duration(milliseconds: 300);
const Curve _expandCurve = Curves.easeOutCubic;

/// 每个格子此刻有多“选中”：0 只有图标，1 图标和文字都在。
List<double> _selection(int chosen) => [
  for (var index = 0; index < _tabs.length; index++)
    index == chosen ? 1.0 : 0.0,
];

/// 模式条里各格的宽度：没选中的平分剩下的宽度，选中的多出文字那么宽。
final class _Layout {
  _Layout({required this.width, required this.labels, required this.selection});

  final double width;

  /// 各格文字连同它和图标之间的间距有多宽；放不下文字时为 null。
  final List<double>? labels;
  final List<double> selection;

  List<double> get widths {
    final labels = this.labels;
    final extras = [
      for (var index = 0; index < _tabs.length; index++)
        labels == null ? 0.0 : labels[index] * selection[index],
    ];
    final base =
        (width - extras.fold(0.0, (sum, extra) => sum + extra)) / _tabs.length;
    return [for (final extra in extras) base + extra];
  }

  /// 第 [index] 格在模式条里的位置，[height] 是格子的高度。
  Rect tab(int index, double height) {
    final widths = this.widths;
    var left = 0.0;
    for (var before = 0; before < index; before++) {
      left += widths[before];
    }
    return Rect.fromLTWH(left, 0, widths[index], height);
  }

  /// 滑块在 [position]（以格子序号计，可为小数）时的位置。
  Rect thumb(double position, double height) {
    final at = position.clamp(0.0, _tabs.length - 1.0);
    final from = at.floor();
    final to = math.min(from + 1, _tabs.length - 1);
    return Rect.lerp(tab(from, height), tab(to, height), at - from)!;
  }
}

class _ModeTabs extends StatefulWidget {
  const _ModeTabs({
    required this.mode,
    required this.position,
    required this.onSelect,
  });

  final RoomMode mode;
  final ValueListenable<double> position;
  final ValueChanged<RoomMode> onSelect;

  static TextStyle _labelStyle({required bool selected}) =>
      AlistenTypography.weighted(
        AlistenTypography.secondary,
        selected ? FontWeight.w700 : FontWeight.w600,
      );

  @override
  State<_ModeTabs> createState() => _ModeTabsState();
}

class _ModeTabsState extends State<_ModeTabs>
    with SingleTickerProviderStateMixin {
  late final _change = AnimationController(
    vsync: this,
    duration: _expand,
    value: 1,
  );
  late List<double> _from = _selection(_chosen);
  late List<double> _to = _from;

  int get _chosen => RoomModeBar.modes.indexOf(widget.mode);

  List<double> get _now {
    final t = _expandCurve.transform(_change.value);
    return [
      for (var index = 0; index < _tabs.length; index++)
        _from[index] + (_to[index] - _from[index]) * t,
    ];
  }

  @override
  void didUpdateWidget(_ModeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == widget.mode) return;
    _from = _now;
    _to = _selection(_chosen);
    if (MediaQuery.disableAnimationsOf(context)) {
      _change.value = 1;
    } else {
      _change.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }

  // 选中的格子要放得下图标和文字，其余格子至少放得下图标；不然都只显示图标。
  List<double>? _labels(BuildContext context, double width) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    final labels = [
      for (final (_, _, text) in _tabs)
        (painter
                  ..text = TextSpan(
                    text: text,
                    style: _ModeTabs._labelStyle(selected: true),
                  )
                  ..layout())
                .width +
            AlistenSpacing.xxs,
    ];
    painter.dispose();
    const icon = AlistenSizes.iconSm + 2 * _tabPadding;
    final widest = labels.reduce(math.max);
    return (width - widest) / _tabs.length >= icon ? labels : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final pill = BorderRadius.circular(AlistenRadii.control);
    final chosen = _chosen;
    final motion = AlistenDurations.of(context, AlistenDurations.medium);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 须与胶囊边框宽度和下方 `Padding` 的内边距一致。
        const inset = _stroke + AlistenSpacing.xxs;
        final width = constraints.maxWidth - 2 * inset;
        final labels = _labels(context, width);
        _Layout layout() =>
            _Layout(width: width, labels: labels, selection: _now);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassFill,
            borderRadius: pill,
            border: Border.all(color: colors.glassStroke, width: _stroke),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AlistenSpacing.xxs),
            child: Stack(
              children: [
                Positioned.fill(
                  // 切到播放器时滑块留在原位淡出。
                  child: AnimatedOpacity(
                    opacity: chosen < 0 ? 0 : 1,
                    duration: motion,
                    curve: AlistenCurves.standard,
                    child: CustomPaint(
                      key: const ValueKey('mode-thumb'),
                      painter: _ThumbPainter(
                        position: widget.position,
                        change: _change,
                        layout: layout,
                        color: colors.selectedFill,
                        radius: pill,
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _change,
                  builder: (context, _) {
                    final now = layout();
                    final widths = now.widths;
                    return Row(
                      children: [
                        for (final (index, (mode, icon, label))
                            in _tabs.indexed)
                          SizedBox(
                            width: widths[index],
                            child: _Tab(
                              icon: icon,
                              label: label,
                              reveal: labels == null ? 0 : now.selection[index],
                              selected: index == chosen,
                              onPressed: () => widget.onSelect(mode),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 位置可能在构建和布局期间改变（如内容随路由跳页），只能在绘制时移动滑块。
// 拖动途中也因此只重绘滑块，不重建模式条。
class _ThumbPainter extends CustomPainter {
  _ThumbPainter({
    required this.position,
    required Animation<double> change,
    required this.layout,
    required this.color,
    required this.radius,
  }) : super(repaint: Listenable.merge([position, change]));

  final ValueListenable<double> position;
  final _Layout Function() layout;
  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = layout().thumb(position.value, size.height);
    canvas.drawRRect(radius.toRRect(rect), Paint()..color = color);
  }

  // 重建时宽度可能变了（如转屏），几何每次重算。
  @override
  bool shouldRepaint(_ThumbPainter oldDelegate) => true;
}

/// 文字从图标旁边滑出：[reveal] 为 0 时只有图标，为 1 时文字完全露出。
class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.reveal,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final double reveal;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final ink = selected ? colors.onGlass : colors.onGlassMuted;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      selected: selected,
      focusRadius: BorderRadius.circular(AlistenRadii.control),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: AlistenSizes.iconSm, color: ink),
            Flexible(
              child: ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: reveal,
                  child: Opacity(
                    opacity: reveal,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AlistenSpacing.xxs,
                      ),
                      child: ExcludeSemantics(
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: _ModeTabs._labelStyle(selected: true)
                              .copyWith(color: ink),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
