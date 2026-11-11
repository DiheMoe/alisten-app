import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/account/application/github_controller.dart';
import 'package:alisten/features/account/presentation/github_notice.dart';
import 'package:alisten/features/account/presentation/show_password_row.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GithubPasswordAction { bind, unbind }

Future<void> showGithubPasswordSheet(
  BuildContext context, {
  required GithubPasswordAction action,
  required void Function(ToastKind kind, String text) onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => GithubPasswordSheet(action: action, onNotice: onNotice),
  );
}

// 当前密码只保存在输入框里，面板关闭即释放。绑定的整个授权流程中面板保持忙碌、
// 不能关闭，结果在这里说明。
class GithubPasswordSheet extends ConsumerStatefulWidget {
  const GithubPasswordSheet({
    required this.action,
    required this.onNotice,
    super.key,
  });

  final GithubPasswordAction action;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<GithubPasswordSheet> createState() =>
      _GithubPasswordSheetState();
}

class _GithubPasswordSheetState extends ConsumerState<GithubPasswordSheet> {
  final _password = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _problem;

  bool get _binding => widget.action == GithubPasswordAction.bind;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final onNotice = widget.onNotice;
    final github = ref.read(githubControllerProvider.notifier);
    if (_binding) {
      final result = await github.bind(_password.text);
      if (result case MutationFailed(
        code: githubWrongPasswordCode,
        :final message,
      )) {
        _stay(message);
        return;
      }
      _close();
      noticeGithubResult(onNotice, result);
      return;
    }
    final result = await github.unbind(_password.text);
    switch (result) {
      case MutationSucceeded():
        _close();
        onNotice(ToastKind.success, '已解绑 GitHub');
      case MutationUnknown():
        _close();
        onNotice(ToastKind.warning, githubUnknownText);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        _stay(message);
    }
  }

  void _stay(String problem) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  void _close() {
    if (!mounted) return;
    dismissSheet(context);
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
    return PopScope(
      canPop: !_busy,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                _binding ? '绑定 GitHub' : '解绑 GitHub',
                style: AlistenTypography.title.copyWith(color: colors.onGlass),
              ),
            ),
            const SizedBox(height: AlistenSpacing.md),
            AlistenTextField(
              controller: _password,
              label: '当前密码',
              obscureText: !_show,
              sensitive: true,
              autofillHints: const [AutofillHints.password],
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
              label: _binding ? '去 GitHub 授权' : '解绑',
              icon: _binding
                  ? Icons.open_in_new_rounded
                  : Icons.link_off_rounded,
              expand: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_submit()),
            ),
          ],
        ),
      ),
    );
  }
}
