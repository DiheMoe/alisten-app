import 'package:alisten/features/admin/presentation/media_format.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 多选时浮在屏幕底部：选了多少、多大，全选本页、删除，左边“×”退出多选。
/// 按钮和数量放成两行：360 dp 宽时一行放不下“取消全选本页”和“删除”。
///
/// 字号大、屏幕窄时按钮文字会折行，高度没法事先算准：每次布局后把实际高度
/// 告诉 [onHeight]，列表据此在末尾留出空间。
class MediaSelectionBar extends StatelessWidget {
  const MediaSelectionBar({
    required this.count,
    required this.bytes,
    required this.pageSelected,
    required this.removing,
    required this.onCancel,
    required this.onTogglePage,
    required this.onDelete,
    required this.onHeight,
    super.key,
  });

  final int count;
  final int bytes;
  final bool pageSelected;
  final bool removing;
  final VoidCallback onCancel;
  final VoidCallback onTogglePage;
  final VoidCallback onDelete;

  /// 高度变化的那一帧结束时调用，参数是整个操作条的高度。
  final ValueChanged<double> onHeight;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return _HeightReporter(onHeight: onHeight, child: _bar(colors));
  }

  Widget _bar(AlistenColors colors) {
    return DecoratedBox(
      // 浮在列表上：用不透明的底色，下面滚过的行不会透上来。
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(AlistenRadii.md),
        border: Border.all(color: colors.glassStroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: AlistenSpacing.lg,
            offset: const Offset(0, AlistenSpacing.xxs),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AlistenSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconCircleButton(
                  icon: AlistenIcons.x,
                  semanticLabel: '退出多选',
                  style: IconCircleButtonStyle.plain,
                  onPressed: onCancel,
                ),
                const SizedBox(width: AlistenSpacing.xxs),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '已选 $count 首 · ${formatBytes(bytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AlistenTypography.weighted(
                        AlistenTypography.bodyStrong,
                        FontWeight.w700,
                      ).copyWith(color: colors.onGlass),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AlistenSpacing.xxs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: PillButton(
                    label: pageSelected ? '取消全选本页' : '全选本页',
                    style: PillButtonStyle.ghost,
                    onPressed: onTogglePage,
                  ),
                ),
                const SizedBox(width: AlistenSpacing.xs),
                Flexible(
                  child: PillButton(
                    label: '删除',
                    icon: AlistenIcons.trash,
                    style: PillButtonStyle.secondary,
                    danger: true,
                    busy: removing,
                    onPressed: removing ? null : onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  _RenderHeightReporter createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // 布局期间不能改别的组件的状态，留到这一帧结束。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}
