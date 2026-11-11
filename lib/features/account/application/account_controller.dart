import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/features/account/application/account_failures.dart';
import 'package:alisten/features/account/application/site_capabilities.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const wrongCredentialsText = '用户名或密码不对';
const wrongCurrentPasswordText = '当前密码不对';
const registrationClosedText = '站点暂时关闭了注册';
const logoutFailedText = '没有退出，再试一次';
const noPasswordText = '这个账号还没有密码，先设置用户名和密码';
const githubVerifyExpiredText = '用 GitHub 确认身份已经超过 10 分钟，请再点一次“设置用户名和密码”。';
const _credentialsRuleText = '用户名要 3–32 位小写字母、数字、_ 或 -，密码要 8–128 位。';
const _alreadySignedInText = '已经登录了账号';
const _identityRenewedText = '身份已更新，请再登录一次';

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
      return const MutationNotSent(serverChangedNotice);
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
      refreshIdentity(_identity);
      return const MutationUnknown();
    }
    if (signedIn.device case final issued?) {
      try {
        await credentials.writeLoginDevice(username, issued);
      } on Object {
        AppLog.warn(_logSource, 'login device not saved');
      }
    }
    // 登录期间换了服务器：会话已写回原来的服务器，不能按当前服务器提示已登录。
    if (!identical(_ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(doneOnOldServerText);
    }
    return MutationSucceeded(signedIn.account);
  }

  Future<MutationResult<Account>> register({
    required String username,
    required String password,
  }) {
    return _register(
      username,
      password,
      action: 'register',
      refused: (error) {
        if (error.code != _forbidden) return null;
        _ref.invalidate(siteCapabilitiesProvider);
        return const MutationFailed(_forbidden, registrationClosedText);
      },
    );
  }

  /// 只绑定了 GitHub 的账号补设用户名和密码，要求这台设备 10 分钟内用 GitHub
  /// 确认过身份。成功后账号的其他会话全部失效，这台设备的会话保留。
  Future<MutationResult<Account>> setCredentials({
    required String username,
    required String password,
  }) async {
    final memberId = _ref.read(identityControllerProvider).member?.id;
    if (memberId == null) return const MutationNotSent(signedOutNotice);
    return _register(
      username,
      password,
      action: 'set credentials',
      expectedMemberId: memberId,
      refused: (error) => switch (error.code) {
        // 这里的 FORBIDDEN 是确认身份已经超时，不是站点关闭了注册。
        _forbidden => const MutationFailed(_forbidden, githubVerifyExpiredText),
        _invalidArgument => const MutationFailed(
          _invalidArgument,
          _credentialsRuleText,
        ),
        _ => null,
      },
    );
  }

  /// 只有游客能兑换；回复里没有设备凭证。
  Future<MutationResult<Account>> redeemPairingCode(String input) async {
    final code = normalizePairingCode(input);
    if (!isPairingCode(code)) {
      return const MutationNotSent(invalidPairingCodeText);
    }
    final credentials = _ref.read(credentialStoreProvider);
    final SignedIn signedIn;
    try {
      signedIn = await _ref
          .read(roomControllerProvider.notifier)
          .changeSession(
            () => _identity.adoptSession((api) => api.redeemPairingCode(code)),
          );
    } on ApiException catch (error) {
      return _pairingFailure(error);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'pairing ended unexpectedly',
        type: '${error.runtimeType}',
      );
      refreshIdentity(_identity);
      return const MutationUnknown();
    }
    if (!identical(_ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(doneOnOldServerText);
    }
    return MutationSucceeded(signedIn.account);
  }

  /// [refused] 处理各方法自己的错误码，返回 null 则落到共同的处理。
  Future<MutationResult<Account>> _register(
    String username,
    String password, {
    required String action,
    required MutationResult<Account>? Function(ApiException error) refused,
    String? expectedMemberId,
  }) async {
    if (usernameProblem(username) ?? passwordProblem(password)
        case final problem?) {
      return MutationNotSent(problem);
    }
    final credentials = _ref.read(credentialStoreProvider);
    final String memberId;
    try {
      memberId = (await _identity.ensureMember()).id;
    } on ApiException catch (error) {
      return MutationNotSent(error.message);
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'member not ready for $action',
        type: '${error.runtimeType}',
      );
      return const MutationNotSent(identityUnreadableText);
    }
    // 成员取自发起时的服务器，注册也只能发给它：从这次检查到取 api 之间不能有
    // await。
    if (!identical(_ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(serverChangedNotice);
    }
    // 只绑定了 GitHub 的账号被下线后换成了新游客：再注册就成了给新游客另开账号。
    if (expectedMemberId != null && memberId != expectedMemberId) {
      return const MutationNotSent(signedOutNotice);
    }
    final api = _ref.read(alistenApiProvider);
    final token = await credentials.readMemberTokenOrNull();
    final Account account;
    try {
      account = await api.register(username: username, password: password);
    } on ApiException catch (error) {
      if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
      if (error.answerLost) {
        refreshIdentity(_identity);
        return const MutationUnknown();
      }
      if (refused(error) case final result?) return result;
      switch (error.code) {
        case _conflict:
          refreshIdentity(_identity);
          return MutationFailed(_conflict, error.message);
        case _unauthorized:
          return MutationFailed(
            _unauthorized,
            await _identity.recoverFromRefusal(credentials, token),
          );
      }
      return MutationFailed(error.code, error.message);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        '$action ended unexpectedly',
        type: '${error.runtimeType}',
      );
      refreshIdentity(_identity);
      return const MutationUnknown();
    }
    // 账号建在原来的服务器上，不能写进当前服务器的状态，也不能把本机邮箱迁过去。
    if (!identical(_ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(doneOnOldServerText);
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
      if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
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
    final token = await credentials.readMemberTokenOrNull();
    try {
      await api.changePassword(currentPassword: current, newPassword: next);
      return const MutationSucceeded(null);
    } on ApiException catch (error) {
      if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
      if (error.answerLost) return const MutationUnknown();
      return switch (error.code) {
        _invalidCredentials => const MutationFailed(
          _invalidCredentials,
          wrongCurrentPasswordText,
        ),
        _conflict => const MutationFailed(_conflict, noPasswordText),
        _unauthorized => MutationFailed(
          _unauthorized,
          await _identity.recoverFromRefusal(credentials, token),
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
    if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
    if (error.answerLost) {
      refreshIdentity(_identity);
      return const MutationUnknown();
    }
    switch (error.code) {
      case _invalidCredentials:
        return const MutationFailed(_invalidCredentials, wrongCredentialsText);
      case _conflict:
        refreshIdentity(_identity);
        return const MutationFailed(_conflict, _alreadySignedInText);
      case _unauthorized:
        return const MutationFailed(_unauthorized, _identityRenewedText);
    }
    return MutationFailed(error.code, error.message);
  }

  // 兑换被拒时 adoptSession 已在身份队列里替换了游客，这里不再替换。
  MutationResult<Account> _pairingFailure(ApiException error) {
    if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
    if (error.answerLost) {
      refreshIdentity(_identity);
      return const MutationUnknown();
    }
    switch (error.code) {
      case _invalidCredentials:
        return MutationFailed(_invalidCredentials, error.message);
      case _invalidArgument:
        return const MutationFailed(_invalidArgument, invalidPairingCodeText);
      case _conflict:
        refreshIdentity(_identity);
        return const MutationFailed(_conflict, _alreadySignedInText);
      case _unauthorized:
        return const MutationFailed(_unauthorized, _identityRenewedText);
    }
    return MutationFailed(error.code, error.message);
  }
}
