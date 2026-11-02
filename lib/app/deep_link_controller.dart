import 'dart:async';

import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
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
    return roomRoute(uri.pathSegments, sections: linkRoomSections);
  }

  // App Links 只为构建时的域名验证；切换服务器后，打开的仍是该域名的链接。
  bool _isOtherServerRoom(Uri uri) {
    return uri.scheme == 'https' &&
        routeFor(uri) == null &&
        roomRoute(uri.pathSegments, sections: linkRoomSections) != null;
  }

  /// 返回应用是否由房间链接（包括其他服务器的）启动；为 true 时由该链接决定
  /// 进入哪个房间。
  Future<bool> start(
    void Function(String route) onRoute, {
    void Function()? onInvalid,
    void Function(Uri uri)? onOtherServer,
  }) async {
    final linkSource = source ?? PluginAppLinkSource();
    await _subscription?.cancel();
    bool toOtherServer(Uri uri) =>
        onOtherServer != null && _isOtherServerRoom(uri);
    _subscription = linkSource.uriLinkStream.listen((uri) {
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
