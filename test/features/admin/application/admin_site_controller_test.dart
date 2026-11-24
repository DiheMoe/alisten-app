import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _defaultId = 'fcd7a878032db68b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServerStore store;
  late FakeAdminApi api;
  late ProviderContainer container;

  AdminSiteController controller() =>
      container.read(adminSiteControllerProvider.notifier);
  AdminSiteState state() => container.read(adminSiteControllerProvider);

  setUp(() async {
    store = FakeServerStore(profiles: [serverB]);
    api = FakeAdminApi();
    container = await switchingContainer(
      store: store,
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    container.listen(adminSiteControllerProvider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('the brand name is read from the server', () async {
    await controller().load();

    expect(state().brandName, 'Alisten');
    expect(state().loading, isFalse);
    expect(state().error, isNull);
  });

  test('a brand name that cannot be read says so', () async {
    api.getBrandError = const ApiException(
      code: 'NETWORK',
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );

    await controller().load();

    expect(state().brandName, isNull);
    expect(state().loading, isFalse);
    expect(state().error, '网络请求失败，请检查网络后重试。');
  });

  test('a brand name is sent without its surrounding blanks, and the name the '
      'server saved is kept here and in the server list', () async {
    api.savedBrandName = '周末听歌会！';

    final result = await controller().save('  周末听歌会 ');

    expect(api.updatedBrandName, '周末听歌会');
    expect(api.tokens.last, 't-1');
    expect(
      result,
      isA<MutationSucceeded<String>>().having(
        (r) => r.value,
        'value',
        '周末听歌会！',
      ),
    );
    expect(state().brandName, '周末听歌会！');
    expect(container.read(currentServerProvider).brandName, '周末听歌会！');
    expect(
      store.profiles.singleWhere((p) => p.id == _defaultId).brandName,
      '周末听歌会！',
    );
  });

  test('a brand name the server would refuse is not sent', () async {
    for (final input in [
      '一二三四五六七八九十一二三四五六七八九十一',
      'a\tb',
      'a\nb',
      'a\u007fb',
      'a\u0085b',
      '   ',
      '',
      String.fromCharCode(0x200b),
    ]) {
      final result = await controller().save(input);

      expect(
        result,
        isA<MutationNotSent<String>>().having(
          (r) => r.message,
          'message',
          brandNameRuleText,
        ),
        reason: input,
      );
    }
    expect(api.updatedBrandName, isNull);
    expect(api.tokens, ['t-1']);
  });

  test('brand names are measured in characters, as the server does', () {
    expect(brandNameProblem('一二三四五六七八九十一二三四五六七八九十'), isNull);
    expect(brandNameProblem('  一二三四五六七八九十一二三四五六七八九十  '), isNull);
    expect(brandNameProblem('😀' * 20), isNull);
    expect(brandNameProblem('😀' * 21), brandNameRuleText);
    expect(brandNameProblem('a'), isNull);
    expect(brandNameProblem('a${String.fromCharCode(0xa0)}b'), isNull);
  });

  test('a brand name the server refuses explains the rule', () async {
    api.updateBrandError = const ApiException(
      code: 'INVALID_ARGUMENT',
      message: 'brandName：去掉首尾空白后应有 1 到 20 个字符',
      status: 400,
    );

    final result = await controller().save('周末听歌会');

    expect(
      result,
      isA<MutationFailed<String>>()
          .having((r) => r.code, 'code', 'INVALID_ARGUMENT')
          .having((r) => r.message, 'message', brandNameRuleText),
    );
    expect(container.read(currentServerProvider).brandName, 'Alisten');
  });

  test('a save without an answer may have taken effect, so the brand name is '
      'read again', () async {
    await controller().load();
    api.updateBrandError = const ApiException(
      code: 'NETWORK',
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );
    api.brandName = '服务端的名字';

    final result = await controller().save('周末听歌会');
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<String>>());
    expect(state().brandName, '服务端的名字');
    expect(container.read(currentServerProvider).brandName, '服务端的名字');
    expect(
      store.profiles.singleWhere((p) => p.id == _defaultId).brandName,
      '服务端的名字',
    );
  });

  test('a brand name from the server that breaks the rule is shown here but '
      'kept out of the server list', () async {
    final bell = String.fromCharCode(0x07);
    for (final name in ['长' * 81, 'a${bell}b', '${'长' * 80}$bell']) {
      api.brandName = name;
      await controller().load();
      expect(state().brandName, name, reason: 'load');

      api.savedBrandName = name;
      final result = await controller().save('周末听歌会');
      expect(
        result,
        isA<MutationSucceeded<String>>().having((r) => r.value, 'value', name),
        reason: 'save',
      );
      expect(state().brandName, name, reason: 'save');

      expect(container.read(currentServerProvider).brandName, 'Alisten');
      expect(
        store.profiles.where((p) => p.id == _defaultId).map((p) => p.brandName),
        isNot(contains(name)),
      );
    }
  });
}
