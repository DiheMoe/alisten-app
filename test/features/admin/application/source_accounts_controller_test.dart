import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_test_doubles.dart';

const _signedIn = SourceAccountStatus(
  saved: true,
  account: SourceAccount(id: '42', name: '小明', verified: true),
);

void main() {
  late FakeAdminApi api;
  late ProviderContainer container;

  SourceAccountsController controller() =>
      container.read(sourceAccountsControllerProvider.notifier);
  Map<LoginSource, SourceEntry> state() =>
      container.read(sourceAccountsControllerProvider);

  setUp(() async {
    api = FakeAdminApi();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(baseUrl: 'https://livehouse.dihe.moe', isRelease: false),
        ),
        adminApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sourceAccountsControllerProvider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('a source that cannot be read says why and leaves the others '
      'alone', () async {
    api.sourceAccountErrors[LoginSource.bilibili] = const ApiException(
      code: 'INTERNAL',
      message: '服务器出错了',
      status: 500,
    );

    await controller().loadAll();

    expect(state()[LoginSource.bilibili]!.error, '服务器出错了');
    expect(state()[LoginSource.bilibili]!.status, isNull);
    expect(state()[LoginSource.netease]!.error, isNull);
    expect(state()[LoginSource.netease]!.status, isNotNull);
    expect(state()[LoginSource.qq]!.error, isNull);
    expect(state()[LoginSource.qq]!.status, isNotNull);
  });

  test('a source read that fails keeps what was read before', () async {
    api.sourceAccounts[LoginSource.netease] = _signedIn;
    await controller().loadAll();
    api.sourceAccountErrors[LoginSource.netease] = const ApiException(
      code: 'NETWORK',
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );

    final status = await controller().load(LoginSource.netease);

    expect(status, isNull);
    expect(state()[LoginSource.netease]!.status!.account!.id, '42');
    expect(state()[LoginSource.netease]!.error, '网络请求失败，请检查网络后重试。');
  });
}
