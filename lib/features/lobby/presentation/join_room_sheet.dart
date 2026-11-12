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

// 从查票据开始就记为已打开，避免查票据期间重复打开。
final _joinSheetShown = Expando<bool>('join sheet shown');

/// 面板只用 [room] 描述房间，从不显示 [roomRef]。已有加入面板，或查完票据时
/// [context] 所在页面已不在最上层，就不打开面板并返回 null。[onChecked] 在
/// 查完票据、面板即将出现时调用。
Future<RoomListing?> showJoinRoomSheet(
  BuildContext context,
  WidgetRef ref, {
  required String roomRef,
  RoomListing? room,
  VoidCallback? onChecked,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_joinSheetShown[navigator] ?? false) return null;
  _joinSheetShown[navigator] = true;
  try {
    final needsPassword = await ref
        .read(lobbyControllerProvider.notifier)
        .needsPassword(room);
    if (!context.mounted || !_onTop(context)) return null;
    onChecked?.call();
    return await showSheetPanel<RoomListing>(
      context,
      builder: (_) => JoinRoomSheet(
        roomRef: roomRef,
        room: room,
        needsPassword: needsPassword,
      ),
    );
  } finally {
    _joinSheetShown[navigator] = null;
  }
}

// 大厅在外壳导航器里，房间页叠在根导航器上；只看最近的导航器会误判大厅仍在
// 最上层。
bool _onTop(BuildContext context) {
  if (!(ModalRoute.isCurrentOf(context) ?? true)) return false;
  for (
    var navigator = Navigator.maybeOf(context);
    navigator != null;
    navigator = navigator.context.findAncestorStateOfType<NavigatorState>()
  ) {
    if (!(ModalRoute.isCurrentOf(navigator.context) ?? true)) return false;
  }
  return true;
}

class JoinRoomSheet extends ConsumerStatefulWidget {
  const JoinRoomSheet({
    required this.roomRef,
    required this.room,
    required this.needsPassword,
    super.key,
  });

  final String roomRef;
  final RoomListing? room;
  final bool needsPassword;

  @override
  ConsumerState<JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends ConsumerState<JoinRoomSheet> {
  final _password = TextEditingController();
  bool _submitting = false;
  LobbyActionException? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _ready => !widget.needsPassword || _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (_submitting || !_ready) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    RoomListing? room;
    LobbyActionException? error;
    try {
      room = await ref
          .read(lobbyControllerProvider.notifier)
          .join(
            widget.roomRef,
            password: widget.needsPassword ? _password.text : null,
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
              '加入房间',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.lg),
          _RoomSummary(room: widget.room),
          if (widget.needsPassword) ...[
            const SizedBox(height: AlistenSpacing.lg),
            // 不自动聚焦：键盘与面板同时滑入会让入场动画明显掉帧。
            AlistenTextField(
              controller: _password,
              label: '房间密码',
              hint: '输入房间密码',
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ],
          const SizedBox(height: AlistenSpacing.md),
          Text(
            '加入后，与房间内的所有人同步播放、点歌和聊天。',
            style: AlistenTypography.secondary.copyWith(
              color: colors.onGlassMuted,
            ),
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
            label: '进入房间',
            icon: Icons.login_rounded,
            large: true,
            expand: true,
            busy: _submitting,
            onPressed: _ready ? _submit : null,
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

class _RoomSummary extends StatelessWidget {
  const _RoomSummary({required this.room});

  final RoomListing? room;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final room = this.room;
    final name = room?.name.trim() ?? '';
    final identity = room == null ? null : AlistenColors.identity(room.id);
    final description = room?.description.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: AlistenSizes.rowCover,
            height: AlistenSizes.rowCover,
            decoration: BoxDecoration(
              color: identity?.fill ?? colors.glassFill,
              borderRadius: BorderRadius.circular(AlistenRadii.sm),
            ),
            alignment: Alignment.center,
            child: identity == null
                ? Icon(
                    Icons.lock_rounded,
                    size: AlistenSizes.icon,
                    color: colors.onGlassMuted,
                  )
                : Text(
                    name.isEmpty ? '#' : name.characters.first.toUpperCase(),
                    // 首字跟随色块尺寸，不随系统字号缩放，否则会撑破色块。
                    textScaler: TextScaler.noScaling,
                    style: AlistenTypography.weighted(
                      AlistenTypography.title,
                      FontWeight.w800,
                    ).copyWith(color: identity.ink),
                  ),
          ),
        ),
        const SizedBox(width: AlistenSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room == null ? '这个房间需要密码' : room.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AlistenTypography.bodyStrong.copyWith(
                  color: colors.onGlass,
                ),
              ),
              if (room != null) ...[
                const SizedBox(height: AlistenSpacing.xxs),
                Text(
                  description.isEmpty ? '来这里，听见好音乐。' : description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
                const SizedBox(height: AlistenSpacing.xs),
                Wrap(
                  spacing: AlistenSpacing.sm,
                  runSpacing: AlistenSpacing.xxs,
                  children: [
                    _Fact(
                      icon: Icons.people_alt_rounded,
                      label: '${room.onlineCount} 人在线',
                    ),
                    if (room.hasPassword)
                      const _Fact(icon: Icons.lock_rounded, label: '需要密码'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ink = AlistenColors.of(context).onGlassMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AlistenSizes.inlineIcon, color: ink),
        const SizedBox(width: AlistenSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: AlistenTypography.weighted(
              AlistenTypography.secondary,
              FontWeight.w600,
            ).copyWith(color: ink),
          ),
        ),
      ],
    );
  }
}
