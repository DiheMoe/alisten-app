import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/presentation/credentials_form.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _doneText = '已设置用户名和密码，其他设备已退出登录';

Future<void> showSetCredentialsSheet(
  BuildContext context, {
  required void Function(ToastKind kind, String text) onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => SetCredentialsSheet(onNotice: onNotice),
  );
}

class SetCredentialsSheet extends ConsumerWidget {
  const SetCredentialsSheet({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    // 确认记在当前服务器的当前会话上：会话或成员一换，这里提交就成了给别的身份
    // 注册账号。
    ref.listen(
      identityControllerProvider.select(
        (identity) => (identity.session, identity.member?.id),
      ),
      (_, _) => dismissSheet(context),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '设置用户名和密码',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.xxs),
        Text(
          '设置之后，其他设备需要重新登录。',
          style: AlistenTypography.secondary.copyWith(
            color: colors.onGlassMuted,
          ),
        ),
        const SizedBox(height: AlistenSpacing.md),
        CredentialsForm(
          submitLabel: '保存',
          newAccount: true,
          onSubmit: (username, password) async {
            final result = await ref
                .read(accountControllerProvider)
                .setCredentials(username: username, password: password);
            // 用 GitHub 确认身份已经超时：在这个面板里怎么改都不会成功。
            if (result case MutationFailed(code: 'FORBIDDEN', :final message)) {
              if (context.mounted) dismissSheet(context);
              onNotice(ToastKind.warning, message);
            } else if (!context.mounted ||
                (result is! MutationSucceeded<Object?> &&
                    !(ModalRoute.isActiveOf(context) ?? true))) {
              // 面板在请求期间已经关掉或正在收起（用户关掉、换了身份或服务器）：
              // 结果仍要提示。成功时表单还在就由 onDone 提示，这里不重复。
              switch (result) {
                case MutationSucceeded():
                  onNotice(ToastKind.success, _doneText);
                case MutationFailed(:final message) ||
                    MutationNotSent(:final message):
                  onNotice(ToastKind.warning, message);
                case MutationUnknown():
                  onNotice(ToastKind.warning, '没有确认结果，请稍后再试。');
              }
            }
            return result;
          },
          onDone: () {
            dismissSheet(context);
            onNotice(ToastKind.success, _doneText);
          },
        ),
      ],
    );
  }
}
