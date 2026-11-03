import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/release/app_release.dart';
import 'package:alisten/domain/release/release_version.dart';
import 'package:alisten/features/update/application/release_opener.dart';
import 'package:alisten/features/update/application/release_source.dart';
import 'package:alisten/features/update/application/update_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const autoCheckInterval = Duration(hours: 24);

const _logSource = 'update';

final installedVersionProvider = Provider<ReleaseVersion>((ref) {
  throw UnimplementedError('installedVersion 未注入');
});

final updateNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

sealed class UpdateCheck {
  const UpdateCheck();
}

final class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.release, this.version);

  final AppRelease release;
  final ReleaseVersion version;
}

final class UpToDate extends UpdateCheck {
  const UpToDate();
}

final class UpdateCheckFailed extends UpdateCheck {
  const UpdateCheckFailed();
}

/// 状态表示手动检查是否正在进行。
final updateControllerProvider = NotifierProvider<UpdateController, bool>(
  UpdateController.new,
);

final class UpdateController extends Notifier<bool> {
  bool _launchChecked = false;

  // 这次运行中弹出过面板的版本，手动检查和启动检查共用。
  ReleaseVersion? _offered;

  @override
  bool build() => false;

  /// 每次运行只检查一次，距上次自动检查不足 [autoCheckInterval] 时不检查；
  /// 失败不提示，只记 debug 日志。跳过的版本不返回。
  Future<UpdateAvailable?> checkOnLaunch() async {
    if (_launchChecked) return null;
    _launchChecked = true;
    final store = ref.read(updateStoreProvider);
    final source = ref.read(releaseSourceProvider);
    final installed = ref.read(installedVersionProvider);
    final now = ref.read(updateNowProvider)();
    final last = store.readLastAutoCheck();
    // 时钟被回拨后上次检查的时间晚于现在，不能因此一直不检查。
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) < autoCheckInterval) {
      return null;
    }
    final AppRelease release;
    try {
      release = await source.latest();
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'launch update check failed',
        type: '${error.runtimeType}',
      );
      return null;
    }
    try {
      await store.writeLastAutoCheck(now);
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'update check time not saved',
        type: '${error.runtimeType}',
      );
    }
    final update = _available(release, installed);
    if (update == null || store.readSkippedVersion() == '${update.version}') {
      return null;
    }
    return update;
  }

  /// [checkOnLaunch] 的结果可能等很久才能弹出，其间同一版本可能已由手动检查
  /// 弹出过或被跳过，所以弹出之前要再确认一次。返回 true 时调用方须立即弹出。
  bool claimLaunchOffer(UpdateAvailable update) {
    final version = update.version;
    if (version == _offered ||
        ref.read(updateStoreProvider).readSkippedVersion() == '$version') {
      return false;
    }
    _offered = version;
    return true;
  }

  /// 不受自动检查间隔、跳过的版本和本次运行已弹出过的限制。已有手动检查在进行
  /// 时不再检查，返回 null。
  Future<UpdateCheck?> checkNow() async {
    if (state) return null;
    final source = ref.read(releaseSourceProvider);
    final installed = ref.read(installedVersionProvider);
    state = true;
    try {
      final update = _available(await source.latest(), installed);
      if (update == null) return const UpToDate();
      _offered = update.version;
      return update;
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'update check failed',
        type: '${error.runtimeType}',
      );
      return const UpdateCheckFailed();
    } finally {
      if (ref.mounted) state = false;
    }
  }

  Future<void> skip(UpdateAvailable update) async {
    try {
      await ref
          .read(updateStoreProvider)
          .writeSkippedVersion('${update.version}');
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'skipped version not saved',
        type: '${error.runtimeType}',
      );
    }
  }

  Future<bool> open(AppRelease release) async {
    try {
      return await ref.read(releaseOpenerProvider).open(release);
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'release not opened',
        type: '${error.runtimeType}',
      );
      return false;
    }
  }
}

UpdateAvailable? _available(AppRelease release, ReleaseVersion installed) {
  final version = release.version;
  if (version == null || !version.isNewerThan(installed)) return null;
  return UpdateAvailable(release, version);
}
