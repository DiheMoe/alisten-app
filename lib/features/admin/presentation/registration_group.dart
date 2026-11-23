import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_registration_controller.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/settings_list.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RegistrationGroup extends ConsumerStatefulWidget {
  const RegistrationGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<RegistrationGroup> createState() => _RegistrationGroupState();
}

class _RegistrationGroupState extends ConsumerState<RegistrationGroup> {
  bool _switching = false;
  bool? _pending;
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
      _pending = open;
      _problem = null;
    });
    final MutationResult<bool> result;
    try {
      result = await _registration.setOpen(open);
    } finally {
      if (mounted) {
        setState(() {
          _switching = false;
          _pending = null;
        });
      }
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded():
        break;
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, '没能确认是否修改，已重新读取');
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = ref.watch(adminRegistrationControllerProvider);
    final open = registration.open;
    final loadError = registration.error;
    final problem = _problem;
    const inset = EdgeInsets.all(AlistenSpacing.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (open != null)
          SettingRow(
            title: '开放注册',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_switching) ...[
                  const BusyIndicator(),
                  const SizedBox(width: AlistenSpacing.sm),
                ],
                AlistenToggle(
                  value: _pending ?? open,
                  onChanged: registration.loading || _switching
                      ? null
                      : (value) => unawaited(_switch(value)),
                  semanticLabel: '开放注册',
                ),
              ],
            ),
          )
        else if (loadError == null)
          const Padding(
            padding: inset,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusPill(
                label: '正在获取注册状态…',
                busy: true,
                icon: AlistenIcons.arrowsClockwise,
              ),
            ),
          ),
        if (loadError != null || problem != null)
          Padding(
            padding: inset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  if (loadError != null)
                    const SizedBox(height: AlistenSpacing.sm),
                  InlineMessage(text: problem),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
