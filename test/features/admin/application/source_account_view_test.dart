import 'package:alisten/features/admin/index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a source without saved sign-in is not signed in', () {
    final view = sourceAccountView(
      const SourceAccountStatus(saved: false),
      LoginSource.netease,
    );

    expect(view.status, '未登录');
    expect(view.details, isEmpty);
  });

  test('a login the platform says has expired says so, before anything '
      'else about the account', () {
    final view = sourceAccountView(
      const SourceAccountStatus(saved: true, signedOut: true),
      LoginSource.qq,
    );

    expect(view.status, '登录已失效');
    expect(view.details, isEmpty);
  });

  test('a saved sign-in without an account says it was not recognized', () {
    final view = sourceAccountView(
      const SourceAccountStatus(saved: true),
      LoginSource.qq,
    );

    expect(view.status, '已保存登录，没认出是哪个账号');
    expect(view.details, isEmpty);
  });

  test('a verified account lists its name, id and membership', () {
    final view = sourceAccountView(
      const SourceAccountStatus(
        saved: true,
        account: SourceAccount(id: '42', name: '小明', vip: true, verified: true),
      ),
      LoginSource.netease,
    );

    expect(view.status, '已登录');
    expect(view.details, ['昵称：小明', '账号 ID：42', '会员状态：会员']);
  });

  test('an account the platform did not verify names the platform, spaced '
      'after Chinese when it starts with a Latin letter or a digit', () {
    const account = SourceAccount(id: '42', vip: false, verified: false);
    String status(LoginSource source) => sourceAccountView(
      const SourceAccountStatus(saved: true, account: account),
      source,
    ).status;

    expect(status(LoginSource.qq), '已保存登录，没能向 QQ 音乐确认');
    expect(status(LoginSource.bilibili), '已保存登录，没能向 B 站确认');
    expect(status(LoginSource.netease), '已保存登录，没能向网易云音乐确认');
    expect(
      sourceAccountView(
        const SourceAccountStatus(saved: true, account: account),
        LoginSource.qq,
      ).details,
      ['账号 ID：42', '会员状态：非会员'],
    );
  });

  test('a name or membership the platform did not give is left out', () {
    final view = sourceAccountView(
      const SourceAccountStatus(
        saved: true,
        account: SourceAccount(id: '42', verified: true),
      ),
      LoginSource.bilibili,
    );

    expect(view.details, ['账号 ID：42']);
  });

  test('platforms are named as on the web', () {
    expect(platformName(LoginSource.netease), '网易云音乐');
    expect(platformName(LoginSource.qq), 'QQ 音乐');
    expect(platformName(LoginSource.bilibili), 'B 站');
  });
}
