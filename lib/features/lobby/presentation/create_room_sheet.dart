import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lobby/application/lobby_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<RoomListing?> showCreateRoomSheet(BuildContext context) {
  return showSheetPanel<RoomListing>(
    context,
    builder: (_) => const CreateRoomSheet(),
  );
}

// 提交期间不能关闭面板，否则请求未完成时可能从新面板重复建房。
class CreateRoomSheet extends ConsumerStatefulWidget {
  const CreateRoomSheet({super.key});

  @override
  ConsumerState<CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends ConsumerState<CreateRoomSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  LobbyActionException? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    RoomListing? room;
    LobbyActionException? error;
    try {
      room = await ref
          .read(lobbyControllerProvider.notifier)
          .createRoom(
            name: _name.text,
            description: _description.text,
            password: _password.text,
          );
    } on LobbyActionException catch (failure) {
      error = failure;
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error;
        });
      }
    }
    if (room != null && mounted) Navigator.of(context).pop(room);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final error = _error;
    return PopScope(
      canPop: !_submitting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '创建房间',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.xxs),
          Text(
            '创建后直接进入，设置了密码的房间要凭密码进入。',
            style: AlistenTypography.secondary.copyWith(
              color: colors.onGlassMuted,
            ),
          ),
          const SizedBox(height: AlistenSpacing.lg),
          // 不自动聚焦：键盘与面板同时滑入会让入场动画明显掉帧。
          AlistenTextField(
            controller: _name,
            label: '房间名称',
            maxLength: 80,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _description,
            label: '房间描述（可选）',
            maxLength: 500,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _password,
            label: '密码（可选）',
            obscureText: true,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
          ),
          if (error != null) ...[
            const SizedBox(height: AlistenSpacing.md),
            InlineMessage(
              text: error.message,
              tone: error.unknown ? StatusTone.warning : StatusTone.danger,
            ),
          ],
          const SizedBox(height: AlistenSpacing.xl),
          PillButton(
            label: '创建并进入',
            icon: Icons.add_rounded,
            large: true,
            expand: true,
            glow: true,
            busy: _submitting,
            onPressed: _submit,
          ),
          const SizedBox(height: AlistenSpacing.xs),
          PillButton(
            label: '取消',
            style: PillButtonStyle.ghost,
            expand: true,
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
