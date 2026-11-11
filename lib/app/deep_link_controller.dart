import 'dart:async';

import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/domain/playlist/share_route.dart';
import 'package:alisten/domain/room/room_route.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AppLinkSource {
  Future<Uri?> getInitialLink();

  /// 包括启动应用的链接。
  Stream<Uri> get uriLinkStream;
}

final class PluginAppLinkSource implements AppLinkSource {
  PluginAppLinkSource() : _links = AppLinks();

  final AppLinks _links;

  @override
  Future<Uri?> getInitialLink() => _links.getInitialLink();

  // app_links 也会把启动链接发给第一个监听者。
  @override
  Stream<Uri> get uriLinkStream => _links.uriLinkStream;
}

const _logSource = 'deep-link';

final appLinkSourceProvider = Provider<AppLinkSource>((ref) {
  throw UnimplementedError('appLinkSource 未注入');
});

// 只读取、不监听当前配置：换服务器时不中断链接订阅，之后的链接按新服务器判断。
final deepLinkControllerProvider = Provider<DeepLinkController>((ref) {
  final controller = DeepLinkController(
    config: () => ref.read(appConfigProvider),
    source: ref.watch(appLinkSourceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final class DeepLinkController {
  DeepLinkController({required this._config, this.source});

  static final appSections = {
    ...linkRoomSections,
    for (final mode in RoomMode.values) ?mode.path,
  };

  final AppConfig Function() _config;
  final AppLinkSource? source;
  StreamSubscription<Uri>? _subscription;

  /// 形如 `host[:port]`。
  String get host => _config().linkHost;

  /// 端口也必须一致：同一主机的不同端口是另一个服务器。
  String? routeFor(Uri uri) {
    if (uri.scheme != 'https' || uri.authority != host) return null;
    return _siteRoute(uri);
  }

  static String? _siteRoute(Uri uri) =>
      _roomRoute(uri) ?? sharedPlaylistRoute(uri.pathSegments);

  static String? _roomRoute(Uri uri) =>
      roomRoute(uri.pathSegments, sections: linkRoomSections);

  /// 配对码在片段里，不进入请求和 Referer。
  ({String authority, String fragment})? pairLinkFor(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.path != '/pair' ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return (authority: uri.authority, fragment: uri.fragment);
  }

  // App Links 只为构建时的域名验证；切换服务器后，打开的仍是该域名的链接。
  bool _isOtherServerLink(Uri uri) {
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        routeFor(uri) == null &&
        _siteRoute(uri) != null;
  }

  /// 返回应用是否由房间链接（包括其他服务器的）启动；为 true 时由该链接决定
  /// 进入哪个房间。配对链接和分享链接不算：用它们启动时照常恢复上次的房间，
  /// 用户才能从分享页点歌进去。
  Future<bool> start(
    void Function(String route) onRoute, {
    void Function()? onInvalid,
    void Function(Uri uri)? onOtherServer,
    void Function(String fragment)? onPair,
    void Function(String authority)? onOtherServerPair,
  }) async {
    final linkSource = source ?? PluginAppLinkSource();
    await _subscription?.cancel();
    bool toOtherServer(Uri uri) =>
        onOtherServer != null && _isOtherServerLink(uri);
    _subscription = linkSource.uriLinkStream.listen((uri) {
      // MainActivity 是导出的，其他 App 可以把 GitHub 回调地址直接发过来；回调只由
      // 授权会话接收，这里不处理，也不算无效链接。
      if (uri.scheme == githubCallbackScheme) return;
      // 配对码只对签发它的服务器有效：其他服务器的链接只交出 authority。
      if (pairLinkFor(uri) case (:final authority, :final fragment)) {
        if (authority == host) {
          onPair?.call(fragment);
        } else {
          onOtherServerPair?.call(authority);
        }
        return;
      }
      final route = routeFor(uri);
      if (route != null) {
        onRoute(route);
      } else if (toOtherServer(uri)) {
        onOtherServer!(uri);
      } else {
        onInvalid?.call();
      }
    }, onError: (Object _) => AppLog.warn(_logSource, 'link not read'));
    try {
      // 启动链接也由 `uriLinkStream` 送达，这里只判断是否存在。
      final initial = await linkSource.getInitialLink();
      return initial != null &&
          _roomRoute(initial) != null &&
          (routeFor(initial) != null || toOtherServer(initial));
    } on Object {
      AppLog.warn(_logSource, 'launch link not read');
      return false;
    }
  }

  String inviteLinkForRef(String ref) => _config().inviteLinkFor(ref);

  String inviteLink({required String id, required String? slug}) {
    return inviteLinkForRef(slug ?? id);
  }

  Future<void> dispose() => _subscription?.cancel() ?? Future.value();
}
