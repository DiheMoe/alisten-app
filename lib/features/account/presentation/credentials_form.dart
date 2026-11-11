import 'dart:async';

import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/account/presentation/show_password_row.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const passwordsDifferText = '两次输入的密码不一样。';

final _lowercase = TextInputFormatter.withFunction(
  (_, next) => next.copyWith(text: next.text.toLowerCase()),
);

/// 登录和注册共用：用户名、密码、显示密码和提交。成功后通知系统的密码
/// 管理器保存。
class CredentialsForm extends StatefulWidget {
  const CredentialsForm({
    required this.submitLabel,
    required this.newAccount,
    required this.onSubmit,
    required this.onDone,
    this.enabled = true,
    super.key,
  });

  final String submitLabel;

  /// 为 true 时按新账号提示密码管理器，在输入框下写出规则，并要求再输入一次
  /// 密码。
  final bool newAccount;
  final Future<MutationResult<Object?>> Function(
    String username,
    String password,
  )
  onSubmit;
  final VoidCallback onDone;
  final bool enabled;

  @override
  State<CredentialsForm> createState() => _CredentialsFormState();
}

class _CredentialsFormState extends State<CredentialsForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !widget.enabled) return;
    if (widget.newAccount && _password.text != _again.text) {
      setState(() => _problem = passwordsDifferText);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final result = await widget.onSubmit(_username.text, _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case MutationSucceeded():
        TextInput.finishAutofillContext();
        widget.onDone();
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
      case MutationUnknown():
        setState(() => _problem = '没有确认结果，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final problem = _problem;
    final rules = widget.newAccount;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlistenTextField(
            controller: _username,
            label: '用户名',
            autofillHints: [
              rules ? AutofillHints.newUsername : AutofillHints.username,
            ],
            inputFormatters: [_lowercase],
            maxLength: 32,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
          ),
          if (rules) ...[
            const SizedBox(height: AlistenSpacing.xxs),
            Text(
              usernameRuleText,
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
          ],
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _password,
            label: '密码',
            obscureText: !_show,
            sensitive: true,
            autofillHints: [
              rules ? AutofillHints.newPassword : AutofillHints.password,
            ],
            textInputAction: rules
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: rules ? null : (_) => unawaited(_submit()),
          ),
          if (rules) ...[
            const SizedBox(height: AlistenSpacing.xxs),
            Text(
              passwordRuleText,
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
            const SizedBox(height: AlistenSpacing.md),
            AlistenTextField(
              controller: _again,
              label: '再次输入密码',
              obscureText: !_show,
              sensitive: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unawaited(_submit()),
            ),
          ],
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
            label: widget.submitLabel,
            icon: Icons.check_rounded,
            expand: true,
            busy: _busy,
            onPressed: _busy || !widget.enabled
                ? null
                : () => unawaited(_submit()),
          ),
        ],
      ),
    );
  }
}
