import 'dart:async';

import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/application/site_capabilities.dart';
import 'package:alisten/features/account/presentation/change_password_sheet.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
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
      confirmIcon: Icons.logout_rounded,
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
        builder: (_) =>
            SheetPanel(child: ChangePasswordSheet(onNotice: widget.onNotice)),
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
    final rows = <Widget>[
      if (account == null) ...[
        _ActionRow(title: '登录', onPressed: widget.onOpenLogin),
        if (site.registrationOpen)
          _ActionRow(title: '注册账号', onPressed: widget.onOpenRegister),
      ] else ...[
        if (account.username != null)
          _ActionRow(title: '修改密码', onPressed: _changePassword),
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
}

// 外观与设置页的链接行一致。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.onPressed,
    this.busy = false,
  });

  final String title;
  final VoidCallback onPressed;
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
                child: Text(
                  title,
                  style: AlistenTypography.bodyStrong.copyWith(
                    color: colors.onGlass,
                  ),
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
                  Icons.chevron_right_rounded,
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
