import 'package:alisten/domain/member/member.dart';

const usernameRuleText = '用户名要 3–32 位小写字母、数字、_ 或 -';
const passwordRuleText = '密码要 8 到 128 位';

final _username = RegExp(r'^[a-z0-9_-]{3,32}$');
final _loginDevice = RegExp(r'^[A-Za-z0-9_-]{43}$');

final class Account {
  const Account({this.username, this.email, required this.github});

  /// 只绑定了 GitHub 的账号没有用户名，也不能用密码登录。
  final String? username;
  final String? email;
  final bool github;

  Account withEmail(String? email) =>
      Account(username: username, email: email, github: github);
}

final class MemberProfile {
  const MemberProfile({
    required this.member,
    this.account,
    required this.recordListens,
  });

  final Member member;

  /// 为 null 表示游客。
  final Account? account;
  final bool recordListens;
}

String? usernameProblem(String username) =>
    _username.hasMatch(username) ? null : usernameRuleText;

/// 服务端按 Unicode 码点计长度，不能用 UTF-16 码元的 `length`。
String? passwordProblem(String password) {
  final length = password.runes.length;
  return length < 8 || length > 128 ? passwordRuleText : null;
}

/// 格式不对的设备凭证会让服务端拒绝整个登录请求，所以不合格式的不发送。
bool isLoginDevice(String value) => _loginDevice.hasMatch(value);
