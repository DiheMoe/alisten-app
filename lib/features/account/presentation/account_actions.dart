import 'dart:async';

import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/application/github_controller.dart';
import 'package:alisten/features/account/application/site_capabilities.dart';
import 'package:alisten/features/account/presentation/change_password_sheet.dart';
import 'package:alisten/features/account/presentation/github_notice.dart';
import 'package:alisten/features/account/presentation/github_password_sheet.dart';
import 'package:alisten/features/account/presentation/pairing_code_sheet.dart';
import 'package:alisten/features/account/presentation/set_credentials_sheet.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountActions extends ConsumerStatefulWidget {
  const AccountActions({
    required this.onOpenLogin,
    required this.onOpenRegister,
    required this.onNotice,
    super.key,
  });

  final VoidCallback onOpenLogin;
  final VoidCallback onOpenRegister;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends ConsumerState<AccountActions> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    final inRoom = ref.read(roomControllerProvider).activeRoomId != null;
    final confirmed = await showConfirmSheet(
      context,
      title: '退出登录？',
      message: inRoom ? '退出后会重新进入当前房间，正在播放的歌会中断。' : '退出后这台设备会变成新的游客。',
      confirmLabel: '退出登录',
      confirmIcon: AlistenIcons.signOut,
    );
    if (!confirmed || !mounted) return;
    setState(() => _loggingOut = true);
    final result = await ref.read(accountControllerProvider).logout();
    if (mounted) setState(() => _loggingOut = false);
    switch (result) {
      case MutationSucceeded():
        widget.onNotice(ToastKind.success, '已退出登录');
      case MutationFailed(:final message) || MutationNotSent(:final message):
        widget.onNotice(ToastKind.failure, message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, logoutFailedText);
    }
  }

  void _changePassword() {
    unawaited(
      showSheetPanel<void>(
        context,
        builder: (_) => ChangePasswordSheet(onNotice: widget.onNotice),
      ),
    );
  }

  void _showPairingCode() {
    unawaited(showPairingCodeSheet(context, onNotice: widget.onNotice));
  }

  Future<void> _setCredentials() async {
    final onNotice = widget.onNotice;
    final result = await ref.read(githubControllerProvider.notifier).verify();
    if (result is! MutationSucceeded<GithubOutcome>) {
      noticeGithubResult(onNotice, result);
      return;
    }
    // 设置页已经不在就不打开面板，用户回来再点一次即可。
    if (!mounted) return;
    unawaited(showSetCredentialsSheet(context, onNotice: onNotice));
  }

  void _askPassword(GithubPasswordAction action) {
    unawaited(
      showGithubPasswordSheet(
        context,
        action: action,
        onNotice: widget.onNotice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(
      identityControllerProvider.select((identity) => identity.account),
    );
    final site =
        ref.watch(siteCapabilitiesProvider).value ?? SiteCapabilities.unknown;
    final running = ref.watch(githubControllerProvider);
    final idle = running == null;
    final rows = <Widget>[
      if (account == null) ...[
        _ActionRow(title: '登录', onPressed: widget.onOpenLogin),
        if (site.registrationOpen)
          _ActionRow(title: '注册账号', onPressed: widget.onOpenRegister),
      ] else ...[
        _ActionRow(title: '在新设备上登录', onPressed: _showPairingCode),
        if (account.username != null)
          _ActionRow(title: '修改密码', onPressed: _changePassword)
        else
          _ActionRow(
            title: '设置用户名和密码',
            busy: running == GithubIntent.verify,
            onPressed: idle ? () => unawaited(_setCredentials()) : null,
          ),
        if (site.githubLogin) _githubRow(account, running),
        _ActionRow(
          title: '退出登录',
          busy: _loggingOut,
          onPressed: () => unawaited(_logout()),
        ),
      ],
    ];
    final stroke = AlistenColors.of(context).glassStroke;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AlistenSpacing.md,
              ),
              child: SizedBox(
                height: AlistenSizes.hairline,
                child: ColoredBox(color: stroke),
              ),
            ),
          row,
        ],
      ],
    );
  }

  Widget _githubRow(Account account, GithubIntent? running) {
    if (!account.github) {
      return _ActionRow(
        title: '绑定 GitHub',
        subtitle: '绑定之后，可以用 GitHub 登录这个账号。',
        busy: running == GithubIntent.bind,
        onPressed: running == null
            ? () => _askPassword(GithubPasswordAction.bind)
            : null,
      );
    }
    // 只绑定了 GitHub 的账号没有密码，服务端不允许解绑。
    final hasUsername = account.username != null;
    return _ActionRow(
      title: '解绑 GitHub',
      subtitle: hasUsername ? '已绑定，可以用 GitHub 登录这个账号。' : '已绑定。先设置用户名和密码，才能解绑。',
      onPressed: hasUsername && running == null
          ? () => _askPassword(GithubPasswordAction.unbind)
          : null,
    );
  }
}

// 外观与设置页的链接行一致。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Pressable(
      onPressed: busy ? null : onPressed,
      dimWhenDisabled: !busy,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.largeTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AlistenSpacing.md,
            AlistenSpacing.sm,
            AlistenSpacing.sm,
            AlistenSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AlistenTypography.bodyStrong.copyWith(
                        color: colors.onGlass,
                      ),
                    ),
                    if (subtitle case final subtitle?) ...[
                      const SizedBox(height: AlistenSpacing.xxs),
                      Text(
                        subtitle,
                        style: AlistenTypography.secondary.copyWith(
                          color: colors.onGlassMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AlistenSpacing.sm),
              if (busy)
                Semantics(
                  value: busySemanticValue,
                  child: SizedBox.square(
                    dimension: AlistenSizes.icon,
                    child: Center(
                      child: BusyIndicator(
                        size: AlistenSizes.iconSm * 0.8,
                        color: colors.onGlassMuted,
                      ),
                    ),
                  ),
                )
              else
                Icon(
                  AlistenIcons.caretRight,
                  size: AlistenSizes.icon,
                  color: colors.onGlassMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
