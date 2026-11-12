import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_registration_controller.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _openText = '现在任何人都可以注册账号。关闭后不能再注册新账号，已有账号照常登录，游客照常使用。';
const _closedText = '现在不能注册新账号。已有账号照常登录，游客照常使用。';

class RegistrationGroup extends ConsumerStatefulWidget {
  const RegistrationGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<RegistrationGroup> createState() => _RegistrationGroupState();
}

class _RegistrationGroupState extends ConsumerState<RegistrationGroup> {
  bool _switching = false;
  String? _problem;

  AdminRegistrationController get _registration =>
      ref.read(adminRegistrationControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _registration.load();
      }),
    );
  }

  Future<void> _switch(bool open) async {
    setState(() {
      _switching = true;
      _problem = null;
    });
    final MutationResult<bool> result;
    try {
      result = await _registration.setOpen(open);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded(:final value):
        widget.onNotice(ToastKind.success, value ? '已开放注册' : '已关闭注册');
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, '结果未知，请确认注册状态后再决定是否重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = ref.watch(adminRegistrationControllerProvider);
    final open = registration.open;
    final loadError = registration.error;
    final problem = _problem;
    final colors = AlistenColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (open != null) ...[
            Text(
              open ? _openText : _closedText,
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
            const SizedBox(height: AlistenSpacing.md),
            PillButton(
              label: open ? '关闭注册' : '开放注册',
              expand: true,
              busy: _switching,
              onPressed: registration.loading || _switching
                  ? null
                  : () => unawaited(_switch(!open)),
            ),
          ] else if (loadError == null)
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusPill(
                label: '正在获取注册状态…',
                busy: true,
                icon: AlistenIcons.arrowsClockwise,
              ),
            ),
          if (loadError != null)
            InlineMessage(
              text: loadError,
              action: PillButton(
                label: '重试',
                style: PillButtonStyle.ghost,
                onPressed: registration.loading
                    ? null
                    : () => unawaited(_registration.load()),
              ),
            ),
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(text: problem),
          ],
        ],
      ),
    );
  }
}
