import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/member.dart';

final class IdentityState {
  const IdentityState({
    this.member,
    this.account,
    this.recordListens = true,
    this.notice,
    this.session = 0,
  });

  /// 解析完成之前，或服务端拒绝已保存的 memberToken 之后为 null。
  final Member? member;

  /// 为 null 表示游客。
  final Account? account;

  final bool recordListens;

  final String? notice;

  /// 已保存的 memberToken 每被丢弃或替换一次就加 1：被拒后替换、登录、退出。
  /// 每次变化都表示与旧身份关联的本地数据（例如邮箱、票据）已经过期。第一次
  /// 建游客时没有旧身份，不加。
  final int session;

  IdentityState copyWith({
    Object? member = _unchanged,
    Object? account = _unchanged,
    bool? recordListens,
    Object? notice = _unchanged,
    int? session,
  }) {
    return IdentityState(
      member: identical(member, _unchanged) ? this.member : member as Member?,
      account: identical(account, _unchanged)
          ? this.account
          : account as Account?,
      recordListens: recordListens ?? this.recordListens,
      notice: identical(notice, _unchanged) ? this.notice : notice as String?,
      session: session ?? this.session,
    );
  }
}

const _unchanged = Object();
