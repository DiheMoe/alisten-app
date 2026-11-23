import 'package:alisten/features/admin/application/admin_models.dart';

String platformName(LoginSource source) => switch (source) {
  LoginSource.netease => '网易云音乐',
  LoginSource.qq => 'QQ 音乐',
  LoginSource.bilibili => 'B 站',
};

String afterChinese(String name) =>
    RegExp('^[A-Za-z0-9]').hasMatch(name) ? ' $name' : name;

({String status, List<String> details}) sourceAccountView(
  SourceAccountStatus status,
  LoginSource source,
) {
  if (!status.saved) return (status: '未登录', details: const []);
  if (status.signedOut) return (status: '登录已失效', details: const []);
  final account = status.account;
  if (account == null) {
    return (status: '已保存登录，没认出是哪个账号', details: const []);
  }
  final name = account.name;
  final vip = account.vip;
  return (
    status: account.verified
        ? '已登录'
        : '已保存登录，没能向${afterChinese(platformName(source))}确认',
    details: [
      if (name != null && name.isNotEmpty) '昵称：$name',
      '账号 ID：${account.id}',
      if (vip != null) '会员状态：${vip ? '会员' : '非会员'}',
    ],
  );
}
