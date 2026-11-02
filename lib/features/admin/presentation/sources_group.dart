import 'dart:async';

import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/source_account_view.dart';
import 'package:alisten/features/admin/application/source_accounts_controller.dart';
import 'package:alisten/features/admin/presentation/qr_login_sheet.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SourcesGroup extends ConsumerStatefulWidget {
  const SourcesGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<SourcesGroup> createState() => _SourcesGroupState();
}

class _SourcesGroupState extends ConsumerState<SourcesGroup> {
  SourceAccountsController get _accounts =>
      ref.read(sourceAccountsControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _accounts.loadAll();
      }),
    );
  }

  Future<void> _signIn(LoginSource source) async {
    final onNotice = widget.onNotice;
    final signedIn = await showQrLoginSheet(
      context,
      source: source,
      onNotice: onNotice,
    );
    if (!mounted) return;
    // 无论面板如何关闭都重新读取：查询回复丢失时，服务端可能已保存登录信息。
    final status = await _accounts.load(source);
    if (!signedIn) return;
    final account = status?.account;
    final name = account?.name;
    onNotice(ToastKind.success, switch (account) {
      null => '已登录',
      _ when name != null && name.isNotEmpty => '已登录 $name',
      _ => '已登录 ${account.id}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final entries = ref.watch(sourceAccountsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, source) in LoginSource.values.indexed) ...[
          if (index > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AlistenSpacing.md,
              ),
              child: SizedBox(
                height: AlistenSizes.hairline,
                child: ColoredBox(color: colors.glassStroke),
              ),
            ),
          _SourceRow(
            key: ValueKey(source),
            source: source,
            entry: entries[source] ?? const SourceEntry(),
            onSignIn: () => unawaited(_signIn(source)),
            onRetry: () => unawaited(_accounts.load(source)),
          ),
        ],
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.entry,
    required this.onSignIn,
    required this.onRetry,
    super.key,
  });

  final LoginSource source;
  final SourceEntry entry;
  final VoidCallback onSignIn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    final status = entry.status;
    final error = entry.error;
    final view = status == null ? null : sourceAccountView(status, source);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlistenSpacing.md,
        vertical: AlistenSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platformName(source),
                      style: AlistenTypography.bodyStrong.copyWith(
                        color: colors.onGlass,
                      ),
                    ),
                    const SizedBox(height: AlistenSpacing.xxs / 2),
                    if (view != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(view.status, style: muted),
                      ),
                      for (final detail in view.details)
                        Text(detail, style: muted),
                    ] else if (error == null)
                      const StatusPill(
                        label: '正在读取',
                        icon: Icons.sync_rounded,
                        busy: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AlistenSpacing.sm),
              PillButton(
                label: status?.saved ?? false ? '重新登录' : '扫码登录',
                icon: Icons.qr_code_2_rounded,
                style: PillButtonStyle.secondary,
                onPressed: status == null && error == null ? null : onSignIn,
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(
              text: error,
              action: PillButton(
                label: '重试',
                style: PillButtonStyle.ghost,
                onPressed: entry.loading ? null : onRetry,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
