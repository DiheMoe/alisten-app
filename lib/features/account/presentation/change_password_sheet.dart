import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/presentation/credentials_form.dart';
import 'package:alisten/features/account/presentation/show_password_row.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_next.text != _again.text) {
      setState(() => _problem = passwordsDifferText);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final onNotice = widget.onNotice;
    final result = await ref
        .read(accountControllerProvider)
        .changePassword(current: _current.text, next: _next.text);
    final String problem;
    switch (result) {
      case MutationSucceeded():
        // 面板在请求期间被关掉时密码也已经改了，仍要提示，并让密码管理器保存。
        TextInput.finishAutofillContext();
        onNotice(ToastKind.success, '已修改密码，其他设备已退出登录');
        if (mounted) dismissSheet(context);
        return;
      case MutationFailed(:final message) || MutationNotSent(:final message):
        problem = message;
      case MutationUnknown():
        problem = '没有确认密码是否已经修改，请用新密码登录试试。';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 为一个服务器输入的密码绝不能发给另一个服务器，会话或成员一换就关闭。
    ref.listen(
      identityControllerProvider.select(
        (identity) => (identity.session, identity.member?.id),
      ),
      (_, _) => dismissSheet(context),
    );
    final colors = AlistenColors.of(context);
    final problem = _problem;
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '修改密码',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.xxs),
          Text(
            '修改后，其他设备需要重新登录。',
            style: AlistenTypography.secondary.copyWith(
              color: colors.onGlassMuted,
            ),
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _current,
            label: '当前密码',
            obscureText: !_show,
            sensitive: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _next,
            label: '新密码',
            obscureText: !_show,
            sensitive: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _again,
            label: '再次输入新密码',
            obscureText: !_show,
            sensitive: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_submit()),
          ),
          const SizedBox(height: AlistenSpacing.sm),
          ShowPasswordRow(
            value: _show,
            onChanged: (value) => setState(() => _show = value),
          ),
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(text: problem),
          ],
          const SizedBox(height: AlistenSpacing.lg),
          PillButton(
            label: '修改密码',
            icon: AlistenIcons.checkBold,
            expand: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_submit()),
          ),
        ],
      ),
    );
  }
}
