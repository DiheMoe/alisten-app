import 'dart:convert';
import 'dart:math';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/application/account_failures.dart';
import 'package:alisten/features/account/application/github_authorizer.dart';
import 'package:alisten/features/account/application/site_capabilities.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GithubOutcome { signedIn, registered, bound, verified }

/// 绑定前当前密码没有通过：本机校验不过，或者服务端在打开浏览器之前就拒绝了。
/// 当前密码面板据此留在原处；兑换时的 `INVALID_CREDENTIALS` 不是这个意思。
const githubWrongPasswordCode = 'GITHUB_WRONG_PASSWORD';
const githubUnknownText = '结果未知，已重新同步';
const githubNoResultText = '没有收到 GitHub 的授权结果，请重新发起。';

const _githubFailedText = '没有从 GitHub 确认你的身份，请稍后再试。';
const _deniedText = '你在 GitHub 上取消了授权。';
const _expiredText = 'GitHub 授权已经过期，请重新发起。';
const _notFinishedText = 'GitHub 登录没有完成，请重新发起。';
const _notRedirectedText = '没有跳转到 GitHub，再试一次。';

const _unauthorized = 'UNAUTHORIZED';
const _invalidCredentials = 'INVALID_CREDENTIALS';
const _conflict = 'CONFLICT';
const _forbidden = 'FORBIDDEN';
const _notFound = 'NOT_FOUND';
const _logSource = 'account';

final githubControllerProvider =
    NotifierProvider<GithubController, GithubIntent?>(GithubController.new);

/// 状态是进行中的意图。浏览器返回时设置页可能已经不在，流程仍要走完，所以不随
/// 页面释放。nonce 只在一次流程的局部变量里，不写盘、不写日志。
final class GithubController extends Notifier<GithubIntent?> {
  Future<MutationResult<GithubOutcome>>? _pending;

  @override
  GithubIntent? build() => null;

  Future<MutationResult<GithubOutcome>> signIn() => _start(GithubIntent.login);

  Future<MutationResult<GithubOutcome>> bind(String currentPassword) =>
      _start(GithubIntent.bind, currentPassword: currentPassword);

  Future<MutationResult<GithubOutcome>> verify() => _start(GithubIntent.verify);

  Future<MutationResult<void>> unbind(String currentPassword) async {
    if (passwordProblem(currentPassword) != null) {
      return const MutationNotSent(wrongCurrentPasswordText);
    }
    final identity = ref.read(identityControllerProvider.notifier);
    final memberId = ref.read(identityControllerProvider).member?.id;
    final credentials = ref.read(credentialStoreProvider);
    final api = ref.read(alistenApiProvider);
    final token = await credentials.readMemberTokenOrNull();
    try {
      await api.unbindGithub(currentPassword: currentPassword);
    } on ApiException catch (error) {
      if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
      if (error.answerLost) {
        refreshIdentity(identity);
        return const MutationUnknown();
      }
      switch (error.code) {
        case _invalidCredentials:
          return const MutationFailed(
            _invalidCredentials,
            wrongCurrentPasswordText,
          );
        case _conflict:
          refreshIdentity(identity);
          return const MutationFailed(_conflict, noPasswordText);
        case _notFound:
          ref.invalidate(siteCapabilitiesProvider);
          return MutationFailed(_notFound, error.message);
        case _unauthorized:
          return MutationFailed(
            _unauthorized,
            await identity.recoverFromRefusal(credentials, token),
          );
      }
      return MutationFailed(error.code, error.message);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'github unbind ended unexpectedly',
        type: '${error.runtimeType}',
      );
      refreshIdentity(identity);
      return const MutationUnknown();
    }
    final account = ref.read(identityControllerProvider).account;
    if (memberId != null && account != null) {
      identity.updateAccount(
        memberId,
        Account(
          username: account.username,
          email: account.email,
          github: false,
        ),
      );
    }
    return const MutationSucceeded(null);
  }

  // 插件按 scheme 记录待返回的回调，同时发起第二次授权会让第一次永远等不到
  // 结果。
  Future<MutationResult<GithubOutcome>> _start(
    GithubIntent intent, {
    String? currentPassword,
  }) {
    final running = state;
    if (running != null) {
      if (running == intent) return _pending!;
      throw StateError('Another GitHub authorization is running');
    }
    final pending = _pending = _authorize(intent, currentPassword).whenComplete(
      () {
        _pending = null;
        if (ref.mounted) state = null;
      },
    );
    // 设置状态会同步通知监听者，它们再调用时要拿到这一次的结果。
    state = intent;
    return pending;
  }

  Future<MutationResult<GithubOutcome>> _authorize(
    GithubIntent intent,
    String? currentPassword,
  ) async {
    final identity = ref.read(identityControllerProvider.notifier);
    final credentials = ref.read(credentialStoreProvider);
    if (intent == GithubIntent.login) {
      try {
        await identity.ensureMember();
      } on ApiException catch (error) {
        return MutationNotSent(error.message);
      } on Object catch (error) {
        AppLog.warn(
          _logSource,
          'member not ready for github',
          type: '${error.runtimeType}',
        );
        return const MutationNotSent(identityUnreadableText);
      }
    }
    // 游客建在发起时的服务器上，授权也要从那里发起：从这次检查到取 api 之间不能
    // 有 await。
    if (!identical(ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(serverChangedNotice);
    }
    if (intent == GithubIntent.bind &&
        passwordProblem(currentPassword ?? '') != null) {
      return const MutationFailed(
        githubWrongPasswordCode,
        wrongCurrentPasswordText,
      );
    }
    final session = ref.read(identityControllerProvider).session;
    final api = ref.read(alistenApiProvider);
    final nonce = _newNonce();
    final token = await credentials.readMemberTokenOrNull();
    final Uri url;
    try {
      url = await api.startGithubLogin(
        intent: intent,
        nonce: nonce,
        currentPassword: intent == GithubIntent.bind ? currentPassword : null,
      );
    } on ApiException catch (error) {
      return _refusedStart(intent, error, identity, credentials, token);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'github start ended unexpectedly',
        type: '${error.runtimeType}',
      );
      return const MutationNotSent(_githubFailedText);
    }
    // 授权地址属于发起时的服务器：换了服务器就不打开浏览器。
    if (!identical(ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(serverChangedNotice);
    }
    final Uri? callback;
    try {
      callback = await ref.read(githubAuthorizerProvider).authorize(url);
    } on Object catch (error) {
      if (error is! GithubAuthorizerFailed) {
        AppLog.warn(
          _logSource,
          'github browser ended unexpectedly',
          type: '${error.runtimeType}',
        );
      }
      return const MutationNotSent(_githubFailedText);
    }
    final String code;
    switch (callback == null
        ? const GithubRefused(GithubRefusal.missing)
        : readGithubCallback(callback)) {
      case GithubGranted(code: final granted):
        code = granted;
      case GithubRefused(:final reason):
        return MutationNotSent(switch (reason) {
          GithubRefusal.denied => _deniedText,
          GithubRefusal.expired => _expiredText,
          GithubRefusal.failed => _githubFailedText,
          GithubRefusal.missing => githubNoResultText,
        });
    }
    // 兑换必须发给发起授权的服务器：从这次检查到 adoptSessionIfIssued 取定会话
    // 之间不能有 await。
    if (!identical(ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(serverChangedNotice);
    }
    Future<GithubExchange> exchange() =>
        identity.adoptSessionIfIssued((api) async {
          // 轮到兑换时身份已经换过（例如回到前台时的 restore 丢弃了它）：发出去
          // 只会白白用掉兑换码。
          if (ref.read(identityControllerProvider).session != session) {
            throw const _IdentityChanged();
          }
          return api.finishGithubLogin(code: code, nonce: nonce);
        });
    final GithubExchange result;
    try {
      // 登录已有账号时服务端立即让游客 token 失效，4401 可能比回复先到，所以
      // 发请求之前就要开始暂存。
      result = intent == GithubIntent.login
          ? await ref
                .read(roomControllerProvider.notifier)
                .changeSession(exchange)
          : await exchange();
    } on _IdentityChanged {
      return const MutationNotSent(_notFinishedText);
    } on ApiException catch (error) {
      return _refusedExchange(intent, error, identity);
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'github exchange ended unexpectedly',
        type: '${error.runtimeType}',
      );
      refreshIdentity(identity);
      return const MutationUnknown();
    }
    // 兑换期间换了服务器：结果属于原来的服务器（新会话已由身份层写回那里），
    // 不能按当前服务器提示成功，也不能把本机邮箱迁进当前服务器的账号。
    if (!identical(ref.read(credentialStoreProvider), credentials)) {
      return const MutationNotSent(doneOnOldServerText);
    }
    if (result.signedIn != null) {
      return const MutationSucceeded(GithubOutcome.signedIn);
    }
    switch (intent) {
      case GithubIntent.login:
        await ref.read(accountControllerProvider).migrateLocalEmail();
        return const MutationSucceeded(GithubOutcome.registered);
      case GithubIntent.bind:
        return const MutationSucceeded(GithubOutcome.bound);
      case GithubIntent.verify:
        return const MutationSucceeded(GithubOutcome.verified);
    }
  }

  Future<MutationResult<GithubOutcome>> _refusedStart(
    GithubIntent intent,
    ApiException error,
    IdentityController identity,
    CredentialStore credentials,
    String? token,
  ) async {
    if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
    // 还没有打开浏览器，可以直接再点一次。
    if (error.answerLost) return MutationNotSent(error.message);
    switch (error.code) {
      case _notFound:
        ref.invalidate(siteCapabilitiesProvider);
        return MutationFailed(_notFound, error.message);
      case _conflict || _forbidden:
        refreshIdentity(identity);
        return MutationFailed(error.code, error.message);
      case _invalidCredentials when intent == GithubIntent.bind:
        return const MutationFailed(
          githubWrongPasswordCode,
          wrongCurrentPasswordText,
        );
      case _unauthorized:
        final text = await identity.recoverFromRefusal(credentials, token);
        // 游客换成新游客后可以直接再发起；换了服务器或者账号被下线时照实说。
        final retry =
            intent == GithubIntent.login &&
            identical(ref.read(credentialStoreProvider), credentials);
        return MutationFailed(_unauthorized, retry ? _notRedirectedText : text);
    }
    return MutationFailed(error.code, error.message);
  }

  MutationResult<GithubOutcome> _refusedExchange(
    GithubIntent intent,
    ApiException error,
    IdentityController identity,
  ) {
    if (error.rateLimited) return MutationNotSent(rateLimitedText(error));
    if (error.answerLost) {
      // 登录已有账号的回复丢了时游客 token 可能已经失效，之后按被动下线处理。
      refreshIdentity(identity);
      return const MutationUnknown();
    }
    switch (error.code) {
      case LocalErrorCodes.noToken:
        return const MutationNotSent(_notFinishedText);
      case _conflict:
        refreshIdentity(identity);
        return MutationFailed(_conflict, error.message);
      case _forbidden when intent == GithubIntent.login:
        ref.invalidate(siteCapabilitiesProvider);
        return const MutationFailed(_forbidden, registrationClosedText);
      case _forbidden:
        refreshIdentity(identity);
        return MutationFailed(_forbidden, error.message);
      case _notFound:
        ref.invalidate(siteCapabilitiesProvider);
        return MutationFailed(_notFound, error.message);
      // 身份已由 adoptSessionIfIssued 在队列里替换，不再调用
      // recoverFromRefusal，否则会重复替换。
      case _unauthorized:
        return MutationFailed(
          _unauthorized,
          intent == GithubIntent.login ? _notFinishedText : signedOutNotice,
        );
    }
    return MutationFailed(error.code, error.message);
  }
}

// 32 字节编码后是 43 个字符，在协议要求的 16–128 之内，与 Web 相同。
String _newNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

final class _IdentityChanged implements Exception {
  const _IdentityChanged();
}
