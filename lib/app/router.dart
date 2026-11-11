import 'dart:async';

import 'package:alisten/app/app_version.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/mini_player.dart';
import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/room/room_screen.dart';
import 'package:alisten/app/room_route_gate.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' show protocolVersion;
import 'package:alisten/domain/room/room_route.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/lobby/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _pages = {
  '/',
  '/history',
  '/playlists',
  '/settings',
  '/settings/licenses',
  '/settings/servers',
  '/settings/admin',
  '/settings/account/login',
  '/settings/account/register',
  '/settings/account/pair',
};

const invalidLinkText = '链接无效，已回到大厅';

// 房间路由之下的相对路径片段，不是完整位置。
const songSearchSegment = 'search';
const playlistSegment = 'playlists/netease/:id';

final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigator = GlobalKey<NavigatorState>(debugLabel: 'root');
  final toasts = ref.read(toastControllerProvider);
  void reportPick(MutationResult<Object?> result, String success) {
    reportMutation(toasts, result, success: (_) => success);
  }

  void notice(String text) => toasts.show(ToastKind.warning, text);

  // 面板在根导航器上，链接换掉打开它的页面后仍开着，所以不用页面的 context 跳转。
  late final GoRouter router;
  void openAccount() => router.go('/settings');

  router = GoRouter(
    navigatorKey: rootNavigator,
    redirect: (context, state) {
      final uri = state.uri;
      final segments = uri.pathSegments;
      if (_pages.contains(uri.path) ||
          roomRoute(segments, sections: DeepLinkController.appSections) !=
              null ||
          _isPlaylistPage(segments)) {
        return null;
      }
      // 重定向可能在路由构建期间执行，不能在这时显示提示。
      scheduleMicrotask(() => toasts.show(ToastKind.warning, invalidLinkText));
      return '/';
    },
    errorBuilder: (context, state) => const _LostPage(),
    routes: [
      ShellRoute(
        pageBuilder: (context, state, child) => MaterialPage(
          key: state.pageKey,
          child: MiniPlayerHost(location: state.uri, child: child),
        ),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: _page(
              (context, state) => LobbyScreen(
                onOpenRoom: (roomRef) => context.go('/r/$roomRef'),
                onOpenPlaylists: () => context.go('/playlists'),
                onOpenHistory: () => context.go('/history'),
                onOpenSettings: () => context.go('/settings'),
                onNotice: toasts.show,
              ),
            ),
            routes: [
              GoRoute(
                path: 'history',
                pageBuilder: _page(
                  (context, state) => HistoryScreen(
                    onResult: reportPick,
                    onNotice: toasts.show,
                    onCopyTitle: (title) => copySongTitle(toasts, title),
                    saveToPlaylist: (track, title) => SaveToPlaylistButton(
                      track: track,
                      title: title,
                      onOpenAccount: openAccount,
                      onNotice: toasts.show,
                      iconSize: AlistenSizes.iconSm,
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: 'playlists',
                pageBuilder: _page(
                  (context, state) => MyPlaylistsScreen(
                    onOpenPlaylist: (id) => context.go('/playlists/$id'),
                    onOpenAccount: openAccount,
                    onNotice: toasts.show,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: _page(
                      (context, state) => MyPlaylistScreen(
                        id: state.pathParameters['id']!,
                        onResult: reportPick,
                        onNotice: toasts.show,
                        onCopyTitle: (title) => copySongTitle(toasts, title),
                        onOpenAccount: openAccount,
                        onDeleted: () => context.go('/playlists'),
                      ),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'settings',
                pageBuilder: _page(
                  (context, state) => SettingsScreen(
                    appVersion: appVersion,
                    protocolVersion: protocolVersion,
                    onProfileResult: (result) =>
                        reportMutation(toasts, result, success: (_) => '资料已保存'),
                    onNotice: toasts.show,
                    onOpenLicenses: () => context.go('/settings/licenses'),
                    onOpenServers: () => context.go('/settings/servers'),
                    onOpenAdmin: () => context.go('/settings/admin'),
                    accountActions: AccountActions(
                      onOpenLogin: () => context.go('/settings/account/login'),
                      onOpenRegister: () =>
                          context.go('/settings/account/register'),
                      onNotice: toasts.show,
                    ),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'licenses',
                    pageBuilder: _page(
                      (context, state) => const LicensesScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'servers',
                    pageBuilder: _page(
                      (context, state) => ServerScreen(
                        onSwitched: () => context.go('/'),
                        onNotice: toasts.show,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'account/login',
                    pageBuilder: _page(
                      (context, state) => LoginScreen(
                        onDone: () => context.go('/settings'),
                        onOpenRegister: () =>
                            context.go('/settings/account/register'),
                        onOpenPairing: () =>
                            context.go('/settings/account/pair'),
                        onNotice: toasts.show,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'account/register',
                    pageBuilder: _page(
                      (context, state) => RegisterScreen(
                        onDone: () {
                          toasts.show(ToastKind.success, '已注册');
                          context.go('/settings');
                        },
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'account/pair',
                    pageBuilder: _page((context, state) {
                      final extra = state.extra;
                      return PairScreen(
                        prefill: extra is PairPrefill ? extra : null,
                        onDone: () {
                          toasts.show(ToastKind.success, '已登录');
                          context.go('/settings');
                        },
                      );
                    }),
                  ),
                  GoRoute(
                    path: 'admin',
                    parentNavigatorKey: rootNavigator,
                    // 管理 token 只在后台页面存续期间有效。后台里可能开关了注册或
                    // GitHub 登录，回到设置页时重新读取站点能力。
                    onExit: (context, state) {
                      ref.read(adminSessionProvider.notifier).end();
                      ref.invalidate(siteCapabilitiesProvider);
                      return true;
                    },
                    pageBuilder: _page(
                      (context, state) => AdminScreen(
                        onNotice: toasts.show,
                        onExit: () => context.go('/settings'),
                        onOpenRoom: (roomRef) => context.go('/r/$roomRef'),
                      ),
                    ),
                  ),
                ],
              ),
              for (final mode in RoomMode.values)
                GoRoute(
                  path: _roomPath(mode),
                  parentNavigatorKey: rootNavigator,
                  pageBuilder: (context, state) =>
                      _roomPage(state.pathParameters['ref']!, mode),
                  routes: [
                    if (mode == RoomMode.player) ...[
                      GoRoute(
                        path: songSearchSegment,
                        parentNavigatorKey: rootNavigator,
                        pageBuilder: _page(task: true, (context, state) {
                          final roomRef = state.pathParameters['ref']!;
                          return RoomRouteGate(
                            roomRef: roomRef,
                            child: SearchScreen(
                              onResult: reportPick,
                              onNotice: notice,
                              // 歌单页叠在点歌页之上，返回时点歌页保持原样。
                              onOpenPlaylist: (playlist) => unawaited(
                                context.push<void>(
                                  '/r/$roomRef/playlists/'
                                  '${playlist.source.name}/${playlist.id}',
                                ),
                              ),
                              onShowQueue: () =>
                                  context.go(RoomMode.queue.routeIn(roomRef)),
                              onOpenRoom: context.go,
                            ),
                          );
                        }),
                      ),
                      GoRoute(
                        path: playlistSegment,
                        parentNavigatorKey: rootNavigator,
                        pageBuilder: _page(
                          (context, state) => RoomRouteGate(
                            roomRef: state.pathParameters['ref']!,
                            child: PlaylistScreen(
                              source: TrackSource.netease,
                              id: state.pathParameters['id']!,
                              onResult: reportPick,
                              onNotice: notice,
                              saveAsMine: (name) => SavePlatformPlaylistButton(
                                playlistId: state.pathParameters['id']!,
                                name: name,
                                onOpenAccount: openAccount,
                                onNotice: toasts.show,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ],
      ),
    ],
  );
  final stopReleasingFocus = _releaseFocusWhenLeaving(router);
  ref.onDispose(() {
    stopReleasingFocus();
    router.dispose();
  });
  return router;
});

// 被盖住或替换的页面重新露出时，框架会把焦点还给它最后聚焦的输入框并弹出键盘。
// 因此无论跳转由谁发起，离开页面前都先让输入框失去焦点；按钮和卡片的焦点保留，
// 键盘用户返回后仍停在原处。
VoidCallback _releaseFocusWhenLeaving(GoRouter router) {
  final delegate = router.routerDelegate;
  var page = _pageOf(delegate.currentConfiguration);
  void changed() {
    final next = _pageOf(delegate.currentConfiguration);
    if (next == page) return;
    page = next;
    final focus = FocusManager.instance.primaryFocus;
    final typing =
        focus?.context?.findAncestorStateOfType<EditableTextState>() != null;
    if (typing) focus!.unfocus();
  }

  delegate.addListener(changed);
  return () => delegate.removeListener(changed);
}

// 房间的各个模式是同一个页面，切换模式不算离开。
Object? _pageOf(RouteMatchList matches) {
  if (matches.isEmpty) return null;
  final last = matches.last;
  return _roomPaths.contains(last.route.path)
      ? _roomPageKey
      : last.matchedLocation;
}

String _roomPath(RoomMode mode) =>
    mode.path == null ? 'r/:ref' : 'r/:ref/${mode.path}';

final _roomPaths = {for (final mode in RoomMode.values) _roomPath(mode)};

// 所有房间路由共用一个 key，切换模式或 ref 时原地更新页面，而不是替换。
const _roomPageKey = ValueKey('room');

Page<void> _roomPage(String roomRef, RoomMode mode) {
  return MaterialPage(
    key: _roomPageKey,
    child: RoomRouteGate(
      roomRef: roomRef,
      child: RoomScreen(roomRef: roomRef, mode: mode),
    ),
  );
}

// 页面都由这里给出：go_router 按 material_ui 的 MaterialApp 判断应用类型，认不出
// flutter/material 的 MaterialApp，只给 builder 的路由会退回没有转场的页面。
//
// [task] 页面从底部升起。Apple 平台除外：全屏对话框没有边缘滑动返回。
GoRouterPageBuilder _page(GoRouterWidgetBuilder builder, {bool task = false}) {
  return (context, state) {
    final platform = Theme.of(context).platform;
    return MaterialPage(
      key: state.pageKey,
      name: state.name ?? state.path,
      restorationId: state.pageKey.value,
      fullscreenDialog:
          task &&
          platform != TargetPlatform.iOS &&
          platform != TargetPlatform.macOS,
      child: Builder(builder: (context) => builder(context, state)),
    );
  };
}

// 歌单 ID 由服务端给出，App 不假设它的格式。
bool _isPlaylistPage(List<String> segments) =>
    segments.length == 2 &&
    segments.first == 'playlists' &&
    segments[1].isNotEmpty;

class _LostPage extends StatelessWidget {
  const _LostPage();

  @override
  Widget build(BuildContext context) {
    return AlistenScaffold(
      body: EmptyState(
        icon: Icons.link_off_rounded,
        title: '找不到这个页面',
        message: '链接可能有误或已过期。',
        action: PillButton(label: '返回大厅', onPressed: () => context.go('/')),
      ),
    );
  }
}
