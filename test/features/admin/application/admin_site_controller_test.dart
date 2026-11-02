import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
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
    expect(brandNameRuleText, '品牌名要有 1 到 20 个字，不能含换行、制表符等特殊字符');
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

  for (final (code, status) in [('UNAVAILABLE', 503), ('INTERNAL', 500)]) {
    test('a save the server could not finish ($code) may have taken effect, '
        'so it is not sent again and the brand name is read again', () async {
      api
        ..updateBrandError = ApiException(
          code: code,
          message: '服务器没有及时响应',
          status: status,
        )
        ..brandName = '服务端的名字';

      final result = await controller().save('周末听歌会');
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<String>>());
      expect(api.getBrandCalls, 1);
      expect(state().brandName, '服务端的名字');
    });
  }

  test('a save turned away for coming too often was not carried out: it '
      'says so and the brand name is not read again', () async {
    api.updateBrandError = const ApiException(
      code: 'RATE_LIMITED',
      message: '请求太频繁，请稍后再试。',
      status: 429,
    );

    final result = await controller().save('周末听歌会');
    await pumpEventQueue();

    expect(
      result,
      isA<MutationNotSent<String>>().having(
        (r) => r.message,
        'message',
        '请求太频繁，请稍后再试。',
      ),
    );
    expect(api.getBrandCalls, 0);
    expect(container.read(currentServerProvider).brandName, 'Alisten');
  });

  test('a save failing unexpectedly is unknown, the error type alone is '
      'logged, and the brand name is read again', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    api
      ..updateBrandError = StateError('t-1 周末听歌会')
      ..brandName = '服务端的名字';

    final result = await controller().save('周末听歌会');
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<String>>());
    expect(state().brandName, '服务端的名字');
    expect(records, contains(contains('StateError')));
    expect(records.where((r) => r.contains('t-1')), isEmpty);
    expect(records.where((r) => r.contains('周末听歌会')), isEmpty);
  });

  test('a save after the session ended is not sent', () async {
    container.read(adminSessionProvider.notifier).end();

    final result = await controller().save('周末听歌会');

    expect(result, isA<MutationNotSent<String>>());
    expect(api.updatedBrandName, isNull);
  });

  test('a save already sent when the session ended may have taken '
      'effect', () async {
    api.updateBrandGate = Completer();
    final pending = controller().save('周末听歌会');
    await pumpEventQueue();

    container.read(adminSessionProvider.notifier).end();
    api.updateBrandGate!.complete();

    expect(await pending, isA<MutationUnknown<String>>());
    expect(api.updatedBrandName, '周末听歌会');
  });

  test('a save refused because the token expired is not saved, and the '
      'session ends', () async {
    api.updateBrandError = const ApiException(
      code: 'UNAUTHORIZED',
      message: 'token invalid',
      status: 401,
    );

    final result = await controller().save('周末听歌会');

    expect(result, isA<MutationNotSent<String>>());
    expect(container.read(adminSessionProvider).active, isFalse);
    expect(container.read(adminSessionProvider).notice, adminTokenExpiredText);
    expect(container.read(currentServerProvider).brandName, 'Alisten');
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
