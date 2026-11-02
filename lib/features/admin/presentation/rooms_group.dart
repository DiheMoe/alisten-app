import 'dart:async';

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/application/admin_rooms_controller.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/presentation/api_key_sheet.dart';
import 'package:alisten/features/admin/presentation/room_actions_sheet.dart';
import 'package:alisten/features/admin/presentation/room_form_sheet.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _unknownText = '结果未知，请查看列表确认房间是否已删除。';

class RoomsGroup extends ConsumerStatefulWidget {
  const RoomsGroup({
    required this.onNotice,
    required this.onOpenRoom,
    super.key,
  });

  final void Function(ToastKind kind, String text) onNotice;
  final void Function(String roomRef) onOpenRoom;

  @override
  ConsumerState<RoomsGroup> createState() => _RoomsGroupState();
}

class _RoomsGroupState extends ConsumerState<RoomsGroup> {
  String? _deleting;

  AdminRoomsController get _rooms =>
      ref.read(adminRoomsControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _rooms.load();
      }),
    );
  }

  Future<void> _open(RoomListing room) async {
    final action = await showRoomActionsSheet(context, room);
    if (action == null || !mounted) return;
    final roomRef = room.slug ?? room.id;
    switch (action) {
      case RoomAction.enter:
        widget.onOpenRoom(roomRef);
      case RoomAction.copyInvite:
        final link = ref.read(appConfigProvider).inviteLinkFor(roomRef);
        unawaited(Clipboard.setData(ClipboardData(text: link)));
        widget.onNotice(ToastKind.success, '邀请链接已复制');
      case RoomAction.apiKey:
        await showApiKeySheet(context, room: room, onNotice: widget.onNotice);
      case RoomAction.edit:
        await showRoomFormSheet(context, room: room, onNotice: widget.onNotice);
      case RoomAction.delete:
        await _delete(room);
    }
  }

  Future<void> _delete(RoomListing room) async {
    final confirmed = await showConfirmSheet(
      context,
      title: '删除常驻房间？',
      message: '删除「${room.name}」后，房间里的所有人都会断开连接。',
      confirmLabel: '删除',
      confirmIcon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted || _deleting != null) return;
    setState(() => _deleting = room.id);
    final MutationResult<void> result;
    try {
      result = await _rooms.delete(room.id);
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded():
        widget.onNotice(ToastKind.success, '已删除「${room.name}」');
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, _unknownText);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        widget.onNotice(ToastKind.failure, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final rooms = ref.watch(adminRoomsControllerProvider);
    final error = rooms.error;
    final deleting = _deleting;
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, room) in rooms.rooms.indexed) ...[
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
          _RoomRow(
            room: room,
            deleting: room.id == deleting,
            onPressed: deleting == null ? () => unawaited(_open(room)) : null,
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(AlistenSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                InlineMessage(
                  text: error,
                  action: PillButton(
                    label: '重试',
                    style: PillButtonStyle.ghost,
                    onPressed: rooms.loading
                        ? null
                        : () => unawaited(_rooms.load()),
                  ),
                ),
                const SizedBox(height: AlistenSpacing.sm),
              ] else if (rooms.rooms.isEmpty) ...[
                if (rooms.loading)
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StatusPill(
                      label: '正在读取',
                      icon: Icons.sync_rounded,
                      busy: true,
                    ),
                  )
                else
                  Text('还没有常驻房间', style: muted),
                const SizedBox(height: AlistenSpacing.sm),
              ],
              PillButton(
                label: '新建常驻房间',
                icon: Icons.add_rounded,
                style: PillButtonStyle.secondary,
                expand: true,
                onPressed: deleting == null
                    ? () => unawaited(
                        showRoomFormSheet(context, onNotice: widget.onNotice),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({
    required this.room,
    required this.deleting,
    required this.onPressed,
  });

  final RoomListing room;
  final bool deleting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    return Pressable(
      onPressed: onPressed,
      dimWhenDisabled: !deleting,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.largeTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.md,
            vertical: AlistenSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AlistenTypography.bodyStrong.copyWith(
                        color: colors.onGlass,
                      ),
                    ),
                    const SizedBox(height: AlistenSpacing.xxs / 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            room.slug ?? room.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                        const SizedBox(width: AlistenSpacing.sm),
                        Text('在线 ${room.onlineCount} 人', style: muted),
                      ],
                    ),
                  ],
                ),
              ),
              if (deleting) ...[
                const SizedBox(width: AlistenSpacing.xs),
                const StatusPill(
                  label: '删除中',
                  icon: Icons.sync_rounded,
                  busy: true,
                ),
              ] else if (room.hasPassword) ...[
                const SizedBox(width: AlistenSpacing.xs),
                const StatusPill(label: '有密码', icon: Icons.lock_rounded),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
