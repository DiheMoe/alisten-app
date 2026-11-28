import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/hover_glow.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/widgets.dart';

final class GlassAction {
  const GlassAction({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;
}

/// 两三个相关的图标按钮并在一枚玻璃胶囊里。
class GlassActionGroup extends StatelessWidget {
  const GlassActionGroup({required this.actions, super.key});

  final List<GlassAction> actions;

  static const _slotWidth = 36.0;
  static const _slotHeight = 30.0;
  static const _inset = 3.0;
  static const _dividerHeight = 14.0;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final colors = AlistenColors.of(context);
    final outer = BorderRadius.circular(AlistenRadii.control);
    final inner = BorderRadius.circular(AlistenRadii.control - _inset);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFill,
        borderRadius: outer,
        border: Border.all(color: colors.glassStroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_inset),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, action) in actions.indexed) ...[
              if (index > 0)
                Container(
                  width: AlistenSizes.hairline,
                  height: _dividerHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  color: colors.glassStroke,
                ),
              Pressable(
                onPressed: action.onPressed,
                semanticLabel: action.semanticLabel,
                focusRadius: inner,
                child: SizedBox(
                  width: _slotWidth,
                  height: _slotHeight,
                  child: Center(
                    child: HoverPop(
                      child: Icon(
                        action.icon,
                        size: AlistenSizes.iconSm,
                        color: colors.onGlass,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
