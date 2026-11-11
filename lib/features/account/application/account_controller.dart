import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/features/account/application/site_capabilities.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const wrongCredentialsText = '用户名或密码不对';
const wrongCurrentPasswordText = '当前密码不对';
const registrationClosedText = '站点暂时关闭了注册';
const logoutFailedText = '没有退出，再试一次';
const _alreadySignedInText = '已经登录了账号';
const _identityRenewedText = '身份已更新，请再登录一次';
const _identityUnreadableText = '身份凭据暂时无法读取，请稍后重试。';
const _noPasswordText = '这个账号还没有密码，先设置用户名和密码';
const _serverChangedText = '服务器已经切换，这次操作没有完成。';

const _unauthorized = 'UNAUTHORIZED';
const _invalidCredentials = 'INVALID_CREDENTIALS';
const _invalidArgument = 'INVALID_ARGUMENT';
const _conflict = 'CONFLICT';
const _forbidden = 'FORBIDDEN';
const _logSource = 'account';

final accountControllerProvider = Provider<AccountController>(
  AccountController.new,
);

/// 所有操作都把失败放进结果，不抛出。
final class AccountController {
  AccountController(this._ref);

  final Ref _ref;

  IdentityController get _identity =>
      _ref.read(identityControllerProvider.notifier);

  Future<MutationResult<Account>> login({
    required String username,
    required String password,
  }) async {
    if (usernameProblem(username) ?? passwordProblem(password)
        case final problem?) {
      return MutationNotSent(problem);
    }
    final credentials = _ref.read(credentialStoreProvider);
    String? device;
    try {
      final saved = await credentials.readLoginDevice(username);
      if (saved != null && isLoginDevice(saved)) device = saved;
    } on Object {
      AppLog.warn(_logSource, 'login device not read');
    }
    // 设备凭证只能发给签发它的服务器。从这里到 adoptSession 取定会话之间不能
    // 有 await：此后登录请求、memberToken 和设备凭证都固定属于这个服务器，即使
    // 期间换了服务器。
    if (!identical(_ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(_serverChangedText);
    }
    final SignedIn signedIn;
    try {
      signedIn = await _ref
          .read(roomControllerProvider.notifier)
          .changeSession(
            () => _identity.adoptSession(
              (api) => api.login(
                username: username,
                password: password,
                device: device,
              ),
            ),
          );
    } on ApiException catch (error) {
      return _signInFailure(error);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'login ended unexpectedly',
        type: '${error.runtimeType}',
      );
      _refresh();
      return const MutationUnknown();
    }
    if (signedIn.device case final issued?) {
      try {
        await credentials.writeLoginDevice(username, issued);
      } on Object {
        AppLog.warn(_logSource, 'login device not saved');
      }
    }
    return MutationSucceeded(signedIn.account);
  }

  Future<MutationResult<Account>> register({
    required String username,
    required String password,
  }) async {
    if (usernameProblem(username) ?? passwordProblem(password)
        case final problem?) {
      return MutationNotSent(problem);
    }
    final String memberId;
    try {
      memberId = (await _identity.ensureMember()).id;
    } on ApiException catch (error) {
      return MutationNotSent(error.message);
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'member not ready for register',
        type: '${error.runtimeType}',
      );
      return const MutationNotSent(_identityUnreadableText);
    }
    final credentials = _ref.read(credentialStoreProvider);
    final api = _ref.read(alistenApiProvider);
    final token = await _readToken(credentials);
    final Account account;
    try {
      account = await api.register(username: username, password: password);
    } on ApiException catch (error) {
      if (error.rateLimited) return MutationNotSent(_rateLimitedText(error));
      if (error.answerLost) {
        _refresh();
        return const MutationUnknown();
      }
      switch (error.code) {
        case _forbidden:
          _ref.invalidate(siteCapabilitiesProvider);
          return const MutationFailed(_forbidden, registrationClosedText);
        case _conflict:
          _refresh();
          return MutationFailed(_conflict, error.message);
        case _unauthorized:
          return MutationFailed(
            _unauthorized,
            await _replaced(credentials, token),
          );
      }
      return MutationFailed(error.code, error.message);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'register ended unexpectedly',
        type: '${error.runtimeType}',
      );
      _refresh();
      return const MutationUnknown();
    }
    _identity.updateAccount(memberId, account);
    await migrateLocalEmail();
    return MutationSucceeded(account);
  }

  Future<MutationResult<void>> logout() async {
    try {
      await _ref
          .read(roomControllerProvider.notifier)
          .changeSession(() => _identity.signOut((api) => api.logout()));
      return const MutationSucceeded(null);
    } on ApiException catch (error) {
      if (error.rateLimited) return MutationNotSent(_rateLimitedText(error));
      return MutationFailed(error.code, logoutFailedText);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'logout ended unexpectedly',
        type: '${error.runtimeType}',
      );
      return const MutationFailed(null, logoutFailedText);
    }
  }

  Future<MutationResult<void>> changePassword({
    required String current,
    required String next,
  }) async {
    if (passwordProblem(current) != null) {
      return const MutationNotSent(wrongCurrentPasswordText);
    }
    if (passwordProblem(next) case final problem?) {
      return MutationNotSent(problem);
    }
    final credentials = _ref.read(credentialStoreProvider);
    final api = _ref.read(alistenApiProvider);
    final token = await _readToken(credentials);
    try {
      await api.changePassword(currentPassword: current, newPassword: next);
      return const MutationSucceeded(null);
    } on ApiException catch (error) {
      if (error.rateLimited) return MutationNotSent(_rateLimitedText(error));
      if (error.answerLost) return const MutationUnknown();
      return switch (error.code) {
        _invalidCredentials => const MutationFailed(
          _invalidCredentials,
          wrongCurrentPasswordText,
        ),
        _conflict => const MutationFailed(_conflict, _noPasswordText),
        _unauthorized => MutationFailed(
          _unauthorized,
          await _replaced(credentials, token),
        ),
        _ => MutationFailed(error.code, error.message),
      };
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'change password ended unexpectedly',
        type: '${error.runtimeType}',
      );
      return const MutationUnknown();
    }
  }

  /// 已注册的账号还没有邮箱、本机却存着游客时期的邮箱时，把它存进账号。成功
  /// 或邮箱不合法时删掉本机副本；其他失败保留，下次启动或回到前台时再试。
  Future<void> migrateLocalEmail() async {
    try {
      final account = _ref.read(identityControllerProvider).account;
      if (account == null || account.email != null) return;
      final settings = _ref.read(settingsControllerProvider.notifier);
      final email = _ref.read(settingsControllerProvider).value.email.trim();
      if (email.isEmpty) return;
      final result = await _identity.saveProfile(email: email);
      switch (result) {
        case MutationSucceeded():
        case MutationFailed(code: _invalidArgument):
          await settings.setEmail('');
        case MutationFailed() || MutationNotSent() || MutationUnknown():
          AppLog.debug(_logSource, 'local email kept for a later try');
      }
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'local email not migrated',
        type: '${error.runtimeType}',
      );
    }
  }

  MutationResult<Account> _signInFailure(ApiException error) {
    if (error.rateLimited) return MutationNotSent(_rateLimitedText(error));
    if (error.answerLost) {
      _refresh();
      return const MutationUnknown();
    }
    switch (error.code) {
      case _invalidCredentials:
        return const MutationFailed(_invalidCredentials, wrongCredentialsText);
      case _conflict:
        _refresh();
        return const MutationFailed(_conflict, _alreadySignedInText);
      case _unauthorized:
        return const MutationFailed(_unauthorized, _identityRenewedText);
    }
    return MutationFailed(error.code, error.message);
  }

  // 被拒的是 [credentials] 所属服务器的 memberToken；已经换了服务器时不能拿它
  // 去替换新服务器上的身份。
  Future<String> _replaced(
    CredentialStore credentials,
    String? rejectedToken,
  ) async {
    if (!identical(_ref.read(credentialStoreProvider), credentials)) {
      return _serverChangedText;
    }
    final registered = _ref.read(identityControllerProvider).account != null;
    try {
      await _identity.replaceAfterUnauthorized(rejectedToken: rejectedToken);
    } on Object {
      AppLog.debug(_logSource, 'identity not replaced');
    }
    return registered ? signedOutNotice : identityRenewedNotice;
  }

  void _refresh() {
    unawaited(
      _identity.restore().then<void>(
        (_) {},
        onError: (Object _) {
          AppLog.debug(_logSource, 'profile not refreshed');
        },
      ),
    );
  }

  static Future<String?> _readToken(CredentialStore credentials) async {
    try {
      return await credentials.readMemberToken();
    } on Object {
      return null;
    }
  }

  static String _rateLimitedText(ApiException error) {
    final seconds = error.retryAfter?.inSeconds;
    return seconds == null || seconds <= 0
        ? error.message
        : '请求太频繁，请 $seconds 秒后再试';
  }
}
