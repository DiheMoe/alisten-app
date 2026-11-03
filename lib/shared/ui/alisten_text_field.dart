import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 读屏名称取 [label]，没有时取 [hint]，输入内容后仍保留；`TextField` 自带的
/// 提示文字会随输入消失。[maxLength] 只限制长度，不显示计数。
class AlistenTextField extends StatefulWidget {
  const AlistenTextField({
    required this.controller,
    this.label,
    this.hint,
    this.icon,
    this.pill = false,
    this.onClear,
    this.focusNode,
    this.autofocus = false,
    this.obscureText = false,
    this.sensitive = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLength,
    this.inputFormatters = const [],
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final bool pill;

  /// 调用时输入框已清空，随后重新获得焦点。
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscureText;

  /// 为 true 时选择菜单只保留粘贴和全选，复制、剪切快捷键失效，键盘不学习、
  /// 不联想、不纠错。读屏复制、Android 输入法的复制和 iOS 原生拷贝由平台直接
  /// 写入系统剪贴板，Dart 层无法拦截，因此不能保证内容不外泄。
  final bool sensitive;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final List<TextInputFormatter> inputFormatters;

  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 有焦点时点按框外任意位置（包括其他页面和面板）都会调用；框内的图标和
  /// 清空按钮不算框外。
  final TapRegionCallback? onTapOutside;

  @override
  State<AlistenTextField> createState() => _AlistenTextFieldState();
}

class _AlistenTextFieldState extends State<AlistenTextField> {
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  void _clear() {
    widget.controller.clear();
    widget.onClear?.call();
    _focus.requestFocus();
  }

  // 敏感时只保留粘贴和全选：复制、剪切、分享、查询、搜索网页和文本处理都会把
  // 内容交给剪贴板或其他应用。
  Widget _contextMenu(BuildContext context, EditableTextState editable) {
    final system = SystemContextMenu.isSupportedByField(editable);
    if (!widget.sensitive) {
      return system
          ? SystemContextMenu.editableText(editableTextState: editable)
          : AdaptiveTextSelectionToolbar.editableText(
              editableTextState: editable,
            );
    }
    final items = [
      for (final item in editable.contextMenuButtonItems)
        if (item.kind == ContextMenuButtonKind.paste ||
            item.kind == ContextMenuButtonKind.selectAll)
          item,
    ];
    if (system) {
      return SystemContextMenu.editableText(
        editableTextState: editable,
        items: [
          for (final item in items)
            item.kind == ContextMenuButtonKind.paste
                ? const IOSSystemContextMenuItemPaste()
                : const IOSSystemContextMenuItemSelectAll(),
        ],
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final style = AlistenTypography.body.copyWith(color: colors.onGlass);
    final icon = widget.icon;
    final maxLength = widget.maxLength;
    final label = widget.label;
    final hint = widget.hint;
    final radius = BorderRadius.circular(
      widget.pill ? AlistenRadii.pill : AlistenRadii.sm,
    );
    final minHeight = widget.pill
        ? AlistenSizes.largeTouchTarget
        : AlistenSizes.minTouchTarget;
    final lines = widget.obscureText ? 1 : widget.maxLines;
    // InputDecoration.constraints 撑出的高度全部留在文字下方，垂直居中不分配
    // 它，文字因此偏上。改由内边距把一行时的自然高度补足到最小高度。
    final padding = math.max(
      AlistenSpacing.sm,
      (minHeight -
              AlistenTypography.lineHeight(
                style,
                MediaQuery.textScalerOf(context),
              )) /
          2,
    );
    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      autocorrect: !widget.sensitive,
      enableSuggestions: !widget.sensitive,
      enableIMEPersonalizedLearning: !widget.sensitive,
      contextMenuBuilder: _contextMenu,
      minLines: 1,
      maxLines: lines,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ...widget.inputFormatters,
      ],
      style: style,
      // iOS 默认光标淡入淡出，聚焦期间持续按屏幕刷新率出帧；关闭后与 Android
      // 一样每 500 ms 闪烁一次。
      cursorOpacityAnimates: false,
      textAlignVertical: TextAlignVertical.center,
      // 上下留白放在输入框内部，点按留白也能聚焦，读屏的触控区域与整个框等高。
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: padding),
        constraints: BoxConstraints(minHeight: minHeight),
        border: InputBorder.none,
        hintFadeDuration: Duration.zero,
        hint: hint == null
            ? null
            : ExcludeSemantics(
                child: Text(
                  hint,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: colors.onGlassMuted),
                ),
              ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTapOutside: widget.onTapOutside,
    );
    final box = TextFieldTapRegion(
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassFill,
            borderRadius: radius,
            border: Border.all(
              color: _focus.hasFocus ? colors.outline : colors.glassStroke,
            ),
          ),
          child: child,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Row(
            children: [
              SizedBox(
                width: widget.pill ? AlistenSpacing.md : AlistenSpacing.sm,
              ),
              if (icon != null) ...[
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: AlistenSizes.iconSm,
                    color: colors.onGlassMuted,
                  ),
                ),
                const SizedBox(width: AlistenSpacing.sm),
              ],
              Expanded(
                child: MergeSemantics(
                  child: Semantics(
                    label: label ?? hint,
                    child: Actions(
                      actions: {
                        if (widget.sensitive)
                          CopySelectionTextIntent: DoNothingAction(),
                      },
                      child: field,
                    ),
                  ),
                ),
              ),
              if (widget.onClear == null)
                SizedBox(
                  width: widget.pill ? AlistenSpacing.md : AlistenSpacing.sm,
                )
              else
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => widget.controller.text.isEmpty
                      ? const SizedBox(width: AlistenSpacing.md)
                      : IconCircleButton(
                          icon: Icons.cancel_rounded,
                          semanticLabel: '清空',
                          style: IconCircleButtonStyle.plain,
                          iconSize: AlistenSizes.iconSm,
                          diameter: AlistenSizes.rowAction,
                          onPressed: _clear,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
    if (label == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AlistenSpacing.xxs,
            bottom: AlistenSpacing.xs,
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: AlistenTypography.weighted(
                AlistenTypography.secondary,
                FontWeight.w600,
              ).copyWith(color: colors.onGlassMuted),
            ),
          ),
        ),
        box,
      ],
    );
  }
}
