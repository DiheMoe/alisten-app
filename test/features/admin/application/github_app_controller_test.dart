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
