import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

final class SelectOption<T> {
  const SelectOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 从几项里选一项：按钮上是当前选项和上下箭头，点开是从按钮长出的菜单，当前
/// 项打勾。读屏读作“[label]，按钮，当前选项”，并说明是否展开。
class SelectMenuButton<T> extends StatelessWidget {
  const SelectMenuButton({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String label;
  final List<SelectOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final current = options
        .where((option) => option.value == selected)
        .firstOrNull;
    return ActionMenuButton(
      semanticLabel: label,
      // 名称、当前项、点按和展开状态合成一个读屏节点。
      trigger: (open, toggle) => MergeSemantics(
        child: Semantics(
          value: current?.label,
          child: Pressable(
            onPressed: toggle,
            semanticLabel: label,
            expanded: open,
            focusRadius: BorderRadius.circular(AlistenRadii.pill),
            // 菜单从按钮长出、缩回就是反馈；再叠按压的灰底，菜单收起后它
            // 还留在选中的值后面。
            ink: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AlistenSizes.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlistenSpacing.xs,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          current?.label ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AlistenTypography.body.copyWith(
                            color: colors.onGlassMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: AlistenSpacing.xxs),
                      Icon(
                        AlistenIcons.caretUpDown,
                        size: AlistenSizes.iconSm,
                        color: colors.onGlassMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      entries: [
        for (final option in options)
          ActionMenuEntry(
            label: option.label,
            icon: option.icon,
            checked: option.value == selected,
            onSelected: () {
              if (option.value != selected) onChanged(option.value);
            },
          ),
      ],
    );
  }
}
