import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdminApi api;
  late ProviderContainer container;

  final provider = apiKeyControllerProvider('r1');
  ApiKeyController controller() => container.read(provider.notifier);
  ApiKeyState state() => container.read(provider);

  setUp(() async {
    api = FakeAdminApi();
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    container.listen(provider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('a status that cannot be read says why', () async {
    api.getApiKeyStatusError = const ApiException(
      code: 'NOT_FOUND',
      message: '房间不存在',
      status: 404,
    );

    await controller().load();

    expect(state().status, isNull);
    expect(state().loading, isFalse);
    expect(state().error, '房间不存在');
  });

  test(
    'a reset that did not succeed returns once the status has been read '
    'again, so the generation time before and after can be compared',
    () async {
      await controller().load();
      api
        ..resetApiKeyError = const ApiException(
          code: 'INTERNAL',
          message: '服务器出错了',
          status: 500,
        )
        ..apiKeyStatus = const ApiKeyStatus(
          generated: true,
          createdAtMs: 1800000000000,
        );

      final result = await controller().reset();

      expect(result, isA<MutationUnknown<String>>());
      expect(state().status!.createdAtMs, 1800000000000);
      expect(state().loading, isFalse);
    },
  );

  test('a token the server no longer takes ends the session', () async {
    api.resetApiKeyError = const ApiException(
      code: 'UNAUTHORIZED',
      message: 'token invalid',
      status: 401,
    );
    final read = api.getApiKeyStatusCalls;

    final result = await controller().reset();
    await pumpEventQueue();

    expect(
      result,
      isA<MutationNotSent<String>>().having(
        (r) => r.message,
        'message',
        '后台会话已结束',
      ),
    );
    expect(container.read(adminSessionProvider).active, isFalse);
    expect(api.getApiKeyStatusCalls, read);
  });
}
