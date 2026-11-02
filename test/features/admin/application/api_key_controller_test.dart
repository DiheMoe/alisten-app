import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
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

  test('the status of the key is read with the admin token', () async {
    await controller().load();

    final status = state().status!;
    expect(status.generated, isTrue);
    expect(status.createdAtMs, 1700000000000);
    expect(state().loading, isFalse);
    expect(state().error, isNull);
    expect(api.tokens.last, 't-1');
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

  test('a new key is handed back once and only the status is kept', () async {
    await controller().load();
    final read = api.getApiKeyStatusCalls;

    final result = await controller().reset();
    await pumpEventQueue();

    expect(
      result,
      isA<MutationSucceeded<String>>().having((r) => r.value, 'value', 'k-new'),
    );
    expect(api.resetApiKeyCalls, 1);
    expect(api.getApiKeyStatusCalls, read + 1);
    expect(state().status!.createdAtMs, 1800000000000);
    expect(state().error, isNull);
  });

  test('a reset without an answer may have taken effect: it is not sent '
      'again and the status is read again', () async {
    await controller().load();
    api.resetApiKeyError = const ApiException(
      code: 'NETWORK',
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );
    final read = api.getApiKeyStatusCalls;

    final result = await controller().reset();
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<String>>());
    expect(api.resetApiKeyCalls, 1);
    expect(api.getApiKeyStatusCalls, read + 1);
  });

  test('a reset refused by the server says why and the status is read '
      'again', () async {
    await controller().load();
    api.resetApiKeyError = const ApiException(
      code: 'NOT_FOUND',
      message: '房间不存在',
      status: 404,
    );
    final read = api.getApiKeyStatusCalls;

    final result = await controller().reset();
    await pumpEventQueue();

    expect(
      result,
      isA<MutationFailed<String>>()
          .having((r) => r.code, 'code', 'NOT_FOUND')
          .having((r) => r.message, 'message', '房间不存在'),
    );
    expect(api.getApiKeyStatusCalls, read + 1);
  });

  // 服务端重置 Key 后若通知断开事件流失败，会回复 UNAVAILABLE，此时 Key 已经
  // 更换。
  for (final (code, status) in [('UNAVAILABLE', 503), ('INTERNAL', 500)]) {
    test('a reset the server could not finish ($code) may have taken effect: '
        'it is not sent again and the status is read again', () async {
      await controller().load();
      api.resetApiKeyError = ApiException(
        code: code,
        message: '房间暂时不可用，请稍后再试。',
        status: status,
      );
      final read = api.getApiKeyStatusCalls;

      final result = await controller().reset();

      expect(result, isA<MutationUnknown<String>>());
      expect(api.resetApiKeyCalls, 1);
      expect(api.getApiKeyStatusCalls, read + 1);
    });
  }

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

  test('a reset that fails unexpectedly is unknown and logged by its type '
      'only', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    api.resetApiKeyError = StateError('t-1 k-secret');
    final read = api.getApiKeyStatusCalls;

    final result = await controller().reset();
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<String>>());
    expect(api.getApiKeyStatusCalls, read + 1);
    expect(records, contains(contains('StateError')));
    expect(records.where((r) => r.contains('k-secret')), isEmpty);
    expect(records.where((r) => r.contains('t-1')), isEmpty);
  });

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

  test('a reset sent before the session ended may have taken effect', () async {
    final gate = api.resetApiKeyGate = Completer();
    final pending = controller().reset();
    await pumpEventQueue();

    container.read(adminSessionProvider.notifier).end();
    gate.complete();

    expect(await pending, isA<MutationUnknown<String>>());
  });

  test('a key is copied only to the clipboard marked sensitive, and a copy '
      'that fails says so', () async {
    final clipboard = FakeSensitiveClipboard();
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [
        adminApiProvider.overrideWithValue(api),
        sensitiveClipboardProvider.overrideWithValue(clipboard),
      ],
    );

    expect(await controller().copy('k-new'), isTrue);
    expect(clipboard.copied, ['k-new']);

    clipboard.error = StateError('clipboard unavailable');
    expect(await controller().copy('k-new'), isFalse);
    expect(clipboard.copied, ['k-new']);
  });
}
