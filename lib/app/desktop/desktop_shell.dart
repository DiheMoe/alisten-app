import 'dart:async';

import 'package:alisten/app/desktop/desktop_keys.dart';
import 'package:alisten/app/mini_player.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:alisten/shared/ui/hover_glow.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/window_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面窗口里房间之外的页面：左边是悬浮的导航，右边是当前页面；在房间里时页面
/// 下方悬着迷你播放条。房间自己的窗口盖在它上面。
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({required this.location, required this.child, super.key});

  final Uri location;
  final Widget child;

  static const _sidebarWidth =
      AlistenSpacing.sm + AlistenSizes.iconButton + 2 * AlistenSpacing.xs;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  // 到过的位置，鼠标侧键像浏览器那样在其中后退和前进。
  final _visited = <Uri>[];
  int _visitedAt = -1;

  @override
  void initState() {
    super.initState();
    _visit(widget.location);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(DesktopShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visit(widget.location);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // 后退或前进到的位置就是 [_visitedAt] 指着的那个，不算新到的地方。
  void _visit(Uri location) {
    if (_visitedAt >= 0 && _visited[_visitedAt] == location) return;
    _visited
      ..removeRange(_visitedAt + 1, _visited.length)
      ..add(location);
    if (_visited.length > _visitedLimit) _visited.removeAt(0);
    _visitedAt = _visited.length - 1;
  }

  void _travel(int step) {
    final rooms = ref.read(roomControllerProvider.notifier);
    for (
      var at = _visitedAt + step;
      at >= 0 && at < _visited.length;
      at += step
    ) {
      final segments = _visited[at].pathSegments;
      // 后退和前进不进房间也不换房间：已经离开的房间的页面跳过。
      if (segments.length >= 2 &&
          segments.first == 'r' &&
          !rooms.names(segments[1])) {
        continue;
      }
      _visitedAt = at;
      GoRouter.of(context).go('${_visited[at]}');
      return;
    }
  }

  // 侧键在窗口的任何地方都管用，所以不经过命中测试。
  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    final back = event.buttons & kBackMouseButton != 0;
    final forward = event.buttons & kForwardMouseButton != 0;
    if (back == forward) return;
    _step(back: back);
  }

  // Alt 加左右方向键，和鼠标侧键一样后退、前进。
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    final back = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    if (!back && event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    _step(back: back);
    return true;
  }

  void _step({required bool back}) {
    // 对话框开着时，后退先关掉它。
    final navigator = Navigator.of(context, rootNavigator: true);
    Route<Object?>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    if (top is PopupRoute) {
      if (back) unawaited(navigator.maybePop());
      return;
    }
    _travel(back ? -1 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final media = MediaQuery.of(context);
    return DesktopKeys(
      location: location,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isWindowsDesktop) const WindowDragStrip(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: DesktopShell._sidebarWidth,
                  child: _Sidebar(location: location),
                ),
                Expanded(
                  child: LayoutBuilder(
                    // 页面按自己这一块的大小排版，而不是整个窗口。
                    builder: (context, constraints) => MediaQuery(
                      data: media.copyWith(size: constraints.biggest),
                      child: ClipRect(
                        child: SidebarPage(
                          active: _sidebarPages.contains(location.path),
                          child: MiniPlayerHost(
                            location: location,
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _sidebarPages = {'/playlists', '/history', '/settings'};
const _visitedLimit = 50;

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});

  final Uri location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final member = ref.watch(
      identityControllerProvider.select(
        (state) => switch (state.member) {
          final member? => (name: member.name, avatarUrl: member.avatarUrl),
          null => null,
        },
      ),
    );
    final path = location.path;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.sm,
        AlistenSpacing.sm,
        0,
        AlistenSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.glassFill,
          borderRadius: BorderRadius.circular(AlistenRadii.md),
          border: Border.all(color: colors.glassStroke),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AlistenSpacing.xs),
          child: Column(
            children: [
              _NavItem(
                icon: AlistenIcons.door,
                label: '大厅',
                selected: path == '/',
                onPressed: () => context.go('/'),
              ),
              _NavItem(
                icon: AlistenIcons.playlist,
                label: '我的歌单',
                selected:
                    path.startsWith('/playlists') || path.startsWith('/s/'),
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
                avatar: member == null
                    ? null
                    : MemberAvatar(
                        name: member.name,
                        imageUrl: member.avatarUrl,
                      ),
                label: '设置',
                selected: path.startsWith('/settings'),
                onPressed: () => context.go('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 只有图标，名称由读屏读出。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.avatar,
  });

  final IconData icon;

  /// 有身份时代替图标显示的头像。
  final Widget? avatar;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final radius = BorderRadius.circular(AlistenRadii.sm);
    return Padding(
      padding: const EdgeInsets.only(bottom: AlistenSpacing.xxs),
      child: Pressable(
        onPressed: onPressed,
        selected: selected,
        semanticLabel: label,
        focusRadius: radius,
        child: AnimatedContainer(
          duration: AlistenDurations.of(context, AlistenDurations.short),
          curve: AlistenCurves.standard,
          width: AlistenSizes.iconButton,
          height: AlistenSizes.iconButton,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? colors.selectedFill
                : colors.selectedFill.withValues(alpha: 0),
            borderRadius: radius,
          ),
          child: HoverPop(
            child:
                avatar ??
                Icon(icon, size: AlistenSizes.icon, color: colors.onGlass),
          ),
        ),
      ),
    );
  }
}
