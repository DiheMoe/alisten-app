import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/identity/application/identity_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const identityRenewedNotice = '身份已更新，请重新确认刚才的操作';

const identityLostNotice = '身份已失效，请重试';

const signedOutNotice = '已退出登录';

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
    // 会话代号不归零：设置页按它的变化清空邮箱，而邮箱不分服务器。
    if (ref.mounted) state = IdentityState(session: state.session);
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
  /// 时连同关联的本地数据一起丢弃；其他失败照常抛出，memberToken 保留。丢弃了
  /// 被拒的身份时返回 true。
  Future<bool> restore() {
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

  /// 用 [request] 换来账号的新会话并采用它：写入新 memberToken，删除本服务器的
  /// 全部票据，会话代号加 1。在身份队列中执行，期间其他操作用旧 token 被拒触发
  /// 的替换排在之后，那时 token 已经换掉，不会多建一个游客。本机还没有身份时
  /// 先建游客，因为登录要用游客的 token 发出。[request] 返回 `UNAUTHORIZED`
  /// 说明游客 token 已经失效：按被拒替换身份，再原样抛出。
  Future<SignedIn> adoptSession(
    Future<SignedIn> Function(AlistenApi api) request,
  ) {
    final session = _session();
    return _serialized(session, () => _adopt(session, request));
  }

  /// 用 [request] 结束当前会话，然后换成新的游客。[request] 返回
  /// `UNAUTHORIZED` 时会话本来就已失效，同样算作退出；其他失败原样抛出，
  /// memberToken 保留。新建游客失败时身份留空，下次需要成员时再建。
  Future<void> signOut(Future<void> Function(AlistenApi api) request) {
    final session = _session();
    return _serialized(session, () => _signOut(session, request));
  }

  /// [memberId] 是发起操作时的成员：期间身份变了就不再改动状态。
  void updateAccount(String memberId, Account account) {
    if (state.member?.id != memberId) return;
    state = state.copyWith(account: account);
  }

  void clearNotice() {
    if (state.notice != null) state = state.copyWith(notice: null);
  }

  /// 结果中的昵称是服务端保存的昵称，可能与请求的不同。已注册账号的 [email] 由
  /// 服务端保存；游客的只用来生成头像，服务端不保存。
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
      final account = state.account;
      if (email != null && account != null && _isCurrent(session)) {
        final saved = email.trim();
        state = state.copyWith(
          account: account.withEmail(saved.isEmpty ? null : saved),
        );
      }
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
    final registered = state.account != null;
    try {
      await _replaceMember(session, rejectedToken);
      return registered ? signedOutNotice : identityRenewedNotice;
    } on _ServerChanged {
      return _serverChanged;
    } on Object {
      // 旧身份已丢弃并已提示，下一个需要成员的操作会创建新成员。
      return registered ? signedOutNotice : identityLostNotice;
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

  Future<bool> _restore(_Session session) async {
    final token = await session.credentials.readMemberToken();
    if (token == null || token.isEmpty) return false;
    try {
      _setProfile(session, await session.api.getMe());
      return false;
    } on ApiException catch (error) {
      if (error.code != _unauthorized) rethrow;
      final registered = _isCurrent(session) && state.account != null;
      await _discardRejectedIdentity(session);
      if (registered && _isCurrent(session)) {
        state = state.copyWith(notice: signedOutNotice);
      }
      return true;
    }
  }

  Future<Member> _ensure(_Session session) async {
    final token = await session.credentials.readMemberToken();
    if (token == null || token.isEmpty) return _createMember(session);
    try {
      final profile = await session.api.getMe();
      _setProfile(session, profile);
      return profile.member;
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
      // 没有 token 说明被拒的身份已由 restore 或 signOut 丢弃，只差新成员；再丢弃
      // 一次会让会话代号多加 1，并改掉当时的提示。
      if (current == null || current.isEmpty) {
        if (!_isCurrent(session)) throw const _ServerChanged();
        return _createMember(session);
      }
      if (current != rejectedToken) {
        if (!_isCurrent(session)) throw const _ServerChanged();
        return state.member ?? await _ensure(session);
      }
    }
    final registered = _isCurrent(session) && state.account != null;
    await _discardRejectedIdentity(session);
    if (!_isCurrent(session)) throw const _ServerChanged();
    try {
      final member = await _createMember(session);
      if (_isCurrent(session)) {
        state = state.copyWith(
          notice: registered ? signedOutNotice : identityRenewedNotice,
        );
      }
      return member;
    } on Object {
      if (_isCurrent(session)) {
        state = state.copyWith(
          notice: registered ? signedOutNotice : identityLostNotice,
        );
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
    // 票据绑定签发它的会话，会话失效时它们都已作废。
    await session.credentials.deleteTickets();
    await _expireLocalData(session);
  }

  // memberToken 被丢弃或替换之后调用。邮箱保存在本机且不分服务器，换服务器之后
  // 它属于新服务器上的身份，所以只在仍是当前服务器时清除。
  Future<void> _expireLocalData(
    _Session session, {
    Member? member,
    Account? account,
  }) async {
    if (!_isCurrent(session)) return;
    try {
      await ref.read(clearLocalEmailProvider)();
    } on Object {
      // 新成员旁仍会显示旧邮箱，但不能因此妨碍更换身份。
      AppLog.warn(_logSource, 'local email not cleared');
    }
    if (_isCurrent(session)) {
      state = IdentityState(
        member: member,
        account: account,
        notice: state.notice,
        session: state.session + 1,
      );
    }
  }

  void _setProfile(_Session session, MemberProfile profile) {
    if (!_isCurrent(session)) return;
    state = state.copyWith(
      member: profile.member,
      account: profile.account,
      recordListens: profile.recordListens,
    );
  }

  Future<SignedIn> _adopt(
    _Session session,
    Future<SignedIn> Function(AlistenApi api) request,
  ) async {
    var token = await session.credentials.readMemberToken();
    if (token == null || token.isEmpty) {
      await _createMember(session);
      token = await session.credentials.readMemberToken();
    }
    final SignedIn signedIn;
    try {
      signedIn = await request(session.api);
    } on ApiException catch (error) {
      if (error.code == _unauthorized) {
        try {
          await _replace(session, token);
        } on Object {
          AppLog.debug(
            _logSource,
            'guest not replaced after a refused sign-in',
          );
        }
      }
      rethrow;
    }
    // 换了服务器也要写回发起时的服务器：那里的旧 token 已经失效。
    await session.credentials.writeMemberToken(signedIn.memberToken);
    await session.credentials.deleteTickets();
    await _expireLocalData(
      session,
      member: signedIn.member,
      account: signedIn.account,
    );
    // 登录的回复里没有记录开关，读不到时保持默认值。
    try {
      _setProfile(session, await session.api.getMe());
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'profile not read after sign-in',
        code: error is ApiException ? error.code : null,
      );
    }
    return signedIn;
  }

  Future<void> _signOut(
    _Session session,
    Future<void> Function(AlistenApi api) request,
  ) async {
    try {
      await request(session.api);
    } on ApiException catch (error) {
      if (error.code != _unauthorized) rethrow;
    }
    await session.credentials.deleteMemberToken();
    await session.credentials.deleteTickets();
    await _expireLocalData(session);
    if (!_isCurrent(session)) return;
    try {
      await _createMember(session);
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'guest not created after sign-out',
        code: error is ApiException ? error.code : null,
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
  Future<bool>? restoring;
  Future<Member>? ensuring;
  Future<Member>? replacing;
}

final class _ServerChanged implements Exception {
  const _ServerChanged();
}
