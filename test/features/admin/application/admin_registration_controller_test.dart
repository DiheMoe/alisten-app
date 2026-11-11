import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _network = ApiException(
  code: 'NETWORK',
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdminApi api;
  late ProviderContainer container;

  AdminRegistrationController controller() =>
      container.read(adminRegistrationControllerProvider.notifier);
  AdminRegistrationState state() =>
      container.read(adminRegistrationControllerProvider);

  setUp(() async {
    api = FakeAdminApi();
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    container.listen(adminRegistrationControllerProvider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('the registration state is read from the server', () async {
    api.registrationOpen = false;

    await controller().load();

    expect(state().open, isFalse);
    expect(state().loading, isFalse);
    expect(state().error, isNull);
  });

  test('a registration state that cannot be read says so', () async {
    api.getRegistrationError = _network;

    await controller().load();

    expect(state().open, isNull);
    expect(state().error, '暂时无法获取注册状态。');
  });

  test('closing registration is sent with the token and kept', () async {
    await controller().load();

    final result = await controller().setOpen(false);

    expect(
      result,
      isA<MutationSucceeded<bool>>().having((r) => r.value, 'value', false),
    );
    expect(api.registrationCalls, [false]);
    expect(api.tokens.last, 't-1');
    expect(state().open, isFalse);
  });

  test('opening registration is sent and kept', () async {
    api.registrationOpen = false;
    await controller().load();

    await controller().setOpen(true);

    expect(api.registrationCalls, [true]);
    expect(state().open, isTrue);
  });

  test('a refused switch leaves the state as it was', () async {
    await controller().load();
    api.setRegistrationError = const ApiException(
      code: 'FORBIDDEN',
      message: '没有权限',
      status: 403,
    );

    final result = await controller().setOpen(false);
    await pumpEventQueue();

    expect(result, isNot(isA<MutationSucceeded<bool>>()));
    expect(state().open, isTrue);
  });

  test('a switch without an answer may have taken effect, so the state is '
      'read again', () async {
    await controller().load();
    api
      ..setRegistrationError = _network
      ..registrationOpen = false;

    final result = await controller().setOpen(false);
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<bool>>());
    expect(api.registrationCalls, [false]);
    expect(state().open, isFalse);
  });
}
