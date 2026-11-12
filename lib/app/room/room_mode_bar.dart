import 'package:alisten/app/room/room_mode.dart';
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
    required this.onAddSong,
    super.key,
  });

  static final modes = List<RoomMode>.unmodifiable([
    for (final (mode, _, _) in _tabs) mode,
  ]);

  final RoomMode mode;

  /// 滑块的位置，以 [modes] 中的序号计，可为小数。只在绘制时读取。
  final ValueListenable<double> position;
  final ValueChanged<RoomMode> onSelect;
  final VoidCallback onAddSong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.sm,
        AlistenSpacing.xs,
        AlistenSpacing.sm,
        AlistenSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTabs(
              mode: mode,
              position: position,
              onSelect: (chosen) =>
                  onSelect(chosen == mode ? RoomMode.player : chosen),
            ),
          ),
          const SizedBox(width: AlistenSpacing.sm),
          PillButton(
            label: '点歌',
            icon: AlistenIcons.plusBold,
            large: true,
            onPressed: onAddSong,
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

enum _TabContent { iconAndLabel, label, icon }

const _tabPadding = AlistenSpacing.xs;

const _stroke = 1.0;

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({
    required this.mode,
    required this.position,
    required this.onSelect,
  });

  final RoomMode mode;
  final ValueListenable<double> position;
  final ValueChanged<RoomMode> onSelect;

  _TabContent _fit(BuildContext context, double tabWidth) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var label = 0.0;
    for (final (_, _, text) in _tabs) {
      painter
        ..text = TextSpan(text: text, style: _labelStyle(selected: true))
        ..layout();
      if (painter.width > label) label = painter.width;
    }
    painter.dispose();
    const padding = 2 * _tabPadding;
    if (tabWidth >=
        padding + AlistenSizes.iconSm + AlistenSpacing.xxs + label) {
      return _TabContent.iconAndLabel;
    }
    if (tabWidth >= padding + label) return _TabContent.label;
    return _TabContent.icon;
  }

  static TextStyle _labelStyle({required bool selected}) =>
      AlistenTypography.weighted(
        AlistenTypography.secondary,
        selected ? FontWeight.w700 : FontWeight.w600,
      );

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final pill = BorderRadius.circular(AlistenRadii.pill);
    final chosen = RoomModeBar.modes.indexOf(mode);
    final motion = AlistenDurations.of(context, AlistenDurations.medium);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 须与胶囊边框宽度和下方 `Padding` 的内边距一致。
        const inset = _stroke + AlistenSpacing.xxs;
        final content = _fit(
          context,
          (constraints.maxWidth - 2 * inset) / _tabs.length,
        );
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
                    child: Flow(
                      delegate: _ThumbFlow(position),
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.selectedFill,
                            borderRadius: pill,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (index, (mode, icon, label)) in _tabs.indexed)
                      Expanded(
                        child: _Tab(
                          icon: icon,
                          label: label,
                          content: content,
                          selected: index == chosen,
                          onPressed: () => onSelect(mode),
                        ),
                      ),
                  ],
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
class _ThumbFlow extends FlowDelegate {
  _ThumbFlow(this.position) : super(repaint: position);

  final ValueListenable<double> position;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    return BoxConstraints.tightFor(
      width: constraints.maxWidth / _tabs.length,
      height: constraints.maxHeight,
    );
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final at = position.value.clamp(0.0, _tabs.length - 1.0);
    final step = context.size.width / _tabs.length;
    context.paintChild(
      0,
      transform: Matrix4.translationValues(at * step, 0, 0),
    );
  }

  @override
  bool shouldRepaint(_ThumbFlow oldDelegate) =>
      position != oldDelegate.position;
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.content,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final _TabContent content;
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
      focusRadius: BorderRadius.circular(AlistenRadii.pill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _tabPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (content != _TabContent.label)
                Icon(icon, size: AlistenSizes.iconSm, color: ink),
              if (content == _TabContent.iconAndLabel)
                const SizedBox(width: AlistenSpacing.xxs),
              if (content != _TabContent.icon)
                Flexible(
                  child: ExcludeSemantics(
                    child: AnimatedDefaultTextStyle(
                      duration: AlistenDurations.of(
                        context,
                        AlistenDurations.short,
                      ),
                      style: _ModeTabs._labelStyle(selected: selected)
                          .copyWith(color: ink),
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
