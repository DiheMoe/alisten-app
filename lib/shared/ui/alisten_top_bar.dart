import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/widgets.dart';

/// 桌面窗口里由侧栏直接到达的页面：侧栏就是它的导航，顶栏不再放返回按钮。
class SidebarPage extends InheritedWidget {
  const SidebarPage({required this.active, required super.child, super.key});

  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarPage>()?.active ??
      false;

  @override
  bool updateShouldNotify(SidebarPage oldWidget) => active != oldWidget.active;
}

class AlistenTopBar extends StatelessWidget {
  const AlistenTopBar({
    this.leading,
    this.title,
    this.subtitle,
    this.subtitleLeading,
    this.actions = const [],
    super.key,
  });

  final Widget? leading;
  final String? title;
  final String? subtitle;
  final Widget? subtitleLeading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final title = this.title;
    final subtitle = this.subtitle;
    final leading = SidebarPage.of(context) ? null : this.leading;
    return ToastClearance(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.xs,
            vertical: AlistenSpacing.xxs,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlistenSizes.minTouchTarget,
            ),
            child: Row(
              children: [
                ?leading,
                SizedBox(
                  width: leading == null
                      ? AlistenSpacing.sm
                      : AlistenSpacing.xxs,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AlistenTypography.weighted(
                              AlistenTypography.bodyStrong,
                              FontWeight.w700,
                            ).copyWith(color: colors.onGlass),
                          ),
                        ),
                      if (subtitle != null)
                        Row(
                          children: [
                            if (subtitleLeading case final dot?) ...[
                              dot,
                              const SizedBox(width: AlistenSpacing.xxs),
                            ],
                            Flexible(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AlistenTypography.secondary.copyWith(
                                  color: colors.onGlassMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
