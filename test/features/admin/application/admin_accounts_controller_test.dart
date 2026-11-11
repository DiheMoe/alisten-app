import 'dart:async';

import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdminApi api;
  late FakeSensitiveClipboard clipboard;
  late ProviderContainer container;

  final provider = adminAccountsControllerProvider;
  AdminAccountsController controller() => container.read(provider.notifier);
  AdminAccountsState state() => container.read(provider);

  setUp(() async {
    api = FakeAdminApi()
      ..accounts['mao'] = const AdminAccountView(
        member: Member(id: 'm-1', name: '大猫', avatarHash: ''),
        username: 'mao',
      );
    clipboard = FakeSensitiveClipboard();
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [
        adminApiProvider.overrideWithValue(api),
        sensitiveClipboardProvider.overrideWithValue(clipboard),
      ],
    );
    container.listen(provider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('a username that breaks the rule is not looked up', () async {
    final before = api.tokens.length;
    await controller().find('Ma');

    expect(state().problem, usernameRuleText);
    expect(state().account, isNull);
    expect(api.tokens, hasLength(before));
  });

  test('an unknown username says there is no such account', () async {
    await controller().find('nobody');

    expect(state().problem, '没有这个用户名的账号。');
    expect(state().account, isNull);
    expect(state().searching, isFalse);
  });

  test('an account is found by its trimmed username', () async {
    await controller().find(' mao ');

    expect(state().account!.username, 'mao');
    expect(state().problem, isNull);
    expect(api.tokens.last, 't-1');
  });

  test('the new password is handed back and never kept in the state', () async {
    await controller().find('mao');

    final result = await controller().resetPassword();

    expect(
      result,
      isA<MutationSucceeded<String>>().having(
        (r) => r.value,
        'value',
        'reset-secret-password',
      ),
    );
    expect(api.resetUsernames, ['mao']);
    final current = state();
    expect(current.account?.username, 'mao');
    expect(current.account?.member.name, '大猫');
    expect(current.account?.member.id, 'm-1');
    expect(current.account?.member.avatarHash, '');
    expect(current.searching, isFalse);
    expect(current.problem, isNull);
    for (final field in [
      current.account?.username,
      current.account?.member.name,
      current.problem,
    ]) {
      expect(field, isNot('reset-secret-password'));
    }
  });

  test('a reset without a found account is not sent', () async {
    final result = await controller().resetPassword();

    expect(result, isA<MutationNotSent<String>>());
    expect(api.resetUsernames, isEmpty);
  });

  test('a reset after the session ended is not sent', () async {
    await controller().find('mao');
    container.read(adminSessionProvider.notifier).end();

    expect(await controller().resetPassword(), isA<MutationNotSent<String>>());
    expect(api.resetUsernames, isEmpty);
  });

  test('a reset sent before the session ended may have taken effect', () async {
    await controller().find('mao');
    final gate = api.resetPasswordGate = Completer();
    final pending = controller().resetPassword();
    await pumpEventQueue();

    container.read(adminSessionProvider.notifier).end();
    gate.complete();

    expect(await pending, isA<MutationUnknown<String>>());
  });

  test('a password is copied only to the sensitive clipboard, and a copy '
      'that fails says so', () async {
    expect(await controller().copy('pw-secret-1'), isTrue);
    expect(clipboard.copied, ['pw-secret-1']);

    clipboard.error = StateError('clipboard unavailable');
    expect(await controller().copy('pw-secret-1'), isFalse);
    expect(clipboard.copied, ['pw-secret-1']);
  });
}
