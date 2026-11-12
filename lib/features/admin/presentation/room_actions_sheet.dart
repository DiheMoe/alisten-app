import 'package:alisten/domain/room/room.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/material.dart';

enum RoomAction { enter, copyInvite, apiKey, edit, delete }

/// 面板收起后才返回，因为所选操作可能离开后台页面或打开另一个面板。
Future<RoomAction?> showRoomActionsSheet(
  BuildContext context,
  RoomListing room,
) {
  return showSheetPanel<RoomAction>(
    context,
    untilClosed: true,
    builder: (_) => RoomActionsSheet(room: room),
  );
}

class RoomActionsSheet extends StatelessWidget {
  const RoomActionsSheet({required this.room, super.key});

  final RoomListing room;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    Widget action(
      RoomAction value,
      String label,
      IconData icon, {
      PillButtonStyle style = PillButtonStyle.secondary,
    }) {
      return Padding(
        padding: const EdgeInsets.only(top: AlistenSpacing.xs),
        child: PillButton(
          label: label,
          icon: icon,
          style: style,
          expand: true,
          onPressed: () => Navigator.of(context).pop(value),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            room.name,
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.xxs),
        Text(
          room.slug ?? room.id,
          style: AlistenTypography.secondary.copyWith(
            color: colors.onGlassMuted,
          ),
        ),
        const SizedBox(height: AlistenSpacing.md),
        action(
          RoomAction.enter,
          '进入',
          AlistenIcons.signIn,
          style: PillButtonStyle.primary,
        ),
        action(RoomAction.copyInvite, '复制邀请链接', AlistenIcons.link),
        action(RoomAction.apiKey, 'API Key', AlistenIcons.key),
        action(RoomAction.edit, '编辑', AlistenIcons.pencilSimple),
        action(RoomAction.delete, '删除', AlistenIcons.trash),
      ],
    );
  }
}
