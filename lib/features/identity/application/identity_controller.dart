import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/identity/application/identity_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const identityRenewedNotice = '身份已更新，请重新确认刚才的操作';

const identityLostNotice = '身份已失效，请重试';

const _unauthorized = 'UNAUTHORIZED';
const _serverChanged = '服务器已经切换，这次操作没有完成。';
const _logSource = 'identity';

final identityControllerProvider =
    NotifierProvider<IdentityController, IdentityState>(IdentityController.new);

final clearLocalEmailProvider = Provider<Future<void> Function()>((ref) {
  throw UnimplementedError('clearLocalEmail 未注入');
});

/// 只在操作需要成员时才创建身份，启动时从不创建。已保存的 memberToken 被
/// 服务端拒绝时替换身份，但被拒的操作不重发，由用户决定是否以新身份再做一次。
final class IdentityController extends Notifier<IdentityState> {
  // 换服务器时换成新的作用域。之前发出的操作仍用发起时的凭据和 API 完成，
  // 旧服务器的 memberToken 写回旧服务器名下，但不再改动状态。
  var _scope = _Scope();

  @override
  IdentityState build() => const IdentityState();

  /// 丢弃上一个服务器的成员，按新服务器保存的 memberToken 恢复；之前发出的
  /// 身份请求不再改动状态。不抛出。
  Future<void> resetForServerChange() async {
    _scope = _Scope();
    // 替换次数不归零：设置页按它的变化清空邮箱，而邮箱不分服务器。
    if (ref.mounted) state = IdentityState(replacements: state.replacements);
    try {
      await restore();
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'identity not restored after server change',
        code: error is ApiException ? error.code : null,
      );
    }
  }

  /// 只查询已保存的成员，不创建：没有 memberToken 时不发请求。memberToken 被拒
  /// 时连同关联的本地数据一起丢弃；其他失败照常抛出，memberToken 保留。
  Future<void> restore() {
    final session = _session();
    final scope = session.scope;
    return scope.restoring ??= _serialized(
      session,
      () => _restore(session),
    ).whenComplete(() => scope.restoring = null);
  }

  /// 没有保存 memberToken 或它被拒时才创建新成员。并发调用共用同一次尝试。
  Future<Member> ensureMember() => _ensureMember(_session());

  /// 服务端拒绝 memberToken（HTTP 401）后调用，被拒的操作不重试。
  ///
  /// [rejectedToken] 是被拒请求所用的 memberToken，须在发送之前读取：若其他
  /// 操作已替换了它，就原样返回当前成员，不把替换后的 memberToken 也丢掉。
  Future<Member> replaceAfterUnauthorized({String? rejectedToken}) =>
      _replaceMember(_session(), rejectedToken);

  void clearNotice() {
    if (state.notice != null) state = state.copyWith(notice: null);
  }

  /// 结果中的昵称是服务端保存的昵称，可能与请求的不同。[email] 只供服务端生成
  /// 头像，服务端不保存。
  Future<MutationResult<Member>> saveProfile({
    String? nickname,
    String? email,
  }) async {
    final session = _session();
    var created = false;
    String? sentToken;
    try {
      sentToken = await session.credentials.readMemberToken();
      if (sentToken == null || sentToken.isEmpty) {
        await _ensureMember(session);
        created = true;
      }
    } on ApiException catch (error) {
      return MutationNotSent(error.message);
    } on Object {
      return const MutationNotSent('身份凭据暂时无法读取，请稍后重试。');
    }
    try {
      final member = await session.api.updateMe(name: nickname, email: email);
      _setMember(session, member);
      return MutationSucceeded(member);
    } on ApiException catch (error) {
      // 刚为这次调用创建的 memberToken 被拒，并不说明已保存的身份有问题。
      if (error.code == _unauthorized && !created) {
        return MutationFailed(
          error.code,
          await _replaceAfterRefusal(session, sentToken),
        );
      }
      if (error.answerLost) {
        if (_isCurrent(session)) _calibrate();
        return const MutationUnknown();
      }
      return switch (error.code) {
        LocalErrorCodes.noToken => MutationNotSent(error.message),
        _ => MutationFailed(error.code, error.message),
      };
    }
  }

  void _calibrate() {
    unawaited(
      restore().then<void>(
        (_) {},
        onError: (Object _) {
          AppLog.debug(_logSource, 'calibration failed');
        },
      ),
    );
  }

  Future<String> _replaceAfterRefusal(
    _Session session,
    String? rejectedToken,
  ) async {
    try {
      await _replaceMember(session, rejectedToken);
      return identityRenewedNotice;
    } on _ServerChanged {
      return _serverChanged;
    } on Object {
      // 旧身份已丢弃并已提示，下一个需要成员的操作会创建新成员。
      return identityLostNotice;
    }
  }

  // 凭据与 API 在发起时一并取定，之后即使换了服务器，也不会把 memberToken
  // 发给另一个服务器或写到它名下。
  _Session _session() => (
    scope: _scope,
    credentials: ref.read(credentialStoreProvider),
    api: ref.read(alistenApiProvider),
  );

  bool _isCurrent(_Session session) =>
      ref.mounted && identical(session.scope, _scope);

  Future<Member> _ensureMember(_Session session) {
    final scope = session.scope;
    return scope.ensuring ??= _serialized(
      session,
      () => _ensure(session),
    ).whenComplete(() => scope.ensuring = null);
  }

  Future<Member> _replaceMember(_Session session, String? rejectedToken) {
    final scope = session.scope;
    return scope.replacing ??= _serialized(
      session,
      () => _replace(session, rejectedToken),
    ).whenComplete(() => scope.replacing = null);
  }

  Future<T> _serialized<T>(_Session session, Future<T> Function() action) {
    final scope = session.scope;
    final run = scope.tail.then((_) => action());
    scope.tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _restore(_Session session) async {
    final token = await session.credentials.readMemberToken();
    if (token == null || token.isEmpty) return;
    try {
      _setMember(session, await session.api.getMe());
    } on ApiException catch (error) {
      if (error.code != _unauthorized) rethrow;
      await _discardRejectedIdentity(session);
    }
  }

  Future<Member> _ensure(_Session session) async {
    final token = await session.credentials.readMemberToken();
    if (token == null || token.isEmpty) return _createMember(session);
    try {
      final member = await session.api.getMe();
      _setMember(session, member);
      return member;
    } on ApiException catch (error) {
      if (error.code != _unauthorized) rethrow;
      return _replace(session, token);
    }
  }

  // 换服务器之后只丢弃旧服务器上被拒的 memberToken：用户已经离开，不再在那里
  // 新建成员。
  Future<Member> _replace(_Session session, String? rejectedToken) async {
    if (rejectedToken != null) {
      final current = await session.credentials.readMemberToken();
      if (current != null && current.isNotEmpty && current != rejectedToken) {
        if (!_isCurrent(session)) throw const _ServerChanged();
        return state.member ?? await _ensure(session);
      }
    }
    await _discardRejectedIdentity(session);
    if (!_isCurrent(session)) throw const _ServerChanged();
    try {
      final member = await _createMember(session);
      if (_isCurrent(session)) {
        state = state.copyWith(notice: identityRenewedNotice);
      }
      return member;
    } on Object {
      if (_isCurrent(session)) {
        state = state.copyWith(notice: identityLostNotice);
      }
      rethrow;
    }
  }

  Future<Member> _createMember(_Session session) async {
    final created = await session.api.createMember();
    await session.credentials.writeMemberToken(created.memberToken);
    _setMember(session, created.member);
    return created.member;
  }

  Future<void> _discardRejectedIdentity(_Session session) async {
    AppLog.info(_logSource, 'member token rejected', code: _unauthorized);
    await session.credentials.deleteMemberToken();
    // 邮箱保存在本机且不分服务器，换服务器之后它属于新服务器上的身份。
    if (!_isCurrent(session)) return;
    try {
      await ref.read(clearLocalEmailProvider)();
    } on Object {
      // 新成员旁仍会显示旧邮箱，但不能因此妨碍替换身份。
      AppLog.warn(_logSource, 'local email not cleared');
    }
    if (_isCurrent(session)) {
      state = state.copyWith(
        member: null,
        replacements: state.replacements + 1,
      );
    }
  }

  void _setMember(_Session session, Member member) {
    if (_isCurrent(session)) state = state.copyWith(member: member);
  }
}

typedef _Session = ({
  _Scope scope,
  CredentialStore credentials,
  AlistenApi api,
});

// 同一服务器上的身份变更串行执行，多个调用方同时被拒时只替换一次
// memberToken。换服务器之后的变更既不排在旧服务器的变更之后，也不与它们共用
// 同一次尝试。
final class _Scope {
  Future<void> tail = Future<void>.value();
  Future<void>? restoring;
  Future<Member>? ensuring;
  Future<Member>? replacing;
}

final class _ServerChanged implements Exception {
  const _ServerChanged();
}
