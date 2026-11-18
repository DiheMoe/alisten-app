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

  EphemeralRoomCapacityController controller() =>
      container.read(ephemeralRoomCapacityControllerProvider.notifier);
  EphemeralRoomCapacityState state() =>
      container.read(ephemeralRoomCapacityControllerProvider);

  setUp(() async {
    api = FakeAdminApi()..ephemeralRoomCapacity = 16;
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    container.listen(ephemeralRoomCapacityControllerProvider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('the capacity of new ephemeral rooms is read from the server', () async {
    await controller().load();

    expect(state().capacity, 16);
    expect(state().loading, isFalse);
    expect(state().error, isNull);
  });

  test(
    'a capacity that cannot be read says so and keeps what was read',
    () async {
      await controller().load();
      api.getEphemeralRoomCapacityError = const ApiException(
        code: 'NETWORK',
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await controller().load();

      expect(state().capacity, 16);
      expect(state().error, '网络请求失败，请检查网络后重试。');
    },
  );

  test('a capacity is sent with the admin token and kept once saved', () async {
    final result = await controller().save(' 24 ');

    expect(api.savedEphemeralRoomCapacities, [24]);
    expect(api.tokens.last, 't-1');
    expect(
      result,
      isA<MutationSucceeded<int>>().having((r) => r.value, 'value', 24),
    );
    expect(state().capacity, 24);
  });

  test('a capacity out of range is not sent', () async {
    for (final input in ['', '1', '129', '16.5']) {
      final result = await controller().save(input);

      expect(
        result,
        isA<MutationNotSent<int>>().having(
          (r) => r.message,
          'message',
          '最多人数要在 2 到 128 之间',
        ),
        reason: input,
      );
    }
    expect(api.savedEphemeralRoomCapacities, isEmpty);
  });

  test('a capacity the server refuses explains the rule', () async {
    api.setEphemeralRoomCapacityError = const ApiException(
      code: 'INVALID_ARGUMENT',
      message: 'capacity: must be between 2 and 128',
      status: 400,
    );

    final result = await controller().save('24');

    expect(
      result,
      isA<MutationFailed<int>>().having(
        (r) => r.message,
        'message',
        '最多人数要在 2 到 128 之间',
      ),
    );
  });

  test('a save without an answer may have taken effect, so the capacity is '
      'read again', () async {
    await controller().load();
    final reads = api.getEphemeralRoomCapacityCalls;
    api.setEphemeralRoomCapacityError = const ApiException(
      code: 'NETWORK',
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );

    final result = await controller().save('24');
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<int>>());
    expect(api.getEphemeralRoomCapacityCalls, reads + 1);
  });

  test('a save after the session ended is not sent', () async {
    container.read(adminSessionProvider.notifier).end();

    final result = await controller().save('24');

    expect(
      result,
      isA<MutationNotSent<int>>().having(
        (r) => r.message,
        'message',
        '后台已退出，最多人数没有保存。',
      ),
    );
    expect(api.savedEphemeralRoomCapacities, isEmpty);
  });
}
