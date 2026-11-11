import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/settings/application/notification_access.dart';
import 'package:alisten/features/settings/application/settings_state.dart';
import 'package:alisten/features/settings/application/settings_store.dart';
import 'package:alisten/features/settings/application/system_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logSource = 'settings';

const _unauthorized = 'UNAUTHORIZED';

const _notSavedText = '没有保存，再试一次。';

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

final trimSearchHistoryProvider = Provider<Future<void> Function(int limit)>((
  ref,
) {
  throw UnimplementedError('trimSearchHistory 未注入');
});

/// 资料表单显示的邮箱：已注册账号以服务端保存的为准，游客用本机保存的。
final profileEmailProvider = Provider<String>((ref) {
  final account = ref.watch(
    identityControllerProvider.select((identity) => identity.account),
  );
  if (account != null) return account.email ?? '';
  return ref.watch(
    settingsControllerProvider.select((settings) => settings.value.email),
  );
});

/// 设置改动立即生效；写入失败只记日志，改动在应用关闭前仍然有效。
final class SettingsController extends Notifier<SettingsState> {
  int _permissionRevision = 0;

  @override
  SettingsState build() {
    // 邮箱属于输入它时的身份。身份被替换时存储中的旧邮箱已删除，这里只清空
    // 当前值。
    ref.listen(identityControllerProvider.select((s) => s.session), (_, _) {
      state = state.copyWith(value: state.value.copyWith(email: ''));
    });
    // 偏好设置已在内存中，同步读取可让已存的设置在第一帧之前生效。
    final value = ref.read(settingsStoreProvider).load();
    unawaited(Future.microtask(refreshPermission));
    return SettingsState(
      value: value,
      permission: NotificationPermission.unknown,
    );
  }

  Future<void> refreshPermission() async {
    if (!ref.mounted) return;
    final revision = ++_permissionRevision;
    var permission = NotificationPermission.unknown;
    try {
      final granted = await ref
          .read(notificationAccessProvider)
          .checkPermission();
      permission = granted
          ? NotificationPermission.granted
          : NotificationPermission.denied;
    } on Object {
      AppLog.warn(_logSource, 'notification permission not read');
    }
    if (!ref.mounted || revision != _permissionRevision) return;
    state = state.copyWith(permission: permission);
  }

  /// 用户从系统设置回到前台时会重新读取权限。
  Future<bool> openNotificationSettings() async {
    try {
      return await ref.read(systemSettingsProvider).openNotificationSettings();
    } on Object {
      AppLog.warn(_logSource, 'notification settings not opened');
      return false;
    }
  }

  Future<void> setTheme(AppTheme theme) {
    return _change(
      (value) => value.copyWith(theme: theme),
      (store) => store.setTheme(theme),
    );
  }

  Future<void> setReminders(bool enabled) {
    return _change(
      (value) => value.copyWith(reminders: enabled),
      (store) => store.setReminders(enabled),
    );
  }

  /// 打开时会向系统请求通知权限，被拒绝时保持关闭。
  Future<void> setSystemNotifications(bool enabled) async {
    var allowed = false;
    if (enabled) {
      final revision = ++_permissionRevision;
      var permission = NotificationPermission.unknown;
      try {
        final granted = await ref
            .read(notificationAccessProvider)
            .requestPermission();
        permission = granted
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      } on Object {
        AppLog.warn(_logSource, 'notification permission not requested');
      }
      if (!ref.mounted) return;
      if (revision == _permissionRevision) {
        state = state.copyWith(permission: permission);
      }
      allowed = permission == NotificationPermission.granted;
    }
    await _change(
      (value) => value.copyWith(systemNotifications: allowed),
      (store) => store.setSystemNotifications(allowed),
    );
  }

  Future<void> setRecordSearch(bool enabled) {
    return _change(
      (value) => value.copyWith(recordSearch: enabled),
      (store) => store.setRecordSearch(enabled),
    );
  }

  /// 调小上限会立即截断已存的搜索记录；不在 [searchHistoryLimits] 中的值被
  /// 忽略。
  Future<void> setSearchHistoryLimit(int limit) async {
    if (!searchHistoryLimits.contains(limit)) return;
    final before = await _change(
      (value) => value.copyWith(searchHistoryLimit: limit),
      (store) => store.setSearchHistoryLimit(limit),
    );
    if (before != null && limit < before.searchHistoryLimit) {
      await _truncateSearchHistory(limit);
    }
  }

  /// 记录开关只保存在服务端的成员上，本机不写；还没有成员时先建游客。
  Future<MutationResult<void>> setRecordListens(bool on) async {
    final identity = ref.read(identityControllerProvider.notifier);
    // 先取定凭据和 API：建游客期间换了服务器，写入也不会发给新服务器。
    final credentials = ref.read(credentialStoreProvider);
    final api = ref.read(alistenApiProvider);
    final known = ref.read(identityControllerProvider).member;
    final Member member;
    try {
      member = known ?? await identity.ensureMember();
    } on ApiException catch (error) {
      return MutationNotSent(error.message);
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'member not ready for listen recording',
        type: '${error.runtimeType}',
      );
      return const MutationNotSent(identityUnreadableText);
    }
    final token = await credentials.readMemberTokenOrNull();
    try {
      await api.setListenRecording(on);
    } on ApiException catch (error) {
      // 成员是这次才取得的（通常是刚建的游客）时，被拒并不说明已保存的身份
      // 有问题。
      if (error.code == _unauthorized && known != null) {
        final text = await identity.recoverFromRefusal(credentials, token);
        // 换成了新游客时再试一次就能保存；账号被下线、换了服务器或没取到新身份
        // 时照实说。
        return MutationFailed(
          _unauthorized,
          text == identityRenewedNotice ? _notSavedText : text,
        );
      }
      if (error.answerLost) {
        if (ref.mounted) unawaited(loadProfile());
        return const MutationUnknown();
      }
      if (error.code == LocalErrorCodes.noToken) {
        return MutationNotSent(error.message);
      }
      return MutationFailed(error.code, rateLimitedText(error));
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'listen recording change ended unexpectedly',
        type: '${error.runtimeType}',
      );
      if (ref.mounted) unawaited(loadProfile());
      return const MutationUnknown();
    }
    identity.updateRecordListens(member.id, on);
    return const MutationSucceeded(null);
  }

  /// [volume] 取 0 到 100。拖动滑块期间 [persist] 传 false，只生效不写入，松开
  /// 时再写入。
  Future<void> setVolume(int volume, {required bool persist}) {
    final clamped = volume.clamp(0, 100);
    return _change(
      (value) => value.copyWith(volume: clamped),
      persist ? (store) => store.setVolume(clamped) : null,
    );
  }

  Future<void> setMuted(bool muted) {
    return _change(
      (value) => value.copyWith(muted: muted),
      (store) => store.setMuted(muted),
    );
  }

  Future<void> setEmail(String email) {
    return _change(
      (value) => value.copyWith(email: email),
      (store) => store.setEmail(email),
    );
  }

  /// 重新读取成员，不会创建成员，失败时资料保持原样。读取失败时返回 false；返回
  /// true 而仍然没有成员，说明这个服务器上还没有身份。
  Future<bool> loadProfile() async {
    try {
      await ref.read(identityControllerProvider.notifier).restore();
      return true;
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'profile not restored',
        code: error is ApiException ? error.code : null,
      );
      return false;
    }
  }

  /// 只发送与当前成员和当前邮箱不同的字段，还没有成员时非空邮箱照样发送。已注册
  /// 账号的邮箱以服务端的 `account.email` 为准，由服务端保存；游客的邮箱在服务端
  /// 接受后才保存在本机。
  Future<MutationResult<Member>> saveProfile({
    required String nickname,
    required String email,
  }) async {
    final identity = ref.read(identityControllerProvider);
    final member = identity.member;
    final account = identity.account;
    final nameChanged = nickname != (member?.name ?? '');
    final currentEmail = account != null
        ? account.email ?? ''
        : state.value.email;
    // 游客的邮箱存在本机、各服务器共用，头像却由各服务器为自己的成员保存，
    // 所以新服务器上的成员要收到一次邮箱才有头像。
    final emailChanged =
        email != currentEmail || (member == null && email.isNotEmpty);
    if (!nameChanged && !emailChanged) {
      return const MutationNotSent('没有需要保存的修改。');
    }
    final MutationResult<Member> result;
    try {
      result = await ref
          .read(identityControllerProvider.notifier)
          .saveProfile(
            nickname: nameChanged ? nickname : null,
            email: emailChanged ? email : null,
          );
    } on Object catch (error) {
      // 服务端错误已转成结果；其他错误发生时请求可能已到达服务端，只能重新
      // 读取成员。日志只记错误类型，不含昵称、邮箱和凭据。
      AppLog.error(
        _logSource,
        'profile save ended unexpectedly',
        type: '${error.runtimeType}',
      );
      if (ref.mounted) unawaited(loadProfile());
      return const MutationUnknown();
    }
    if (!ref.mounted || result is! MutationSucceeded<Member> || !emailChanged) {
      return result;
    }
    // 已注册账号的邮箱由服务端保存。保存期间身份变了时，为旧身份输入的邮箱
    // 不能留给新身份。
    final changed =
        ref.read(identityControllerProvider).session != identity.session;
    if (account == null && !changed) await setEmail(email);
    return result;
  }

  // 返回改动之前的设置；控制器已销毁时返回 null。
  Future<LocalSettings?> _change(
    LocalSettings Function(LocalSettings value) change,
    Future<void> Function(SettingsStore store)? write,
  ) async {
    if (!ref.mounted) return null;
    final before = state.value;
    state = state.copyWith(value: change(before));
    if (write != null) {
      try {
        await write(ref.read(settingsStoreProvider));
      } on Object {
        AppLog.warn(_logSource, 'setting not saved');
      }
    }
    return before;
  }

  // 截断失败也不撤销已保存的上限。
  Future<void> _truncateSearchHistory(int limit) async {
    if (!ref.mounted) return;
    try {
      await ref.read(trimSearchHistoryProvider)(limit);
    } on Object {
      AppLog.warn(_logSource, 'search history not shortened');
    }
  }
}
