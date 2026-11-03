import 'package:alisten/app/room/connection_pill.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/animated_resize.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/popover.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';

class RoomTopBar extends StatefulWidget {
  const RoomTopBar({
    required this.name,
    required this.onlineCount,
    required this.status,
    required this.nextRetryAt,
    required this.onCollapse,
    required this.onInvite,
    required this.onLeave,
    this.onRetryNow,
    this.onAddSong,
    super.key,
  });

  final String name;
  final int onlineCount;
  final RoomConnectionStatus status;
  final DateTime? nextRetryAt;
  final VoidCallback onCollapse;
  final VoidCallback onInvite;
  final VoidCallback onLeave;

  final VoidCallback? onRetryNow;

  final VoidCallback? onAddSong;

  @override
  State<RoomTopBar> createState() => _RoomTopBarState();
}

// 与带前置按钮的 `AlistenTopBar` 中标题的起点一致，连接状态与标题左对齐。
const _titleStart =
    AlistenSpacing.xs + AlistenSizes.minTouchTarget + AlistenSpacing.xxs;

const _onlineDot = 6.0;

class _RoomTopBarState extends State<RoomTopBar> {
  bool _menuOpen = false;

  void _closeMenu() => setState(() => _menuOpen = false);

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final open = widget.status == RoomConnectionStatus.open;
    final motion = AlistenDurations.of(context, AlistenDurations.medium);
    return ToastClearance(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlistenTopBar(
            leading: IconCircleButton(
              icon: Icons.keyboard_arrow_down_rounded,
              semanticLabel: '收起房间',
              style: IconCircleButtonStyle.plain,
              iconSize: AlistenSizes.iconLg,
              onPressed: widget.onCollapse,
            ),
            title: widget.name,
            subtitle: '${widget.onlineCount} 人在线',
            subtitleLeading: Container(
              width: _onlineDot,
              height: _onlineDot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.success,
              ),
            ),
            actions: [
              if (widget.onAddSong case final onAddSong?) ...[
                PillButton(
                  label: '点歌',
                  icon: Icons.add_rounded,
                  glow: true,
                  onPressed: onAddSong,
                ),
                const SizedBox(width: AlistenSpacing.xs),
              ],
              Popover(
                open: _menuOpen,
                onClose: _closeMenu,
                childAnchor: Alignment.bottomRight,
                contentAnchor: Alignment.topRight,
                offset: const Offset(0, AlistenSpacing.xxs),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MenuItem(
                      icon: Icons.person_add_alt_1_rounded,
                      label: '复制邀请链接',
                      ink: colors.onGlass,
                      onPressed: () {
                        _closeMenu();
                        widget.onInvite();
                      },
                    ),
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      label: '退出房间',
                      ink: colors.danger,
                      onPressed: () {
                        _closeMenu();
                        widget.onLeave();
                      },
                    ),
                  ],
                ),
                child: IconCircleButton(
                  icon: Icons.more_horiz_rounded,
                  semanticLabel: '更多',
                  style: IconCircleButtonStyle.plain,
                  expanded: _menuOpen,
                  onPressed: () => setState(() => _menuOpen = !_menuOpen),
                ),
              ),
            ],
          ),
          AnimatedResize(
            duration: motion,
            curve: AlistenCurves.standard,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: motion,
              child: open
                  ? const SizedBox(
                      key: ValueKey('open'),
                      width: double.infinity,
                    )
                  : Padding(
                      key: const ValueKey('not open'),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        _titleStart,
                        0,
                        AlistenSpacing.page,
                        AlistenSpacing.xs,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ConnectionPill(
                          status: widget.status,
                          nextRetryAt: widget.nextRetryAt,
                          onRetryNow: widget.onRetryNow,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.ink,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color ink;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.sm,
            vertical: AlistenSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AlistenSizes.iconSm, color: ink),
              const SizedBox(width: AlistenSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: AlistenTypography.bodyStrong.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
