import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/widgets.dart';

Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  IconData? confirmIcon,
  bool untilClosed = false,
  Future<bool> Function()? onConfirm,
  String? busyLabel,
}) async {
  final confirmed = await showSheetPanel<bool>(
    context,
    untilClosed: untilClosed,
    builder: (_) => ConfirmSheet(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmIcon: confirmIcon,
      onConfirm: onConfirm,
      busyLabel: busyLabel,
    ),
  );
  return confirmed ?? false;
}

class ConfirmSheet extends StatefulWidget {
  const ConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = '取消',
    this.confirmIcon,
    this.onConfirm,
    this.busyLabel,
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData? confirmIcon;

  /// 确认后面板保持打开直到它完成，并以它的结果关闭；等待期间确认按钮显示
  /// [busyLabel] 且不可再按，取消仍然可用。
  final Future<bool> Function()? onConfirm;
  final String? busyLabel;

  @override
  State<ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<ConfirmSheet> {
  bool _busy = false;

  Future<void> _confirm() async {
    final onConfirm = widget.onConfirm;
    if (onConfirm == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = true);
    final confirmed = await onConfirm();
    // 等待期间用户可能已取消：收起动画结束前组件仍挂载，但栈顶已是下方页面，
    // 此时 pop 会把那个页面弹掉。
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop(confirmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.title,
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.xs),
        Text(
          widget.message,
          style: AlistenTypography.body.copyWith(color: colors.onGlassMuted),
        ),
        const SizedBox(height: AlistenSpacing.xl),
        PillButton(
          label: _busy
              ? widget.busyLabel ?? widget.confirmLabel
              : widget.confirmLabel,
          icon: widget.confirmIcon,
          busy: _busy,
          large: true,
          expand: true,
          onPressed: () => unawaited(_confirm()),
        ),
        const SizedBox(height: AlistenSpacing.xs),
        PillButton(
          label: widget.cancelLabel,
          style: PillButtonStyle.ghost,
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
