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
