import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/features/admin/application/admin_media_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 两个按钮占去 360 dp 宽屏幕的大半，字号再大中间的范围就没地方了；范围放
/// 不下时缩小，读屏名称里仍是完整的范围。
const _maxTextScale = 1.3;

const _target = BoxConstraints(minHeight: AlistenSizes.minTouchTarget);

/// “‹ 上一页”“第 21–40 首”“下一页 ›”；点中间的范围输入页码跳转。
class MediaPager extends StatelessWidget {
  const MediaPager({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onGo,
    super.key,
  });

  final int page;
  final int pageCount;
  final int total;
  final ValueChanged<int> onGo;

  Future<void> _jump(BuildContext context) async {
    final target = await showMediaJumpSheet(context, pageCount: pageCount);
    if (target != null && context.mounted) onGo(target);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final first = (page - 1) * mediaPageSize + 1;
    final last = math.min(page * mediaPageSize, total);
    final range = '第 $first–$last 首';
    final label = Text(
      range,
      maxLines: 1,
      style: AlistenTypography.timecode.copyWith(color: colors.onGlass),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AlistenSpacing.sm),
        child: Row(
          children: [
            PillButton(
              label: '上一页',
              icon: AlistenIcons.arrowLeft,
              style: PillButtonStyle.ghost,
              onPressed: page > 1 ? () => onGo(page - 1) : null,
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Pressable(
                    semanticLabel: '$range，共 $pageCount 页，跳到指定页',
                    onPressed: () => unawaited(_jump(context)),
                    // 桌面窗口里只有页码在鼠标下亮起；手机上整块都是按下的范围。
                    touchTarget: isDesktopPlatform ? _target : null,
                    child: ExcludeSemantics(
                      child: isDesktopPlatform
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AlistenSpacing.sm,
                                vertical: AlistenSpacing.xs,
                              ),
                              child: label,
                            )
                          : ConstrainedBox(
                              constraints: _target,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AlistenSpacing.xs,
                                ),
                                child: Center(widthFactor: 1, child: label),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            PillButton(
              label: '下一页',
              icon: AlistenIcons.arrowRight,
              iconAfter: true,
              style: PillButtonStyle.ghost,
              onPressed: page < pageCount ? () => onGo(page + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入 1 到 [pageCount] 之间的页码；关掉面板时为 null。
Future<int?> showMediaJumpSheet(
  BuildContext context, {
  required int pageCount,
}) => showSheetPanel<int>(
  context,
  builder: (_) => _JumpSheet(pageCount: pageCount),
);

class _JumpSheet extends StatefulWidget {
  const _JumpSheet({required this.pageCount});

  final int pageCount;

  @override
  State<_JumpSheet> createState() => _JumpSheetState();
}

class _JumpSheetState extends State<_JumpSheet> {
  final _page = TextEditingController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  int? get _target {
    final page = int.tryParse(_page.text);
    return page != null && page >= 1 && page <= widget.pageCount ? page : null;
  }

  void _go() {
    final target = _target;
    if (target != null) Navigator.of(context).pop(target);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final pageCount = widget.pageCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '跳到第几页',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.xs),
        Text(
          '共 $pageCount 页',
          style: AlistenTypography.body.copyWith(color: colors.onGlassMuted),
        ),
        const SizedBox(height: AlistenSpacing.md),
        AlistenTextField(
          controller: _page,
          label: '页码',
          hint: '1–$pageCount',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: '$pageCount'.length,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: AlistenSpacing.xl),
        PillButton(
          label: '跳转',
          large: true,
          expand: true,
          onPressed: _target == null ? null : _go,
        ),
      ],
    );
  }
}
