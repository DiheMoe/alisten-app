import 'package:alisten/domain/server/server_origin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfig 未注入');
});

final buildEnvironmentProvider = Provider<BuildEnvironment>((ref) {
  throw UnimplementedError('buildEnvironment 未注入');
});

final class AppConfig {
  factory AppConfig({
    required String baseUrl,
    required bool isRelease,
    bool allowCleartext = false,
    Duration requestTimeout = const Duration(seconds: 15),
    String? linkHost,
  }) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Must be an HTTP(S) URL');
    }
    // REST 和 WebSocket 都使用绝对路径，源之后的部分会被静默丢弃。
    if ((uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Must be an origin without path, query or fragment',
      );
    }
    if (uri.scheme == 'http' && (isRelease || !allowCleartext)) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        isRelease
            ? 'Release backends must use HTTPS'
            : 'Cleartext HTTP requires explicit development opt-in',
      );
    }
    final origin = switch (parseServerOrigin(baseUrl, allowCleartext: true)) {
      ValidOrigin(:final origin) => origin,
      InvalidOrigin() => throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Must be an HTTP(S) origin without user info',
      ),
    };
    final normalizedLinkHost = linkHost?.trim().toLowerCase();
    if (normalizedLinkHost != null && normalizedLinkHost.isEmpty) {
      throw ArgumentError.value(linkHost, 'linkHost', 'Must not be empty');
    }
    return AppConfig._(
      baseUrl: origin,
      serverId: serverIdFor(origin),
      isRelease: isRelease,
      requestTimeout: requestTimeout,
      linkHost: normalizedLinkHost ?? originAuthority(origin),
    );
  }

  const AppConfig._({
    required this.baseUrl,
    required this.serverId,
    required this.isRelease,
    required this.requestTimeout,
    required this.linkHost,
  });

  final String baseUrl;
  final String serverId;
  final bool isRelease;
  final Duration requestTimeout;

  /// 端口不是默认端口时带上端口。统一小写：Android 匹配清单中的主机名时
  /// 区分大小写，Gradle 也会把它转成小写。
  final String linkHost;

  String inviteLinkFor(String roomRef) => 'https://$linkHost/r/$roomRef';

  String sharedPlaylistLinkFor(String shareId) =>
      'https://$linkHost/s/$shareId';
}

final class BuildEnvironment {
  factory BuildEnvironment({
    required String defaultOrigin,
    String? defaultLinkHost,
    required bool isRelease,
    bool allowCleartext = false,
  }) {
    return BuildEnvironment._(
      AppConfig(
        baseUrl: defaultOrigin,
        isRelease: isRelease,
        allowCleartext: allowCleartext,
        linkHost: defaultLinkHost,
      ),
      allowCleartext: allowCleartext,
    );
  }

  factory BuildEnvironment.fromEnvironment() {
    // 没有定义的 dart-define 读出来是空字符串，表示没有设置。
    const linkHost = String.fromEnvironment('ALISTEN_LINK_HOST');
    return BuildEnvironment(
      defaultOrigin: const String.fromEnvironment(
        'ALISTEN_API_URL',
        defaultValue: 'https://livehouse.dihe.moe',
      ),
      defaultLinkHost: linkHost.isEmpty ? null : linkHost,
      isRelease: const bool.fromEnvironment('dart.vm.product'),
      allowCleartext: const bool.fromEnvironment('ALISTEN_ALLOW_CLEARTEXT'),
    );
  }

  const BuildEnvironment._(this._defaultConfig, {required this.allowCleartext});

  final AppConfig _defaultConfig;
  final bool allowCleartext;

  String get defaultOrigin => _defaultConfig.baseUrl;
  String get defaultLinkHost => _defaultConfig.linkHost;
  bool get isRelease => _defaultConfig.isRelease;
  bool get allowsCleartextServers => !isRelease && allowCleartext;
  String get defaultServerId => _defaultConfig.serverId;

  // `ALISTEN_LINK_HOST` 只属于默认服务器；其他服务器的邀请链接使用各自的地址。
  AppConfig configFor(String origin) {
    final config = AppConfig(
      baseUrl: origin,
      isRelease: isRelease,
      allowCleartext: allowCleartext,
    );
    return config.baseUrl == defaultOrigin ? _defaultConfig : config;
  }
}
