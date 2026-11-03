import 'dart:ffi' show Abi;

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/release/app_release.dart';
import 'package:alisten/features/update/application/release_opener.dart';
import 'package:url_launcher/url_launcher.dart';

const _packageAbis = {
  Abi.androidArm64: 'arm64-v8a',
  Abi.androidArm: 'armeabi-v7a',
};

/// 安装包交给浏览器下载，由用户自己安装，因此应用不需要“安装未知应用”权限。
/// 没有本机架构的安装包时（包括 iOS）打开发布页。
final class PlatformReleaseOpener implements ReleaseOpener {
  PlatformReleaseOpener({Abi? abi, this._launch = launchUrl})
    : _abi = abi ?? Abi.current();

  final Abi _abi;
  final Future<bool> Function(Uri url, {LaunchMode mode}) _launch;

  @override
  Future<bool> open(AppRelease release) async {
    try {
      return await _launch(
        _target(release),
        mode: LaunchMode.externalApplication,
      );
    } on Object catch (error) {
      AppLog.debug(
        'update',
        'release link not opened',
        type: '${error.runtimeType}',
      );
      return false;
    }
  }

  Uri _target(AppRelease release) {
    final abi = _packageAbis[_abi];
    if (abi == null) return release.page;
    for (final asset in release.assets) {
      if (asset.name.contains(abi) && asset.name.endsWith('.apk')) {
        return asset.downloadUrl;
      }
    }
    return release.page;
  }
}
