import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/popover.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

final class ActionMenuEntry {
  const ActionMenuEntry({
    required this.label,
    required this.onSelected,
    this.icon,
    this.danger = false,
    this.enabled = true,
    this.checked,
  });

  /// 为 null 时这一项只有文字，比如从几个数里选一个。
  final IconData? icon;
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
    this.icon = AlistenIcons.dotsThreeBold,
    this.iconSize = AlistenSizes.icon,
    this.trigger,
    this.below = false,
    super.key,
  });

  final String semanticLabel;
  final List<ActionMenuEntry> entries;
  final IconData icon;
  final double iconSize;

  /// 自定义触发控件，参数是菜单是否展开和开关菜单的回调；为 null 时是图标按钮。
  /// 有它时不用 [semanticLabel]：名称和展开状态由它自己提供。
  final Widget Function(bool open, VoidCallback toggle)? trigger;

  /// 为 true 时菜单在按钮下方（放不下时上方）展开，不盖住按钮。
  final bool below;

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
    final trigger = widget.trigger;
    final alignX = _rightward ? -1.0 : 1.0;
    final childY = widget.below
        ? (_upward ? -1.0 : 1.0)
        : (_upward ? 1.0 : -1.0);
    final contentY = _upward ? 1.0 : -1.0;
    return Popover(
      open: _open,
      onClose: _close,
      // 菜单的角对着按钮的同一个角，盖住按钮展开；[below] 时留一条缝，从按钮的
      // 边长出来。
      childAnchor: Alignment(alignX, childY),
      contentAnchor: Alignment(alignX, contentY),
      offset: widget.below
          ? Offset(0, _upward ? -AlistenSpacing.xxs : AlistenSpacing.xxs)
          : Offset.zero,
      padding: _menuPadding,
      pours: !widget.below,
      fromPoint: widget.below,
      content: _MenuList(
        entries: widget.entries,
        onClose: _close,
        minWidth: widget.below && isDesktopPlatform ? _dropdownMinWidth : 0,
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

/// 桌面窗口里在 [child] 上按鼠标右键，在指针处打开菜单。[entries] 为空或不在
/// 桌面上时就是 [child] 本身。
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    required this.entries,
    required this.child,
    super.key,
  });

  final List<ActionMenuEntry> entries;
  final Widget child;

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  Offset? _at;
  bool _open = false;
  bool _upward = false;
  bool _leftward = false;

  void _show(TapUpDetails details) {
    final screen = MediaQuery.sizeOf(context);
    setState(() {
      _at = details.localPosition;
      _upward = details.globalPosition.dy > screen.height / 2;
      _leftward = details.globalPosition.dx > screen.width / 2;
      _open = true;
    });
  }

  void _close() {
    if (_open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform || widget.entries.isEmpty) return widget.child;
    final at = _at;
    // 菜单的一个角落在指针上，朝窗口里空的那一边展开。
    final corner = Alignment(_leftward ? 1 : -1, _upward ? 1 : -1);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: _show,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (at != null)
            Positioned(
              left: at.dx,
              top: at.dy,
              child: Popover(
                open: _open,
                onClose: _close,
                childAnchor: Alignment.topLeft,
                contentAnchor: corner,
                padding: _menuPadding,
                content: _MenuList(entries: widget.entries, onClose: _close),
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

EdgeInsets get _menuPadding =>
    EdgeInsets.all(isDesktopPlatform ? AlistenSpacing.xxs : AlistenSpacing.xs);

const _dropdownMinWidth = 160.0;

// 菜单与最长的一项同宽，各项整行可点。
class _MenuList extends StatelessWidget {
  const _MenuList({
    required this.entries,
    required this.onClose,
    this.minWidth = 0,
  });

  final List<ActionMenuEntry> entries;
  final VoidCallback onClose;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, entry) in entries.indexed) ...[
              if (isDesktopPlatform &&
                  index > 0 &&
                  entry.danger &&
                  !entries[index - 1].danger)
                Container(
                  height: AlistenSizes.hairline,
                  margin: const EdgeInsets.symmetric(
                    horizontal: AlistenSpacing.sm,
                    vertical: AlistenSpacing.xxs,
                  ),
                  color: colors.glassStroke,
                ),
              _MenuItem(
                entry: entry,
                ink: entry.danger ? colors.danger : colors.onGlass,
                onPressed: entry.enabled
                    ? () {
                        onClose();
                        entry.onSelected();
                      }
                    : null,
              ),
            ],
          ],
        ),
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
    final compact = isDesktopPlatform;
    final colors = AlistenColors.of(context);
    return Pressable(
      onPressed: onPressed,
      selected: entry.checked,
      inMutuallyExclusiveGroup: entry.checked != null,
      hoverColor: entry.danger ? colors.danger : null,
      // 桌面窗口里鼠标指着的一项亮起来，圆角套在面板的圆角里面。
      focusRadius: BorderRadius.circular(
        compact ? AlistenRadii.md - AlistenSpacing.xxs : AlistenRadii.sm,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: compact
              ? AlistenSizes.rowAction
              : AlistenSizes.minTouchTarget,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AlistenSpacing.sm,
            vertical: compact ? AlistenSpacing.xxs : AlistenSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.icon case final icon?) ...[
                Icon(icon, size: AlistenSizes.iconSm, color: ink),
                SizedBox(
                  width: compact ? AlistenSpacing.xs : AlistenSpacing.sm,
                ),
              ],
              // 菜单与最长的一项同宽，勾在每一行的末端对齐。
              Expanded(
                child: Text(
                  entry.label,
                  style:
                      (compact
                              ? AlistenTypography.weighted(
                                  AlistenTypography.secondary,
                                  FontWeight.w600,
                                )
                              : AlistenTypography.bodyStrong)
                          .copyWith(color: ink),
                ),
              ),
              if (entry.checked ?? false) ...[
                const SizedBox(width: AlistenSpacing.sm),
                Icon(
                  AlistenIcons.checkBold,
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
