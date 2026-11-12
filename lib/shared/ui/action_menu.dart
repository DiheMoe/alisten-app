import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/popover.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

final class ActionMenuEntry {
  const ActionMenuEntry({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.danger = false,
    this.enabled = true,
    this.checked,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool danger;
  final bool enabled;

  /// 不为 null 时是单选项，选中的打勾。
  final bool? checked;
}

/// 菜单朝按钮所在位置空间较大的一侧展开：按钮在屏幕下半部分时向上，在左半部分时
/// 与按钮左边对齐、向右展开，免得超出屏幕。选中一项时先收起菜单。
class ActionMenuButton extends StatefulWidget {
  const ActionMenuButton({
    required this.semanticLabel,
    required this.entries,
    this.icon = Icons.more_horiz_rounded,
    this.iconSize = AlistenSizes.icon,
    this.trigger,
    super.key,
  });

  final String semanticLabel;
  final List<ActionMenuEntry> entries;
  final IconData icon;
  final double iconSize;

  /// 自定义触发控件，参数是菜单是否展开和开关菜单的回调；为 null 时是图标按钮。
  /// 有它时不用 [semanticLabel]：名称和展开状态由它自己提供。
  final Widget Function(bool open, VoidCallback toggle)? trigger;

  @override
  State<ActionMenuButton> createState() => _ActionMenuButtonState();
}

class _ActionMenuButtonState extends State<ActionMenuButton> {
  bool _open = false;
  bool _upward = false;
  bool _rightward = false;

  void _toggle() {
    if (!_open) {
      final box = context.findRenderObject();
      final center = box is RenderBox && box.hasSize
          ? box.localToGlobal(box.size.center(Offset.zero))
          : null;
      final screen = MediaQuery.sizeOf(context);
      _upward = center != null && center.dy > screen.height / 2;
      _rightward = center != null && center.dx < screen.width / 2;
    }
    setState(() => _open = !_open);
  }

  void _close() {
    if (_open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final trigger = widget.trigger;
    return Popover(
      open: _open,
      onClose: _close,
      childAnchor: Alignment(_rightward ? -1 : 1, _upward ? -1 : 1),
      contentAnchor: Alignment(_rightward ? -1 : 1, _upward ? 1 : -1),
      offset: Offset(0, _upward ? -AlistenSpacing.xxs : AlistenSpacing.xxs),
      // 菜单与最长的一项同宽，各项整行可点。
      content: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in widget.entries)
              _MenuItem(
                entry: entry,
                ink: entry.danger ? colors.danger : colors.onGlass,
                onPressed: entry.enabled
                    ? () {
                        _close();
                        entry.onSelected();
                      }
                    : null,
              ),
          ],
        ),
      ),
      child: trigger != null
          ? trigger(_open, _toggle)
          : IconCircleButton(
              icon: widget.icon,
              semanticLabel: widget.semanticLabel,
              style: IconCircleButtonStyle.plain,
              iconSize: widget.iconSize,
              expanded: _open,
              onPressed: _toggle,
            ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.entry,
    required this.ink,
    required this.onPressed,
  });

  final ActionMenuEntry entry;
  final Color ink;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onPressed,
      selected: entry.checked,
      inMutuallyExclusiveGroup: entry.checked != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.sm,
            vertical: AlistenSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: AlistenSizes.iconSm, color: ink),
              const SizedBox(width: AlistenSpacing.sm),
              Flexible(
                child: Text(
                  entry.label,
                  style: AlistenTypography.bodyStrong.copyWith(color: ink),
                ),
              ),
              if (entry.checked ?? false) ...[
                const SizedBox(width: AlistenSpacing.sm),
                Icon(
                  Icons.check_rounded,
                  size: AlistenSizes.iconSm,
                  color: ink,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
