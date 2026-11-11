import 'dart:async';

import 'package:alisten/app/app_theme.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/invite_confirm_sheet.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/app/share_confirm_sheet.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/avatar/avatar_image.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/data/reminder_notifier.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/features/update/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/avatar_images.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logSource = 'app';

final reminderNotifierProvider = Provider<ReminderNotifier>((ref) {
  throw UnimplementedError('reminderNotifier 未注入');
});

final avatarImageSourceProvider = Provider<ImageProvider Function(String url)>((
  ref,
) {
  final cache = ref.watch(avatarCacheProvider);
  return (url) => AvatarImage(url, cache);
});

final class AlistenApp extends ConsumerStatefulWidget {
  const AlistenApp({super.key});

  @override
  ConsumerState<AlistenApp> createState() => _AlistenAppState();
}

final class _AlistenAppState extends ConsumerState<AlistenApp> {
  late final AppLifecycleListener _lifecycle;
  late final Future<void> _started;

  // 链接或提醒已指定去处时，启动流程不再恢复上次的房间。
  bool _roomOpened = false;

  @override
  void initState() {
    super.initState();
    // 播放控制和播放历史记录常驻，不依赖当前显示的页面。
    ref.listenManual(
      playbackControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    ref.listenManual(historyRecorderProvider, (_, _) {});
    listenForNotices(ref);
    listenForShares(ref);
    listenForInvites(ref, openRoute: _openRoute);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _started = Future.microtask(_start);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_offerUpdate()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    // 管理会话必须最先处理：回到前台后其他逻辑可能立即发请求，
    // 离开太久的会话要先结束。
    ref.read(adminSessionProvider.notifier).handleLifecycle(state);
    ref.read(appVisibleProvider.notifier).follow(state);
    unawaited(ref.read(roomControllerProvider.notifier).handleLifecycle(state));
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(settingsControllerProvider.notifier).refreshPermission(),
      );
      unawaited(_restoreIdentity());
    }
  }

  Future<void> _start() async {
    // 挂载之前平台可能已报告过生命周期，[_lifecycle] 只报告之后的变化。
    if (WidgetsBinding.instance.lifecycleState case final launched?) {
      ref.read(appVisibleProvider.notifier).follow(launched);
    }
    // 不等待：网络慢时不能拖住通知和链接的初始化。
    unawaited(_restoreIdentity());
    try {
      await ref
          .read(reminderNotifierProvider)
          .initialize(onOpenRoom: _openReminderRoom);
    } on Object {
      AppLog.warn(_logSource, 'notifications not initialized');
    }
    if (!mounted) return;
    var launchedByLink = false;
    try {
      launchedByLink = await ref
          .read(deepLinkControllerProvider)
          .start(
            _openRoute,
            onInvalid: _onInvalidLink,
            onOtherServer: (uri) => unawaited(_followOtherServerLink(uri)),
            onPair: _openPairing,
            onOtherServerPair: _onOtherServerPair,
          );
    } on Object {
      AppLog.warn(_logSource, 'links not followed');
    }
    // 房间的启动链接（即使尚未送达）优先于上次的房间。
    if (!mounted || launchedByLink || _roomOpened) return;
    unawaited(ref.read(roomControllerProvider.notifier).restoreLastRoom());
  }

  void _openRoute(String route) {
    _roomOpened = true;
    ref.read(routerProvider).go(route);
  }

  // 旧版本发出的提醒不带服务器，都来自默认服务器。
  void _openReminderRoom(String? serverId, String roomId) {
    final defaultId = ref.read(serverDirectoryProvider).defaultId;
    if ((serverId ?? defaultId) == ref.read(currentServerProvider).id) {
      _openRoute('/r/$roomId');
      return;
    }
    // 冷启动时也留在大厅，不能在“歌在另一个服务器上”的提示下进入无关的房间。
    _roomOpened = true;
    ref.read(routerProvider).go('/');
    ref.read(toastControllerProvider).show(ToastKind.info, '这首歌在另一个服务器上');
  }

  void _onInvalidLink() {
    ref.read(routerProvider).go('/');
    ref.read(toastControllerProvider).show(ToastKind.warning, invalidLinkText);
  }

  // 配对码经 extra 传递、不进路由地址：在它有效的几分钟里它就是登录凭据。
  // 不算打开了房间，启动流程照常恢复上次的房间。
  void _openPairing(String fragment) {
    ref
        .read(routerProvider)
        .go(
          '/settings/account/pair',
          extra: (
            serverId: ref.read(currentServerProvider).id,
            fragment: fragment,
          ),
        );
  }

  void _onOtherServerPair(String authority) {
    ref
        .read(toastControllerProvider)
        .show(ToastKind.warning, '这个配对码属于 $authority，先切换到这个服务器再输入。');
  }

  // 仅凭路径无法判断是否为 Alisten（如 reddit 的 `/r/<名字>`），
  // 需要询问该网站。
  Future<void> _followOtherServerLink(Uri uri) async {
    final invite = await ref.read(inviteRecognizerProvider).recognize('$uri');
    if (!mounted) return;
    if (invite == null) {
      _onInvalidLink();
    } else {
      ref.read(inviteOfferControllerProvider.notifier).offer(invite);
    }
  }

  // 启动链接打开的页面先就位，面板才不会被随后推入的页面盖住；已经打开的面板
  // （如分享、邀请）关闭之后再弹出，不打断它们。出错与自动检查失败一样不打扰
  // 用户，只记 debug 日志。
  Future<void> _offerUpdate() async {
    try {
      final updates = ref.read(updateControllerProvider.notifier);
      final update = await updates.checkOnLaunch();
      if (update == null || !mounted) return;
      await _started;
      await SchedulerBinding.instance.endOfFrame;
      final navigator = await _uncoveredRootNavigator();
      if (navigator == null || !mounted || !updates.claimLaunchOffer(update)) {
        return;
      }
      await showUpdateSheet(
        navigator.context,
        update,
        onNotice: ref.read(toastControllerProvider).show,
      );
    } on Object catch (error) {
      AppLog.debug(
        'update',
        'update not offered',
        type: '${error.runtimeType}',
      );
    }
  }

  Future<NavigatorState?> _uncoveredRootNavigator() async {
    while (mounted) {
      final navigator = ref
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentState;
      if (navigator == null) return null;
      Route<Object?>? top;
      // 导航器不公开栈顶路由；谓词首次返回 true 时 popUntil 即停止，不弹出
      // 任何路由。
      navigator.popUntil((route) {
        top = route;
        return true;
      });
      final panel = top;
      if (panel is! PopupRoute<Object?>) return navigator;
      await panel.popped;
    }
    return null;
  }

  // 回到前台时也读一次：账号可能已在别处退出，记录开关和邮箱可能被其他设备
  // 改过。restore 没有 memberToken 时不发请求。
  Future<void> _restoreIdentity() async {
    try {
      await ref.read(identityControllerProvider.notifier).restore();
      await ref.read(accountControllerProvider).migrateLocalEmail();
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'identity restore failed',
        code: error is ApiException ? error.code : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themes = ref.watch(appThemeProvider);
    final router = ref.watch(routerProvider);
    final toasts = ref.watch(toastControllerProvider);
    final covers = ref.watch(coverImageSourceProvider);
    final avatars = ref.watch(avatarImageSourceProvider);
    return _ForegroundTickerMode(
      child: CoverImages(
        resolve: covers,
        child: AvatarImages(
          resolve: avatars,
          // 在 MaterialApp 之上读取 MediaQuery，主题动画才能遵循系统的
          // 减少动态效果设置。
          child: MediaQuery.fromView(
            view: View.of(context),
            child: Builder(
              builder: (context) => MaterialApp.router(
                title: 'Alisten',
                theme: themes.light,
                darkTheme: themes.dark,
                themeMode: themes.mode,
                themeAnimationDuration: AlistenDurations.of(
                  context,
                  AlistenDurations.theme,
                ),
                themeAnimationCurve: AlistenCurves.standard,
                locale: _locale,
                supportedLocales: const [_locale],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                routerConfig: router,
                builder: (context, child) =>
                    ToastHost(controller: toasts, child: child!),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _locale = Locale('zh', 'CN');

final class _ForegroundTickerMode extends ConsumerWidget {
  const _ForegroundTickerMode({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TickerMode(enabled: ref.watch(appVisibleProvider), child: child);
  }
}
