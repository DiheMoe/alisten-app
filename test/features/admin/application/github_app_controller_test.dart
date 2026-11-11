import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _callback = 'https://example.com:8443/api/auth/github/callback';

const _network = ApiException(
  code: 'NETWORK',
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdminApi api;
  late ProviderContainer container;
  late ProviderSubscription<GithubAppState> subscription;

  GithubAppController controller() =>
      container.read(githubAppControllerProvider.notifier);
  GithubAppState state() => container.read(githubAppControllerProvider);

  setUp(() async {
    api = FakeAdminApi();
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    subscription = container.listen(githubAppControllerProvider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('the status is read with the admin token', () async {
    await controller().load();

    expect(state().status?.enabled, isFalse);
    expect(state().status?.callbackUrl, _callback);
    expect(api.tokens.last, 't-1');
  });

  test('a status that cannot be read says so, and reads again', () async {
    api.getGithubAppError = _network;
    await controller().load();

    expect(state().error, '暂时无法获取 GitHub 登录的配置。');
    expect(state().status, isNull);

    api.getGithubAppError = null;
    await controller().load();
    expect(state().error, isNull);
    expect(state().status?.enabled, isFalse);
  });

  test('saving trims both fields, keeps the secret out of the state and '
      'the log, and reads the status again', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add(message);
    addTearDown(() => AppLog.onRecord = null);
    await controller().load();

    final result = await controller().save(
      clientId: ' Iv1.abc ',
      clientSecret: ' secret-1\n',
    );
    await pumpEventQueue();

    expect(result, isA<MutationSucceeded<void>>());
    expect(api.savedGithubApps, [
      (clientId: 'Iv1.abc', clientSecret: 'secret-1'),
    ]);
    expect(state().status?.clientId, 'Iv1.abc');
    expect(state().status?.clientSecretSet, isTrue);
    expect(api.getGithubAppCalls, 2);
    expect(records.where((r) => r.contains('secret-1')), isEmpty);
    final current = state();
    expect(
      '${current.status?.clientId}${current.status?.callbackUrl}${current.error}',
      isNot(contains('secret-1')),
    );
  });

  test('a blank field is not sent', () async {
    final result = await controller().save(
      clientId: 'Iv1.abc',
      clientSecret: '   ',
    );

    expect(result, isA<MutationNotSent<void>>());
    expect(api.savedGithubApps, isEmpty);
  });

  test('a client the server cannot accept is told in plain words and the '
      'status is not read again', () async {
    await controller().load();
    api.setGithubAppError = const ApiException(
      code: 'INVALID_ARGUMENT',
      message: 'clientId 格式不对',
      status: 400,
    );

    final result = await controller().save(
      clientId: 'Iv1 abc',
      clientSecret: 'secret-1',
    );
    await pumpEventQueue();

    expect((result as MutationFailed<void>).message, githubAppInvalidText);
    expect(api.getGithubAppCalls, 1);
  });

  test('a save whose answer is lost is unknown and reads the status '
      'again', () async {
    await controller().load();
    api.setGithubAppError = _network;

    final result = await controller().save(
      clientId: 'Iv1.abc',
      clientSecret: 'secret-1',
    );
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<void>>());
    expect(api.getGithubAppCalls, 2);
  });

  test('closing turns GitHub off and reads the status again', () async {
    api.githubApp = const GithubAppStatus(
      clientId: 'Iv1.abc',
      clientSecretSet: true,
      callbackUrl: _callback,
    );
    await controller().load();

    final result = await controller().close();
    await pumpEventQueue();

    expect(result, isA<MutationSucceeded<void>>());
    expect(api.deleteGithubAppCalls, 1);
    expect(state().status?.enabled, isFalse);
  });

  test('a status read before a later one does not replace it', () async {
    final first = api.getGithubAppGate = Completer();
    final early = controller().load();
    await pumpEventQueue();
    api
      ..getGithubAppGate = null
      ..githubApp = const GithubAppStatus(
        clientId: 'Iv1.new',
        clientSecretSet: true,
        callbackUrl: _callback,
      );
    await controller().load();

    first.complete();
    await early;

    expect(state().status?.clientId, 'Iv1.new');
    expect(state().loading, isFalse);
  });

  test('a load after the session ended keeps the status and shows no '
      'error', () async {
    api.githubApp = const GithubAppStatus(
      clientId: 'Iv1.abc',
      clientSecretSet: true,
      callbackUrl: _callback,
    );
    await controller().load();
    container.read(adminSessionProvider.notifier).end();

    await controller().load();

    expect(state().status?.clientId, 'Iv1.abc');
    expect(state().error, isNull);
    expect(state().loading, isFalse);
  });

  test('a save after the session ended was not sent', () async {
    container.read(adminSessionProvider.notifier).end();

    final result = await controller().save(
      clientId: 'Iv1.abc',
      clientSecret: 'secret-1',
    );

    expect(
      result,
      isA<MutationNotSent<void>>().having(
        (r) => r.message,
        'message',
        '后台会话已结束',
      ),
    );
    expect(api.savedGithubApps, isEmpty);
  });

  test('a save sent before the session ended may have been saved', () async {
    final gate = api.setGithubAppGate = Completer();
    final pending = controller().save(
      clientId: 'Iv1.abc',
      clientSecret: 'secret-1',
    );
    await pumpEventQueue();

    container.read(adminSessionProvider.notifier).end();
    gate.complete();

    expect(await pending, isA<MutationUnknown<void>>());
  });

  test('an unknown save that answers after the controller is gone does not '
      'read the status', () async {
    await controller().load();
    final gate = api.setGithubAppGate = Completer();
    api.setGithubAppError = _network;
    final pending = controller().save(
      clientId: 'Iv1.abc',
      clientSecret: 'secret-1',
    );
    await pumpEventQueue();

    subscription.close();
    await pumpEventQueue();
    gate.complete();

    expect(await pending, isA<MutationUnknown<void>>());
    await pumpEventQueue();
    expect(api.getGithubAppCalls, 1);
  });
}
