import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/ephemeral_room_capacity_controller.dart';
import 'package:alisten/features/admin/application/room_form.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EphemeralRoomsGroup extends ConsumerStatefulWidget {
  const EphemeralRoomsGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<EphemeralRoomsGroup> createState() =>
      _EphemeralRoomsGroupState();
}

class _EphemeralRoomsGroupState extends ConsumerState<EphemeralRoomsGroup> {
  final _capacity = TextEditingController();
  bool _saving = false;
  String? _problem;

  EphemeralRoomCapacityController get _controller =>
      ref.read(ephemeralRoomCapacityControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _controller.load();
      }),
    );
  }

  @override
  void dispose() {
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _problem = null;
    });
    final MutationResult<int> result;
    try {
      result = await _controller.save(_capacity.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded(:final value):
        _capacity.text = '$value';
        widget.onNotice(ToastKind.success, '临时房间最多人数已保存');
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, '结果未知，请确认最多人数后再决定是否重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 用户改过的输入框不再跟随读到的人数，以免覆盖正在编辑的内容。
    ref.listen(
      ephemeralRoomCapacityControllerProvider.select((state) => state.capacity),
      (previous, next) {
        if (_capacity.text == (previous?.toString() ?? '')) {
          _capacity.text = next?.toString() ?? '';
        }
      },
    );
    final colors = AlistenColors.of(context);
    final capacity = ref.watch(ephemeralRoomCapacityControllerProvider);
    final loadError = capacity.error;
    final problem = _problem;
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlistenTextField(
            controller: _capacity,
            label: '最多人数',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter('$roomCapacityMax'.length),
            ],
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
          ),
          const SizedBox(height: AlistenSpacing.xs),
          Text(
            '只影响之后新建的临时房间，已经建好的保持原来的人数。',
            style: AlistenTypography.secondary.copyWith(
              color: colors.onGlassMuted,
            ),
          ),
          if (loadError != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(
              text: loadError,
              action: PillButton(
                label: '重试',
                style: PillButtonStyle.ghost,
                onPressed: capacity.loading
                    ? null
                    : () => unawaited(_controller.load()),
              ),
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(text: problem),
          ],
          const SizedBox(height: AlistenSpacing.md),
          PillButton(
            label: '保存',
            icon: AlistenIcons.checkBold,
            expand: true,
            busy: _saving,
            onPressed: capacity.loading ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
