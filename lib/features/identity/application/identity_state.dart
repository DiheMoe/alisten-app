import 'package:alisten/domain/member/member.dart';

final class IdentityState {
  const IdentityState({this.member, this.notice, this.replacements = 0});

  /// 解析完成之前，或服务端拒绝已保存的 memberToken 之后为 null。
  final Member? member;

  final String? notice;

  /// 本次运行中服务端拒绝已保存身份的次数。每次变化都表示与旧身份关联的本地
  /// 数据（例如 Gravatar 邮箱）已经过期。
  final int replacements;

  IdentityState copyWith({
    Object? member = _unchanged,
    Object? notice = _unchanged,
    int? replacements,
  }) {
    return IdentityState(
      member: identical(member, _unchanged) ? this.member : member as Member?,
      notice: identical(notice, _unchanged) ? this.notice : notice as String?,
      replacements: replacements ?? this.replacements,
    );
  }
}

const _unchanged = Object();
