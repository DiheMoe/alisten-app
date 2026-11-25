import 'dart:async';

import 'package:alisten/app/app_theme.dart';
import 'package:alisten/app/desktop/desktop_player_bar.dart';
import 'package:alisten/app/desktop/desktop_room.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/flowing_cover_backdrop.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面窗口的骨架：左边导航，中间是当前页面，底部是常驻的播放条；页面属于
/// 所在房间时，右边同时显示队列和聊天。
class DesktopShell extends ConsumerWidget {
  const DesktopShell({required this.location, required this.child, super.key});

  final Uri location;
  final Widget child;

  static const _sidebarWidth = 208.0;
  static const _minPanelWidth = 300.0;
  static const _maxPanelWidth = 360.0;
  // 窗口再窄，中间放不下封面和歌词，右边的队列和聊天让出位置。
  static const _minStageWidth = 400.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (roomId, cover) = ref.watch(
      roomControllerProvider.select(
        (room) =>
            (room.activeRoomId, room.snapshot?.nowPlaying?.entry.meta.coverUrl),
      ),
    );
    final segments = location.pathSegments;
    final routeRoom = segments.length >= 2 && segments.first == 'r'
        ? segments[1]
        : null;
    final inRoom = roomId != null;
    final onRoomPage =
        inRoom &&
        routeRoom != null &&
        ref.read(roomControllerProvider.notifier).names(routeRoom);
    final media = MediaQuery.of(context);
    final router = GoRouter.of(context);
    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      final keyboard = HardwareKeyboard.instance;
      if (key == LogicalKeyboardKey.escape && router.canPop()) {
        router.pop();
        return KeyEventResult.handled;
      }
      if (!inRoom) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyK &&
          (keyboard.isControlPressed || keyboard.isMetaPressed)) {
        final room = ref.read(roomControllerProvider);
        final search = '/r/${room.roomSlug ?? roomId}/search';
        if (location.path != search) unawaited(router.push<void>(search));
        return KeyEventResult.handled;
      }
      // 正在输入时空格是文字。
      final typing =
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() !=
          null;
      if (key == LogicalKeyboardKey.space && !typing) {
        unawaited(
          ref.read(playbackControllerProvider.notifier).toggleLocalPause(),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: onKey,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RoomTheme(
              child: inRoom
                  ? FlowingCoverBackdrop(url: cover)
                  : Builder(
                      builder: (context) => ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                      ),
                    ),
            ),
            Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final panelWidth = (constraints.maxWidth * 0.27).clamp(
                        _minPanelWidth,
                        _maxPanelWidth,
                      );
                      final showPanel =
                          onRoomPage &&
                          constraints.maxWidth - _sidebarWidth - panelWidth >=
                              _minStageWidth;
                      final stageWidth =
                          constraints.maxWidth -
                          _sidebarWidth -
                          (showPanel ? panelWidth : 0);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _sidebarWidth,
                            child: RoomTheme(
                              child: _Sidebar(location: location),
                            ),
                          ),
                          Expanded(
                            // 页面按自己这一块的大小排版，而不是整个窗口。
                            child: MediaQuery(
                              data: media.copyWith(
                                size: Size(stageWidth, constraints.maxHeight),
                              ),
                              child: ClipRect(
                                child: SidebarPage(
                                  active: _sidebarPages.contains(location.path),
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                          if (showPanel)
                            SizedBox(
                              width: panelWidth,
                              child: const RoomTheme(child: DesktopRoomPanel()),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (inRoom) const RoomTheme(child: DesktopPlayerBar()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _sidebarPages = {'/playlists', '/history', '/settings'};

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});

  final Uri location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final avatarUrl = ref.watch(
      identityControllerProvider.select((state) => state.member?.avatarUrl),
    );
    final room = ref.watch(
      roomControllerProvider.select(
        (room) => (
          id: room.activeRoomId,
          slug: room.roomSlug,
          name: room.snapshot?.room.name ?? room.roomName,
          online: room.snapshot?.onlineCount,
          capacity: room.snapshot?.room.capacity,
        ),
      ),
    );
    final path = location.path;
    final roomId = room.id;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFill,
        border: BorderDirectional(
          end: BorderSide(
            color: colors.onGlass.withValues(alpha: 0.08),
            width: AlistenSizes.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AlistenSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (roomId != null) ...[
              _RoomCard(
                name: room.name ?? '',
                online: room.online,
                capacity: room.capacity,
                selected: path.startsWith('/r/'),
                onPressed: () => context.go('/r/${room.slug ?? roomId}'),
              ),
              const SizedBox(height: AlistenSpacing.sm),
            ],
            _NavItem(
              icon: AlistenIcons.door,
              label: '大厅',
              selected: path == '/',
              onPressed: () => context.go('/'),
            ),
            _NavItem(
              icon: AlistenIcons.playlist,
              label: '我的歌单',
              selected: path.startsWith('/playlists') || path.startsWith('/s/'),
              onPressed: () => context.go('/playlists'),
            ),
            _NavItem(
              icon: AlistenIcons.clockCounterClockwise,
              label: '播放历史',
              selected: path == '/history',
              onPressed: () => context.go('/history'),
            ),
            const Spacer(),
            _NavItem(
              icon: AlistenIcons.gearSix,
              image: avatarUrl == null
                  ? null
                  : avatarImageOf(context, avatarUrl),
              label: '设置',
              selected: path.startsWith('/settings'),
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.image,
  });

  final IconData icon;
  final ImageProvider? image;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final image = this.image;
    return Padding(
      padding: const EdgeInsets.only(bottom: AlistenSpacing.xxs / 2),
      child: Pressable(
        onPressed: onPressed,
        selected: selected,
        focusRadius: BorderRadius.circular(AlistenRadii.sm),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? colors.selectedFill : null,
            borderRadius: BorderRadius.circular(AlistenRadii.sm),
          ),
          child: Row(
            children: [
              if (image != null)
                CircleAvatar(
                  radius: AlistenSizes.iconSm / 2,
                  backgroundColor: colors.onGlass.withValues(alpha: 0.08),
                  foregroundImage: image,
                )
              else
                Icon(icon, size: AlistenSizes.iconSm, color: colors.onGlass),
              const SizedBox(width: AlistenSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (selected
                              ? AlistenTypography.bodyStrong
                              : AlistenTypography.body)
                          .copyWith(color: colors.onGlass),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.name,
    required this.online,
    required this.capacity,
    required this.selected,
    required this.onPressed,
  });

  final String name;
  final int? online;
  final int? capacity;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final online = this.online;
    final capacity = this.capacity;
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '打开房间 $name',
      focusRadius: BorderRadius.circular(AlistenRadii.sm),
      child: Container(
        padding: const EdgeInsets.all(AlistenSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colors.raised : colors.glassFill,
          borderRadius: BorderRadius.circular(AlistenRadii.sm),
          border: Border.all(
            color: selected ? colors.control : colors.glassStroke,
            width: selected ? 1.5 : AlistenSizes.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AlistenTypography.bodyStrong.copyWith(
                color: colors.onGlass,
              ),
            ),
            if (online != null && capacity != null) ...[
              const SizedBox(height: AlistenSpacing.xxs / 2),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AlistenSpacing.xxs + 2),
                  Text(
                    '$online / $capacity',
                    style: AlistenTypography.caption.copyWith(
                      color: colors.success,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
