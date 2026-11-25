import 'dart:async';

import 'package:alisten/app/desktop/desktop_room.dart';
import 'package:alisten/app/desktop/desktop_shell.dart';
import 'package:alisten/app/app_theme.dart';
import 'package:alisten/app/app_version.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/mini_player.dart';
import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/room/room_screen.dart';
import 'package:alisten/app/room_route_gate.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' show protocolVersion;
import 'package:alisten/domain/playlist/share_route.dart';
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
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/page_routes.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _pages = {
  '/',
  '/history',
  '/playlists',
  '/settings',
  '/settings/account',
  '/settings/appearance',
  '/settings/notifications',
  '/settings/privacy',
  '/settings/privacy/history',
  '/settings/storage',
  '/settings/about',
  '/settings/about/licenses',
  '/settings/servers',
  '/settings/admin',
  for (final section in AdminSection.values) '/settings/admin/${section.path}',
  '/settings/account/login',
  '/settings/account/register',
  '/settings/account/pair',
};

const invalidLinkText = '链接无效，已回到大厅';

// 房间路由之下的相对路径片段，不是完整位置。
const songSearchSegment = 'search';
const playlistSegment = 'playlists/:source/:id';

final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigator = GlobalKey<NavigatorState>(debugLabel: 'root');
  // 手机上房间盖住整个屏幕；桌面上它是窗口骨架里的一页，侧栏和播放条不动。
  final roomNavigator = isDesktopPlatform ? null : rootNavigator;
  final toasts = ref.read(toastControllerProvider);
  void reportPick(MutationResult<Object?> result, String success) {
    reportMutation(toasts, result, success: (_) => success);
  }

  void notice(String text) => toasts.show(ToastKind.warning, text);

  // 面板在根导航器上，链接换掉打开它的页面后仍开着，所以不用页面的 context 跳转。
  late final GoRouter router;
  void openAccount() => router.go('/settings/account');

  // 房间里点歌的两个入口：搜索平台（或粘贴链接），或者从自己的歌单里点。
  Widget songs(
    BuildContext context,
    GoRouterState state, {
    required bool fromPlaylists,
  }) {
    final roomRef = state.pathParameters['ref']!;
    return RoomTheme(
      child: RoomRouteGate(
        roomRef: roomRef,
        child: SearchScreen(
          onResult: reportPick,
          onNotice: notice,
          // 歌单页叠在点歌页之上，返回时点歌页保持原样。
          onOpenPlaylist: (playlist) => unawaited(
            context.push<void>(
              '/r/$roomRef/playlists/${playlist.source.name}/${playlist.id}',
            ),
          ),
          onShowQueue: () => context.go(RoomMode.queue.routeIn(roomRef)),
          onOpenRoom: context.go,
          libraryOnly: fromPlaylists,
          library: fromPlaylists
              ? SearchLibrary(
                  label: '我的歌单',
                  hint: '在选中的歌单里找歌',
                  builder: (context, filter, onPick) => MyPlaylistsPicker(
                    filter: filter,
                    onPick: onPick,
                    onOpenAccount: openAccount,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget history(BuildContext context, GoRouterState state) => HistoryScreen(
    onResult: reportPick,
    onNotice: toasts.show,
    onCopyTitle: (title) => copySongTitle(toasts, title),
    saveToPlaylist: (from, track, title) => unawaited(
      showSaveToPlaylistSheet(
        from,
        SaveOneTrack(track: track, title: title),
        onOpenAccount: openAccount,
        onNotice: toasts.show,
      ),
    ),
  );

  router = GoRouter(
    navigatorKey: rootNavigator,
    redirect: (context, state) {
      final uri = state.uri;
      final segments = uri.pathSegments;
      if (_pages.contains(uri.path) ||
          roomRoute(segments, sections: DeepLinkController.appSections) !=
              null ||
          _isPlaylistPage(segments) ||
          sharedPlaylistRoute(segments) != null) {
        return null;
      }
      // 重定向可能在路由构建期间执行，不能在这时显示提示。
      scheduleMicrotask(() => toasts.show(ToastKind.warning, invalidLinkText));
      return '/';
    },
    errorBuilder: (context, state) => const _LostPage(),
    routes: [
      ShellRoute(
        pageBuilder: (context, state, child) => AlistenPage<void>(
          key: state.pageKey,
          child: isDesktopPlatform
              ? DesktopShell(location: state.uri, child: child)
              : MiniPlayerHost(location: state.uri, child: child),
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
              GoRoute(path: 'history', pageBuilder: _page(history)),
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
                path: 's/:shareId',
                pageBuilder: _page(
                  (context, state) => SharedPlaylistScreen(
                    shareId: state.pathParameters['shareId']!,
                    onResult: reportPick,
                    onNotice: toasts.show,
                    onCopyTitle: (title) => copySongTitle(toasts, title),
                    onOpenAccount: openAccount,
                  ),
                ),
              ),
              GoRoute(
                path: 'settings',
                pageBuilder: _pushPage(
                  (context, state) => SettingsScreen(
                    appVersion: appVersion,
                    onOpen: (section) =>
                        context.go('/settings/${section.path}'),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: SettingsSection.account.path,
                    pageBuilder: _pushPage(
                      (context, state) => AccountSettingsScreen(
                        onProfileResult: (result) => reportMutation(
                          toasts,
                          result,
                          success: (_) => '资料已保存',
                        ),
                        accountActions: AccountActions(
                          onOpenLogin: () =>
                              context.go('/settings/account/login'),
                          onOpenRegister: () =>
                              context.go('/settings/account/register'),
                          onNotice: toasts.show,
                        ),
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'login',
                        pageBuilder: _pushPage(
                          (context, state) => LoginScreen(
                            onDone: () => context.go('/settings/account'),
                            onOpenRegister: () =>
                                context.go('/settings/account/register'),
                            onOpenPairing: () =>
                                context.go('/settings/account/pair'),
                            onNotice: toasts.show,
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'register',
                        pageBuilder: _pushPage(
                          (context, state) => RegisterScreen(
                            onDone: () {
                              toasts.show(ToastKind.success, '已注册');
                              context.go('/settings/account');
                            },
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'pair',
                        pageBuilder: _pushPage((context, state) {
                          final extra = state.extra;
                          return PairScreen(
                            prefill: extra is PairPrefill ? extra : null,
                            onDone: () {
                              toasts.show(ToastKind.success, '已登录');
                              context.go('/settings/account');
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: SettingsSection.appearance.path,
                    pageBuilder: _pushPage(
                      (context, state) => const AppearanceSettingsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: SettingsSection.notifications.path,
                    pageBuilder: _pushPage(
                      (context, state) =>
                          NotificationSettingsScreen(onNotice: toasts.show),
                    ),
                  ),
                  GoRoute(
                    path: SettingsSection.privacy.path,
                    pageBuilder: _pushPage(
                      (context, state) => PrivacySettingsScreen(
                        onNotice: toasts.show,
                        // 从这里看的播放历史返回这里，不回大厅。
                        onOpenHistory: () =>
                            context.go('/settings/privacy/history'),
                      ),
                    ),
                    routes: [
                      GoRoute(path: 'history', pageBuilder: _pushPage(history)),
                    ],
                  ),
                  GoRoute(
                    path: SettingsSection.storage.path,
                    pageBuilder: _pushPage(
                      (context, state) =>
                          StorageSettingsScreen(onNotice: toasts.show),
                    ),
                  ),
                  GoRoute(
                    path: SettingsSection.about.path,
                    pageBuilder: _pushPage(
                      (context, state) => AboutSettingsScreen(
                        appVersion: appVersion,
                        protocolVersion: protocolVersion,
                        onNotice: toasts.show,
                        onOpenLicenses: () =>
                            context.go('/settings/about/licenses'),
                        onOpenServers: () => context.go('/settings/servers'),
                        onOpenAdmin: () => context.go('/settings/admin'),
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'licenses',
                        pageBuilder: _pushPage(
                          (context, state) => const LicensesScreen(),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'servers',
                    pageBuilder: _pushPage(
                      (context, state) => ServerScreen(
                        onSwitched: () => context.go('/'),
                        onNotice: toasts.show,
                      ),
                    ),
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
                    pageBuilder: _pushPage(
                      (context, state) => AdminScreen(
                        onExit: () => context.go('/settings'),
                        onOpenSection: (section) =>
                            context.go('/settings/admin/${section.path}'),
                      ),
                    ),
                    routes: [
                      for (final section in AdminSection.values)
                        GoRoute(
                          path: section.path,
                          parentNavigatorKey: rootNavigator,
                          pageBuilder: _pushPage(
                            (context, state) => adminSectionScreen(
                              section,
                              onNotice: toasts.show,
                              onOpenRoom: (roomRef) =>
                                  context.go('/r/$roomRef'),
                              // 离开后台时会话随之结束，正在退出的子页面不能把位置拉回后台。
                              onEnded: () {
                                if (router.state.uri.path.startsWith(
                                  '/settings/admin',
                                )) {
                                  router.go('/settings/admin');
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              for (final mode in RoomMode.values)
                GoRoute(
                  path: _roomPath(mode),
                  parentNavigatorKey: roomNavigator,
                  pageBuilder: (context, state) =>
                      _roomPage(state.pathParameters['ref']!, mode),
                  routes: [
                    if (mode == RoomMode.player) ...[
                      GoRoute(
                        path: songSearchSegment,
                        parentNavigatorKey: roomNavigator,
                        pageBuilder: _page(
                          task: true,
                          (context, state) =>
                              songs(context, state, fromPlaylists: false),
                        ),
                      ),
                      GoRoute(
                        path: pickFromPlaylistsSegment,
                        parentNavigatorKey: roomNavigator,
                        pageBuilder: _page(
                          task: true,
                          (context, state) =>
                              songs(context, state, fromPlaylists: true),
                        ),
                      ),
                      GoRoute(
                        path: playlistSegment,
                        parentNavigatorKey: roomNavigator,
                        pageBuilder: _page((context, state) {
                          // 重定向已经按 roomRoute 只放行网易云和 QQ 音乐。
                          final source = TrackSource.values.byName(
                            state.pathParameters['source']!,
                          );
                          final id = state.pathParameters['id']!;
                          return RoomTheme(
                            child: RoomRouteGate(
                              roomRef: state.pathParameters['ref']!,
                              child: PlaylistScreen(
                                source: source,
                                id: id,
                                onResult: reportPick,
                                onNotice: notice,
                                saveAsMine: (name) =>
                                    SavePlatformPlaylistButton(
                                      source: source,
                                      playlistId: id,
                                      name: name,
                                      onOpenAccount: openAccount,
                                      onNotice: toasts.show,
                                    ),
                              ),
                            ),
                          );
                        }),
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
  return AlistenPage(
    key: _roomPageKey,
    returnTo: roomZoomTag,
    child: RoomTheme(
      child: RoomRouteGate(
        roomRef: roomRef,
        child: isDesktopPlatform
            ? DesktopRoomStage(roomRef: roomRef)
            : RoomScreen(roomRef: roomRef, mode: mode),
      ),
    ),
  );
}

// 页面都由这里给出：go_router 按 material_ui 的 MaterialApp 判断应用类型，认不出
// flutter/material 的 MaterialApp，只给 builder 的路由会退回没有转场的页面。
GoRouterPageBuilder _page(
  GoRouterWidgetBuilder builder, {
  bool task = false,
  bool push = false,
}) {
  return (context, state) => AlistenPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    restorationId: state.pageKey.value,
    task: task,
    push: push,
    child: Builder(builder: (context) => builder(context, state)),
  );
}

// 设置和它下面的页面是普通导航：从右边推入，不从头像或设置里的那一行长出。
GoRouterPageBuilder _pushPage(GoRouterWidgetBuilder builder) =>
    _page(builder, push: true);

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
        icon: AlistenIcons.linkBreak,
        title: '找不到这个页面',
        message: '链接可能有误或已过期。',
        action: PillButton(label: '返回大厅', onPressed: () => context.go('/')),
      ),
    );
  }
}
