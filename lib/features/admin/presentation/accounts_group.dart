import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_accounts_controller.dart';
import 'package:alisten/features/admin/presentation/reset_password_sheet.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountsGroup extends ConsumerStatefulWidget {
  const AccountsGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<AccountsGroup> createState() => _AccountsGroupState();
}

class _AccountsGroupState extends ConsumerState<AccountsGroup> {
  final _username = TextEditingController();
  bool _resetting = false;

  AdminAccountsController get _accounts =>
      ref.read(adminAccountsControllerProvider.notifier);

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _reset(String username) async {
    if (_resetting) return;
    final confirmed = await showConfirmSheet(
      context,
      title: '重置 @$username 的密码？',
      message: '会生成一个新密码，这个账号在所有设备上都会退出登录。',
      confirmLabel: '重置密码',
    );
    if (!confirmed || !mounted) return;
    setState(() => _resetting = true);
    final MutationResult<String> result;
    try {
      result = await _accounts.resetPassword();
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
    if (!mounted) return;
    switch (result) {
      case MutationSucceeded(:final value):
        await showSheetPanel<void>(
          context,
          builder: (_) => ResetPasswordSheet(
            username: username,
            password: value,
            onCopy: _accounts.copy,
            onNotice: widget.onNotice,
          ),
        );
      case MutationFailed(:final message) || MutationNotSent(:final message):
        widget.onNotice(ToastKind.failure, message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, '结果未知：密码可能已经重置，请再重置一次以拿到新密码。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(adminAccountsControllerProvider);
    final account = accounts.account;
    final problem = accounts.problem;
    final colors = AlistenColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '按用户名查找。用户忘记密码时，可以在这里重置。',
            style: AlistenTypography.secondary.copyWith(
              color: colors.onGlassMuted,
            ),
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _username,
            label: '用户名',
            maxLength: 32,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            inputFormatters: [
              TextInputFormatter.withFunction(
                (_, value) => value.copyWith(text: value.text.toLowerCase()),
              ),
            ],
            onSubmitted: (_) => unawaited(_accounts.find(_username.text)),
          ),
          const SizedBox(height: AlistenSpacing.sm),
          PillButton(
            label: '查找',
            icon: Icons.search_rounded,
            expand: true,
            busy: accounts.searching,
            onPressed: accounts.searching
                ? null
                : () => unawaited(_accounts.find(_username.text)),
          ),
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(text: problem),
          ],
          if (account != null) ...[
            const SizedBox(height: AlistenSpacing.md),
            Row(
              children: [
                MemberAvatar(
                  name: account.member.name,
                  imageUrl: account.member.avatarUrl(
                    AlistenSizes.profileAvatar,
                  ),
                  size: AlistenSizes.profileAvatar,
                ),
                const SizedBox(width: AlistenSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.member.name,
                        style: AlistenTypography.bodyStrong.copyWith(
                          color: colors.onGlass,
                        ),
                      ),
                      Text(
                        '@${account.username}',
                        style: AlistenTypography.secondary.copyWith(
                          color: colors.onGlassMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AlistenSpacing.md),
            PillButton(
              label: '重置密码',
              style: PillButtonStyle.secondary,
              expand: true,
              busy: _resetting,
              onPressed: _resetting
                  ? null
                  : () => unawaited(_reset(account.username)),
            ),
          ],
        ],
      ),
    );
  }
}
