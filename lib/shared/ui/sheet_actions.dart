import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/widgets.dart';

/// 面板底部的一组操作，主操作在前。手机上自上而下排、撑满宽度；桌面的对话框里
/// 横排靠右，主操作在最右，一行放不下时回到竖排。
class SheetActions extends StatelessWidget {
  const SheetActions({required this.children, super.key});

  final List<PillButton> children;

  static const _minWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, button) in children.indexed) ...[
            if (index > 0) const SizedBox(height: AlistenSpacing.xs),
            button.sized(large: button.large, expand: true),
          ],
        ],
      );
    }
    return OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: AlistenSpacing.xs,
      overflowAlignment: OverflowBarAlignment.end,
      overflowDirection: VerticalDirection.up,
      overflowSpacing: AlistenSpacing.xs,
      children: [
        for (final button in children.reversed)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _minWidth),
            child: button.sized(large: false, expand: false),
          ),
      ],
    );
  }
}
