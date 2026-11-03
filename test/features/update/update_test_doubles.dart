import 'dart:async';

import 'package:alisten/app/app_version.dart';
import 'package:alisten/domain/release/app_release.dart';
import 'package:alisten/features/update/index.dart';

/// 与本次构建的版本相同，检查结果为已是最新。
final installedTag = 'v${appVersion.split('+').first}';

const _page = 'https://github.com/DiheMoe/alisten-app/releases/tag/';
const _download = 'https://github.com/DiheMoe/alisten-app/releases/download/';

AppRelease testRelease({
  String tag = 'v9.0.0',
  String notes = '- 修复了切歌时的卡顿\n- 新增检查更新',
  List<ReleaseAsset>? assets,
}) {
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  return AppRelease(
    tag: tag,
    notes: notes,
    page: Uri.parse('$_page$tag'),
    assets:
        assets ??
        [
          for (final abi in ['arm64-v8a', 'armeabi-v7a'])
            ReleaseAsset(
              name: 'Alisten-$version-$abi.apk',
              downloadUrl: Uri.parse(
                '$_download$tag/Alisten-$version-$abi.apk',
              ),
            ),
          ReleaseAsset(
            name: 'Alisten-$version-ios-unsigned.ipa',
            downloadUrl: Uri.parse(
              '$_download$tag/Alisten-$version-ios-unsigned.ipa',
            ),
          ),
        ],
  );
}

final class FakeReleaseSource implements ReleaseSource {
  FakeReleaseSource({AppRelease? release})
    : release = release ?? testRelease(tag: installedTag);

  AppRelease release;
  Exception? error;

  /// 设置后，请求等它完成才答复。
  Completer<void>? holding;

  int calls = 0;

  @override
  Future<AppRelease> latest() async {
    calls++;
    await holding?.future;
    if (error case final error?) throw error;
    return release;
  }
}

final class FakeUpdateStore implements UpdateStore {
  DateTime? lastAutoCheck;
  String? skippedVersion;
  Exception? writeError;

  @override
  DateTime? readLastAutoCheck() => lastAutoCheck;

  @override
  Future<void> writeLastAutoCheck(DateTime at) async {
    if (writeError case final error?) throw error;
    lastAutoCheck = at;
  }

  @override
  String? readSkippedVersion() => skippedVersion;

  @override
  Future<void> writeSkippedVersion(String version) async {
    if (writeError case final error?) throw error;
    skippedVersion = version;
  }
}

final class FakeReleaseOpener implements ReleaseOpener {
  final List<AppRelease> opened = [];
  bool opens = true;

  @override
  Future<bool> open(AppRelease release) async {
    opened.add(release);
    return opens;
  }
}
