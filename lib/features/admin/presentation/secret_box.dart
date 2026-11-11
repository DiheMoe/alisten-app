import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';

// 显示只出现一次的秘密（API Key 或重置后的密码）。选择菜单只保留“全选”和
// “复制”，菜单复制和键盘复制都交给 [onCopy]：默认复制不带敏感标记，分享、查询、
// 搜索网页和文本处理会把秘密交给其他应用。读屏只读出秘密，不提供默认的复制动作。
class SecretBox extends StatelessWidget {
  const SecretBox({required this.secret, required this.onCopy, super.key});

  final String secret;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFill,
        borderRadius: BorderRadius.circular(AlistenRadii.sm),
        border: Border.all(color: colors.glassStroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AlistenSpacing.sm),
        child: Semantics(
          container: true,
          label: secret,
          child: ExcludeSemantics(
            child: Actions(
              actions: {
                CopySelectionTextIntent:
                    CallbackAction<CopySelectionTextIntent>(
                      onInvoke: (_) {
                        onCopy();
                        return null;
                      },
                    ),
              },
              child: SelectableText(
                secret,
                style: AlistenTypography.bodyStrong.copyWith(
                  color: colors.onGlass,
                ),
                contextMenuBuilder: (context, editable) =>
                    AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editable.contextMenuAnchors,
                      buttonItems: [
                        for (final item in editable.contextMenuButtonItems)
                          if (item.type == ContextMenuButtonType.selectAll)
                            item
                          else if (item.type == ContextMenuButtonType.copy)
                            ContextMenuButtonItem(
                              type: ContextMenuButtonType.copy,
                              onPressed: () {
                                editable.hideToolbar();
                                onCopy();
                              },
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
