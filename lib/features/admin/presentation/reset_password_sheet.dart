import 'dart:async';

import 'package:alisten/features/admin/presentation/secret_box.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';

// 新密码只放在本面板的参数里，面板关闭即丢弃，不进入任何 provider。
class ResetPasswordSheet extends StatelessWidget {
  const ResetPasswordSheet({
    required this.username,
    required this.password,
    required this.onCopy,
    required this.onNotice,
    super.key,
  });

  final String username;
  final String password;
  final Future<bool> Function(String password) onCopy;
  final void Function(ToastKind kind, String text) onNotice;

  Future<void> _copy() async {
    if (await onCopy(password)) {
      onNotice(ToastKind.success, '新密码已复制');
    } else {
      onNotice(ToastKind.failure, '没能复制，请重试。');
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
            '新密码',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.xxs),
        Text(
          '@$username',
          style: AlistenTypography.secondary.copyWith(
            color: colors.onGlassMuted,
          ),
        ),
        const SizedBox(height: AlistenSpacing.md),
        SecretBox(secret: password, onCopy: () => unawaited(_copy())),
        const SizedBox(height: AlistenSpacing.xs),
        PillButton(
          label: '复制',
          icon: AlistenIcons.copySimple,
          expand: true,
          onPressed: () => unawaited(_copy()),
        ),
        const SizedBox(height: AlistenSpacing.sm),
        const InlineMessage(
          text: '只显示这一次，请转告用户。这个账号在所有设备上都已退出登录。',
          tone: StatusTone.warning,
        ),
      ],
    );
  }
}
