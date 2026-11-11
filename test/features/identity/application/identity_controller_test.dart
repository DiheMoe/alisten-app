import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';

void main() {
  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeLocalEmail localEmail;
  late ProviderContainer container;
  late IdentityController controller;

  const replacement = Member(id: 'new-id', name: '新听众', avatarHash: '');

  IdentityState identity() => container.read(identityControllerProvider);

  setUp(() {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore();
    localEmail = FakeLocalEmail();
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(api),
        credentialStoreProvider.overrideWithValue(credentials),
        clearLocalEmailProvider.overrideWithValue(localEmail.clear),
      ],
    );
    controller = container.read(identityControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  group('restore', () {
    test('a cold start without a token creates no member', () async {
      await controller.restore();

      expect(api.createMemberCalls, 0);
      expect(api.getMeCalls, 0);
      expect(identity().member, isNull);
      expect(credentials.memberToken, isNull);
    });

    test('a stored token is resolved to its member', () async {
      credentials.memberToken = 'stored-token';

      await controller.restore();

      expect(api.getMeCalls, 1);
      expect(api.createMemberCalls, 0);
      expect(identity().member?.id, 'member-id');
    });

    test('a rejected token is cleared with the local email', () async {
      credentials.memberToken = 'expired-token';
      api.getMeError = unauthorized;

      await controller.restore();

      expect(credentials.memberToken, isNull);
      expect(localEmail.clearCalls, 1);
      expect(api.createMemberCalls, 0);
      expect(identity().member, isNull);
    });

    test('a network failure keeps the token and is reported', () async {
      credentials.memberToken = 'stored-token';
      api.getMeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await expectLater(controller.restore(), throwsA(isA<ApiException>()));

      expect(credentials.memberToken, 'stored-token');
      expect(localEmail.clearCalls, 0);
    });
  });

  group('ensureMember', () {
    test('concurrent callers share one member creation', () async {
      api.createMemberGate = Completer<void>();

      final first = controller.ensureMember();
      final second = controller.ensureMember();
      await pumpEventQueue();
      api.createMemberGate!.complete();
      final members = await Future.wait([first, second]);

      expect(api.createMemberCalls, 1);
      expect(api.getMeCalls, 0);
      expect(members.map((member) => member.id), ['member-id', 'member-id']);
      expect(credentials.memberToken, 'new-member-token');
      expect(identity().member?.id, 'member-id');
    });

    test('a stored token is verified, not replaced', () async {
      credentials.memberToken = 'stored-token';

      await controller.ensureMember();

      expect(api.getMeCalls, 1);
      expect(api.createMemberCalls, 0);
      expect(identity().notice, isNull);
    });

    test('a rejected stored token is replaced and announced', () async {
      credentials.memberToken = 'expired-token';
      api.getMeError = unauthorized;
      api.createdMember = replacement;

      final member = await controller.ensureMember();

      expect(member.id, 'new-id');
      expect(credentials.memberToken, 'new-member-token');
      expect(localEmail.clearCalls, 1);
      expect(identity().notice, identityRenewedNotice);
    });
  });

  group('a replacement that cannot be created', () {
    test('still tells the user the old identity is gone', () async {
      credentials.memberToken = 'expired-token';
      api.getMeError = unauthorized;
      api.createMemberError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await expectLater(
        controller.ensureMember(),
        throwsA(isA<ApiException>()),
      );

      expect(credentials.memberToken, isNull);
      expect(identity().member, isNull);
      expect(identity().notice, identityLostNotice);
    });
  });

  group('replaceAfterUnauthorized', () {
    test(
      'leaves a token that already replaced the rejected one alone',
      () async {
        credentials.memberToken = 'current-token';
        await controller.ensureMember();

        final member = await controller.replaceAfterUnauthorized(
          rejectedToken: 'older-token',
        );

        expect(member.id, 'member-id');
        expect(api.createMemberCalls, 0);
        expect(credentials.deleteMemberCalls, 0);
        expect(credentials.memberToken, 'current-token');
        expect(localEmail.clearCalls, 0);
      },
    );

    test(
      'creates a member, clears the local email and sets the notice',
      () async {
        credentials.memberToken = 'expired-token';
        api.createdMember = replacement;

        final member = await controller.replaceAfterUnauthorized();

        expect(member.id, 'new-id');
        expect(identity().member?.id, 'new-id');
        expect(identity().notice, '身份已更新，请重新确认刚才的操作');
        expect(localEmail.clearCalls, 1);
        expect(credentials.memberToken, 'new-member-token');
        expect(api.getMeCalls, 0);
      },
    );

    test('the notice stays until it is cleared', () async {
      credentials.memberToken = 'expired-token';
      api.createdMember = replacement;
      await controller.replaceAfterUnauthorized();
      final sessions = identity().session;

      controller.clearNotice();

      expect(identity().notice, isNull);
      expect(identity().member?.id, 'new-id');
      expect(identity().session, sessions);
    });
  });

  group('recoverFromRefusal', () {
    const network = ApiException(
      code: LocalErrorCodes.network,
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );

    Future<void> signedIn() async {
      credentials.memberToken = 'account-token';
      api
        ..me = accountMember
        ..account = const Account(username: 'mao', github: false);
      await controller.restore();
      api
        ..me = null
        ..account = null;
    }

    test('an account refused is signed out and told so', () async {
      await signedIn();

      final text = await controller.recoverFromRefusal(
        credentials,
        'account-token',
      );

      expect(text, signedOutNotice);
      expect(credentials.memberToken, 'new-member-token');
      expect(identity().account, isNull);
      expect(identity().session, 1);
    });

    test('a guest refused becomes a new guest and is asked to confirm '
        'again', () async {
      credentials.memberToken = 'guest-token';
      await controller.restore();

      final text = await controller.recoverFromRefusal(
        credentials,
        'guest-token',
      );

      expect(text, identityRenewedNotice);
      expect(credentials.memberToken, 'new-member-token');
      expect(api.createMemberCalls, 1);
    });

    test('a token another operation already replaced keeps the current '
        'identity', () async {
      credentials.memberToken = 'current-token';
      await controller.restore();

      await controller.recoverFromRefusal(credentials, 'older-token');

      expect(api.createMemberCalls, 0);
      expect(credentials.deleteMemberCalls, 0);
      expect(credentials.memberToken, 'current-token');
      expect(identity().member?.id, 'member-id');
    });

    test('a guest whose replacement cannot be made is told the identity '
        'is lost, without a throw', () async {
      credentials.memberToken = 'guest-token';
      await controller.restore();
      api.createMemberError = network;

      expect(
        await controller.recoverFromRefusal(credentials, 'guest-token'),
        identityLostNotice,
      );
    });

    test('an account whose replacement cannot be made is still signed '
        'out', () async {
      await signedIn();
      api.createMemberError = network;

      expect(
        await controller.recoverFromRefusal(credentials, 'account-token'),
        signedOutNotice,
      );
    });
  });

  group('saveProfile', () {
    test('takes the nickname from the server member', () async {
      credentials.memberToken = 'stored-token';
      api.updateMeHandler = (name, email) => Member(
        id: 'member-id',
        name: name?.trim() ?? FakeAlistenApi.member.name,
        avatarHash: '',
      );

      final result = await controller.saveProfile(nickname: '  新昵称  ');

      expect(result, isA<MutationSucceeded<Member>>());
      expect((result as MutationSucceeded<Member>).value.name, '新昵称');
      expect(identity().member?.name, '新昵称');
    });

    test(
      'a rejected token replaces the identity without replaying the update',
      () async {
        credentials.memberToken = 'expired-token';
        api.updateMeError = unauthorized;
        api.createdMember = replacement;

        final result = await controller.saveProfile(
          nickname: '新昵称',
          email: 'a@b.c',
        );

        expect(result, isA<MutationFailed<Member>>());
        expect((result as MutationFailed<Member>).code, 'UNAUTHORIZED');
        expect(result.message, identityRenewedNotice);
        expect(api.updateMeCalls, 1);
        expect(api.createMemberCalls, 1);
        expect(localEmail.clearCalls, 1);
        expect(identity().member?.id, 'new-id');
        expect(identity().notice, identityRenewedNotice);
      },
    );

    test('creates the member first when none exists yet', () async {
      final result = await controller.saveProfile(nickname: '新昵称');

      expect(result, isA<MutationSucceeded<Member>>());
      expect(api.createMemberCalls, 1);
      expect(api.updateMeCalls, 1);
      expect(localEmail.clearCalls, 0);
    });

    test(
      'a refusal on a token created for this save does not replace it',
      () async {
        api.updateMeError = unauthorized;

        final result = await controller.saveProfile(nickname: '新昵称');

        expect(result, isA<MutationFailed<Member>>());
        expect(api.createMemberCalls, 1);
        expect(localEmail.clearCalls, 0);
        expect(identity().notice, isNull);
      },
    );

    test('a lost answer is unknown and the update is not sent again', () async {
      credentials.memberToken = 'stored-token';
      api.updateMeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '请求超时，请检查网络后重试。',
        status: null,
      );

      final result = await controller.saveProfile(nickname: '新昵称');

      expect(result, isA<MutationUnknown<Member>>());
      expect(api.updateMeCalls, 1);
    });

    test('a member that could not be created means nothing was sent', () async {
      api.createMemberError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      final result = await controller.saveProfile(nickname: '新昵称');

      expect(result, isA<MutationNotSent<Member>>());
      expect(api.updateMeCalls, 0);
    });

    test(
      'a refusal for a token another operation replaced keeps the new identity',
      () async {
        credentials.memberToken = 'old-token';
        api.updateMeResult = Completer<Member>();
        final saving = controller.saveProfile(nickname: '新昵称');
        await pumpEventQueue();
        expect(api.updateMeCalls, 1);

        api.getMeError = unauthorized;
        api.createdMember = replacement;
        await controller.ensureMember();
        expect(credentials.memberToken, 'new-member-token');
        api.updateMeResult!.completeError(unauthorized);
        final result = await saving;

        expect(result, isA<MutationFailed<Member>>());
        expect(api.createMemberCalls, 1);
        expect(credentials.deleteMemberCalls, 1);
        expect(credentials.memberToken, 'new-member-token');
        expect(identity().member?.id, 'new-id');
      },
    );

    test(
      'a lost answer is followed by one read-back, never a resend',
      () async {
        credentials.memberToken = 'stored-token';
        api.updateMeError = const ApiException(
          code: LocalErrorCodes.network,
          message: '请求超时，请检查网络后重试。',
          status: null,
        );

        final result = await controller.saveProfile(nickname: '新昵称');
        await pumpEventQueue();

        expect(result, isA<MutationUnknown<Member>>());
        expect(api.updateMeCalls, 1);
        expect(api.getMeCalls, 1);
        expect(identity().member?.id, 'member-id');
      },
    );

    test('an update turned away for coming too often is refused, read back '
        'never, and can be sent again at once', () async {
      credentials.memberToken = 'stored-token';
      api.updateMeError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
      );

      final refused = await controller.saveProfile(nickname: '新昵称');
      await pumpEventQueue();

      expect(
        refused,
        isA<MutationFailed<Member>>()
            .having((r) => r.code, 'code', 'RATE_LIMITED')
            .having((r) => r.message, 'message', '请求太频繁，请稍后再试。'),
      );
      expect(api.getMeCalls, 0);
      expect(api.createMemberCalls, 0);
      expect(identity().notice, isNull);

      api.updateMeError = null;
      final saved = await controller.saveProfile(nickname: '新昵称');

      expect(saved, isA<MutationSucceeded<Member>>());
      expect(api.updateMeCalls, 2);
    });

    test('an undecodable 2xx answer may have been applied', () async {
      credentials.memberToken = 'stored-token';
      api.updateMeError = const ApiException(
        code: LocalErrorCodes.protocolMismatch,
        message: '服务器返回了无法识别的数据，请升级 Alisten。',
        status: 200,
      );

      final result = await controller.saveProfile(nickname: '新昵称');
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<Member>>());
      expect(api.updateMeCalls, 1);
      expect(api.getMeCalls, 1);
    });

    test('an unreadable error answer is a plain failure', () async {
      credentials.memberToken = 'stored-token';
      api.updateMeError = const ApiException(
        code: LocalErrorCodes.protocolMismatch,
        message: '服务器返回了无法识别的数据，请升级 Alisten。',
        status: 400,
      );

      final result = await controller.saveProfile(nickname: '新昵称');

      expect(result, isA<MutationFailed<Member>>());
      expect(api.getMeCalls, 0);
    });

    test('an unreadable keychain means nothing was sent', () async {
      credentials.readMemberTokenError = PlatformException(
        code: '-25308',
        message: 'User interaction is not allowed.',
      );

      final result = await controller.saveProfile(nickname: '新昵称');

      expect(result, isA<MutationNotSent<Member>>());
      expect(api.updateMeCalls, 0);
      expect(api.createMemberCalls, 0);
    });
  });

  group('resetForServerChange', () {
    test('a member created before the reset keeps the token where it was '
        'asked for but is not shown', () async {
      final creating = api.createMemberGate = Completer<void>();
      final pending = controller.ensureMember();
      await pumpEventQueue();

      await controller.resetForServerChange();
      creating.complete();

      expect((await pending).id, 'member-id');
      expect(credentials.memberToken, 'new-member-token');
      expect(identity().member, isNull);
    });

    test('drops the member and the notice but keeps the replacement count, '
        'then restores the saved member', () async {
      credentials.memberToken = 'expired-token';
      api.getMeError = unauthorized;
      await controller.ensureMember();
      expect(identity().notice, identityRenewedNotice);
      expect(identity().session, 1);
      api.getMeError = null;
      api.getMeResult = Completer<Member>();

      final resetting = controller.resetForServerChange();

      expect(identity().member, isNull);
      expect(identity().notice, isNull);
      expect(identity().session, 1);
      api.getMeResult!.complete(replacement);
      await resetting;
      expect(identity().member?.id, 'new-id');
    });

    test('a failed restore is not thrown', () async {
      credentials.memberToken = 'stored-token';
      api.getMeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await controller.resetForServerChange();

      expect(credentials.memberToken, 'stored-token');
      expect(identity().member, isNull);
    });
  });

  group('across a server change', () {
    late FakeAlistenApi apiB;
    late FakeCredentialStore storeB;
    late ProviderContainer switching;
    late IdentityController identities;

    const memberB = Member(id: 'member-b', name: 'B 的听众', avatarHash: '');

    IdentityState current() => switching.read(identityControllerProvider);

    // 与换服务器后的应用一样，API 与凭据跟随 [_serverProvider]。
    setUp(() {
      apiB = FakeAlistenApi()..createdMember = memberB;
      storeB = FakeCredentialStore();
      final apis = {'a': api, 'b': apiB};
      final stores = {'a': credentials, 'b': storeB};
      switching = ProviderContainer(
        overrides: [
          alistenApiProvider.overrideWith(
            (ref) => apis[ref.watch(_serverProvider)]!,
          ),
          credentialStoreProvider.overrideWith(
            (ref) => stores[ref.watch(_serverProvider)]!,
          ),
          clearLocalEmailProvider.overrideWithValue(localEmail.clear),
        ],
      );
      addTearDown(switching.dispose);
      identities = switching.read(identityControllerProvider.notifier);
    });

    Future<void> switchToB() async {
      switching.read(_serverProvider.notifier).switchTo('b');
      await identities.resetForServerChange();
    }

    test('a member being created on the old server keeps its token there and '
        'nothing reaches the new server', () async {
      final creating = api.createMemberGate = Completer<void>();
      final pending = identities.ensureMember();
      await pumpEventQueue();

      await switchToB();
      creating.complete();
      await pending;

      expect(credentials.memberToken, 'new-member-token');
      expect(storeB.memberToken, isNull);
      expect(current().member, isNull);
      expect(apiB.createMemberCalls + apiB.getMeCalls, 0);
    });

    test('a member asked for on the new server neither waits for nor shares '
        'the attempt on the old server', () async {
      final creating = api.createMemberGate = Completer<void>();
      final onA = identities.ensureMember();
      await pumpEventQueue();

      await switchToB();
      final onB = identities.ensureMember();
      await pumpEventQueue();

      expect(apiB.createMemberCalls, 1);
      expect(await onB, memberB);
      expect(storeB.memberToken, 'new-member-token');
      creating.complete();
      expect((await onA).id, 'member-id');
      expect(current().member, memberB);
      expect(credentials.memberToken, 'new-member-token');
    });

    test('a token the old server rejects after the change is only discarded '
        'there, without a notice or touching the email', () async {
      credentials.memberToken = 'a';
      final checking = api.getMeResult = Completer<Member>();
      final pending = identities.ensureMember();
      await pumpEventQueue();

      await switchToB();
      checking.completeError(unauthorized);
      await expectLater(pending, throwsException);

      expect(credentials.deleteMemberCalls, 1);
      expect(credentials.memberToken, isNull);
      expect(api.createMemberCalls, 0);
      expect(storeB.deleteMemberCalls, 0);
      expect(storeB.memberToken, isNull);
      expect(apiB.createMemberCalls, 0);
      expect(localEmail.clearCalls, 0);
      expect(current().notice, isNull);
      expect(current().session, 0);
      expect(current().member, isNull);
    });

    test('a profile the old server refuses after the change creates no member '
        'there and says the server changed', () async {
      credentials.memberToken = 'a';
      final saving = api.updateMeResult = Completer<Member>();
      final result = identities.saveProfile(nickname: 'A 的昵称');
      await pumpEventQueue();

      await switchToB();
      saving.completeError(unauthorized);

      expect(
        await result,
        isA<MutationFailed<Member>>().having(
          (failed) => failed.message,
          'message',
          '服务器已经切换，这次操作没有完成。',
        ),
      );
      expect(credentials.deleteMemberCalls, 1);
      expect(credentials.memberToken, isNull);
      expect(api.createMemberCalls, 0);
      expect(storeB.memberToken, isNull);
      expect(apiB.createMemberCalls, 0);
      expect(current().notice, isNull);
    });

    test('a profile saved on the old server is not shown on the new '
        'one', () async {
      credentials.memberToken = 'a';
      final saving = api.updateMeResult = Completer<Member>();
      final result = identities.saveProfile(nickname: 'A 的昵称');
      await pumpEventQueue();

      await switchToB();
      saving.complete(
        const Member(id: 'member-id', name: 'A 的昵称', avatarHash: ''),
      );

      expect(await result, isA<MutationSucceeded<Member>>());
      expect(current().member, isNull);
    });

    test('a profile update to the old server whose answer is lost re-reads '
        'no member', () async {
      credentials.memberToken = 'a';
      storeB.memberToken = 'b';
      final saving = api.updateMeResult = Completer<Member>();
      final result = identities.saveProfile(nickname: 'A 的昵称');
      await pumpEventQueue();

      await switchToB();
      expect(apiB.getMeCalls, 1);
      saving.completeError(
        const ApiException(
          code: LocalErrorCodes.network,
          message: '网络请求失败，请检查网络后重试。',
          status: null,
        ),
      );

      expect(await result, isA<MutationUnknown<Member>>());
      await pumpEventQueue();
      expect(api.getMeCalls, 0);
      expect(apiB.getMeCalls, 1);
    });

    test('a refusal reported after the change replaces nothing on either '
        'server and only drops the refused token of the old one', () async {
      credentials
        ..memberToken = 'a'
        ..tickets['room-id'] = 'ticket-a';
      await switchToB();

      final text = await identities.recoverFromRefusal(credentials, 'a');

      expect(text, serverChangedNotice);
      expect(credentials.memberToken, isNull);
      expect(credentials.tickets, isEmpty);
      expect(api.createMemberCalls, 0);
      expect(apiB.createMemberCalls, 0);
      expect(storeB.memberToken, isNull);
      expect(storeB.deleteMemberCalls, 0);
      expect(localEmail.clearCalls, 0);
      expect(current().notice, isNull);
      expect(current().session, 0);
    });

    test('a token of the old server that is no longer the refused one '
        'stays', () async {
      credentials.memberToken = 'newer';
      await switchToB();

      expect(
        await identities.recoverFromRefusal(credentials, 'a'),
        serverChangedNotice,
      );
      expect(credentials.memberToken, 'newer');
      expect(credentials.deleteMemberCalls, 0);
    });

    test('a server change while the replacement waits in line says the '
        'server changed', () async {
      credentials.memberToken = 'a';
      final checking = api.getMeResult = Completer<Member>();
      final ensuring = identities.ensureMember();
      await pumpEventQueue();
      final recovering = identities.recoverFromRefusal(credentials, 'a');
      await pumpEventQueue();

      await switchToB();
      checking.complete(FakeAlistenApi.member);
      await ensuring;

      expect(await recovering, serverChangedNotice);
      expect(api.createMemberCalls, 0);
      expect(apiB.createMemberCalls, 0);
      expect(storeB.memberToken, isNull);
    });

    test('an old-server token that cannot be read now is not '
        'deleted', () async {
      credentials
        ..memberToken = 'a'
        ..tickets['room-id'] = 'ticket-a';
      await switchToB();
      credentials.readMemberTokenError = PlatformException(code: 'locked');

      expect(
        await identities.recoverFromRefusal(credentials, 'a'),
        serverChangedNotice,
      );
      expect(credentials.deleteMemberCalls, 0);
      expect(credentials.deleteTicketsCalls, 0);
      expect(credentials.tickets, isNotEmpty);
    });

    test('a refused token that could not be read before sending deletes '
        'nothing on the old server, even with no token stored there', () async {
      credentials.tickets['room-id'] = 'ticket-a';
      await switchToB();

      expect(
        await identities.recoverFromRefusal(credentials, null),
        serverChangedNotice,
      );
      expect(credentials.deleteMemberCalls, 0);
      expect(credentials.deleteTicketsCalls, 0);
      expect(credentials.tickets, isNotEmpty);
    });

    test('a refusal reported after the change waits for a sign-in still '
        'running on the old server', () async {
      credentials.memberToken = 'a';
      final signingIn = api.loginGate = Completer<void>();
      final adopting = identities.adoptSession(
        (api) => api.login(username: 'mao', password: 'password1'),
      );
      await pumpEventQueue();
      await switchToB();

      final recovering = identities.recoverFromRefusal(credentials, 'a');
      await pumpEventQueue();
      signingIn.complete();
      await adopting;

      expect(await recovering, serverChangedNotice);
      expect(credentials.memberToken, 'account-token');
      expect(credentials.deleteMemberCalls, 0);
    });

    test('a server change while the new guest is being created says the '
        'server changed', () async {
      credentials.memberToken = 'a';
      final creating = api.createMemberGate = Completer<void>();
      final recovering = identities.recoverFromRefusal(credentials, 'a');
      await pumpEventQueue();

      await switchToB();
      creating.complete();

      expect(await recovering, serverChangedNotice);
      expect(credentials.memberToken, 'new-member-token');
      expect(storeB.memberToken, isNull);
      expect(apiB.createMemberCalls, 0);
      expect(current().notice, isNull);
    });

    test('a new guest that cannot be created after the server changed says '
        'the server changed', () async {
      credentials.memberToken = 'a';
      final creating = api.createMemberGate = Completer<void>();
      final recovering = identities.recoverFromRefusal(credentials, 'a');
      await pumpEventQueue();

      await switchToB();
      creating.completeError(
        const ApiException(
          code: LocalErrorCodes.network,
          message: '网络请求失败，请检查网络后重试。',
          status: null,
        ),
      );

      expect(await recovering, serverChangedNotice);
      expect(current().notice, isNull);
    });

    test('a refusal with an unread token that waits in line past a server '
        'change deletes nothing on the old server', () async {
      credentials
        ..memberToken = 'a'
        ..tickets['room-id'] = 'ticket-a';
      final checking = api.getMeResult = Completer<Member>();
      final ensuring = identities.ensureMember();
      await pumpEventQueue();
      final recovering = identities.recoverFromRefusal(credentials, null);
      await pumpEventQueue();

      await switchToB();
      checking.complete(FakeAlistenApi.member);
      await ensuring;

      expect(await recovering, serverChangedNotice);
      expect(credentials.memberToken, 'a');
      expect(credentials.deleteMemberCalls, 0);
      expect(credentials.deleteTicketsCalls, 0);
      expect(api.createMemberCalls, 0);
    });

    test('an exchange answered after the change changes nothing on the new '
        'server', () async {
      credentials.memberToken = 'a';
      await identities.restore();
      api.finishGithubGate = Completer<void>();
      final exchanging = identities.adoptSessionIfIssued(
        (api) => api.finishGithubLogin(code: 'c-1', nonce: 'n' * 43),
      );
      await pumpEventQueue();

      await switchToB();
      api.finishGithubGate!.complete();
      await exchanging;

      expect(current().member, isNull);
      expect(current().account, isNull);
      expect(credentials.memberToken, 'a');
      expect(storeB.memberToken, isNull);
    });

    test('an exchange answered after the change leaves a member with the same '
        'id on the new server alone', () async {
      credentials.memberToken = 'a';
      storeB.memberToken = 'b';
      await identities.restore();
      api.finishGithubGate = Completer<void>();
      final exchanging = identities.adoptSessionIfIssued(
        (api) => api.finishGithubLogin(code: 'c-1', nonce: 'n' * 43),
      );
      await pumpEventQueue();

      await switchToB();
      expect(current().member?.id, FakeAlistenApi.member.id);
      api.finishGithubGate!.complete();
      await exchanging;

      expect(current().account, isNull);
    });
  });

  group('adoptSession', () {
    test(
      'writes the new token, drops every ticket and counts a session',
      () async {
        credentials.memberToken = 'guest-token';
        credentials.tickets['room-id'] = 'guest-ticket';
        api.recordListens = false;

        final signedIn = await controller.adoptSession(
          (api) => api.login(username: 'mao', password: 'password1'),
        );

        expect(signedIn.memberToken, 'account-token');
        expect(credentials.memberToken, 'account-token');
        expect(credentials.tickets, isEmpty);
        expect(identity().member?.id, 'account-member');
        expect(identity().account?.username, 'mao');
        expect(identity().recordListens, isFalse);
        expect(identity().session, 1);
        expect(localEmail.clearCalls, 1);
      },
    );

    test('creates a guest first when this device has no identity', () async {
      await controller.adoptSession(
        (api) => api.login(username: 'mao', password: 'password1'),
      );

      expect(api.createMemberCalls, 1);
      expect(api.loginCalls, 1);
      expect(credentials.memberToken, 'account-token');
      expect(identity().session, 1);
    });

    test('creating the first guest does not count a session', () async {
      await controller.ensureMember();

      expect(credentials.memberToken, 'new-member-token');
      expect(identity().session, 0);
    });

    test('a profile that cannot be read after signing in does not fail the '
        'sign-in', () async {
      api.getMeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await controller.adoptSession(
        (api) => api.login(username: 'mao', password: 'password1'),
      );

      expect(credentials.memberToken, 'account-token');
      expect(identity().member?.id, 'account-member');
      expect(identity().account?.username, 'mao');
      expect(identity().recordListens, isTrue);
      expect(identity().session, 1);
    });

    test('a refusal of the old token while signing in waits and replaces '
        'nothing', () async {
      credentials.memberToken = 'guest-token';
      api.loginGate = Completer<void>();

      final signingIn = controller.adoptSession(
        (api) => api.login(username: 'mao', password: 'password1'),
      );
      await pumpEventQueue();
      final refused = controller.replaceAfterUnauthorized(
        rejectedToken: 'guest-token',
      );
      api.loginGate!.complete();
      await signingIn;
      final member = await refused;

      expect(api.createMemberCalls, 0);
      expect(member.id, 'account-member');
      expect(credentials.memberToken, 'account-token');
    });

    test(
      'a rejected guest token is replaced and the refusal is rethrown',
      () async {
        credentials.memberToken = 'guest-token';
        api.loginError = unauthorized;

        await expectLater(
          controller.adoptSession(
            (api) => api.login(username: 'mao', password: 'password1'),
          ),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
          ),
        );

        expect(credentials.memberToken, 'new-member-token');
        expect(identity().session, 1);
      },
    );

    test('wrong credentials leave the identity alone', () async {
      credentials.memberToken = 'guest-token';
      credentials.tickets['room-id'] = 'guest-ticket';
      api.loginError = const ApiException(
        code: 'INVALID_CREDENTIALS',
        message: '用户名或密码不对',
        status: 401,
      );

      await expectLater(
        controller.adoptSession(
          (api) => api.login(username: 'mao', password: 'password1'),
        ),
        throwsA(isA<ApiException>()),
      );

      expect(credentials.memberToken, 'guest-token');
      expect(credentials.tickets, {'room-id': 'guest-ticket'});
      expect(identity().session, 0);
    });
  });

  group('adoptSessionIfIssued', () {
    const issued = GithubExchange(
      signedIn: SignedIn(
        memberToken: 'account-token',
        member: accountMember,
        account: Account(github: true),
      ),
      member: accountMember,
      account: Account(github: true),
    );

    Future<GithubExchange> exchange() => controller.adoptSessionIfIssued(
      (api) => api.finishGithubLogin(code: 'c-1', nonce: 'n' * 43),
    );

    test('a new session is adopted like a sign-in', () async {
      credentials
        ..memberToken = 'guest-token'
        ..tickets['room-id'] = 'guest-ticket';
      api.githubExchange = issued;

      final result = await exchange();

      expect(result.signedIn?.memberToken, 'account-token');
      expect(credentials.memberToken, 'account-token');
      expect(credentials.tickets, isEmpty);
      expect(identity().member?.id, 'account-member');
      expect(identity().account?.github, isTrue);
      expect(identity().session, 1);
      expect(localEmail.clearCalls, 1);
      expect(api.getMeCalls, 1);
    });

    test('without a new session the token, tickets and session stay, and '
        'the member and account are updated', () async {
      credentials
        ..memberToken = 'guest-token'
        ..tickets['room-id'] = 'guest-ticket';
      await controller.restore();
      const renamed = Member(
        id: 'member-id',
        name: 'GitHub 名字',
        avatarHash: '',
      );
      api.githubExchange = const GithubExchange(
        member: renamed,
        account: Account(github: true),
      );

      final result = await exchange();

      expect(result.signedIn, isNull);
      expect(credentials.memberToken, 'guest-token');
      expect(credentials.tickets, {'room-id': 'guest-ticket'});
      expect(identity().session, 0);
      expect(identity().member?.name, 'GitHub 名字');
      expect(identity().account?.github, isTrue);
      expect(localEmail.clearCalls, 0);
    });

    test('an answer for another member leaves the state alone', () async {
      credentials.memberToken = 'guest-token';
      await controller.restore();
      api.githubExchange = const GithubExchange(
        member: accountMember,
        account: Account(github: true),
      );

      await exchange();

      expect(identity().member?.id, 'member-id');
      expect(identity().account, isNull);
    });

    test('without a token no guest is made and the request goes out as it '
        'is', () async {
      var sentWithToken = true;

      await expectLater(
        controller.adoptSessionIfIssued((api) async {
          sentWithToken = credentials.memberToken != null;
          throw const ApiException(
            code: LocalErrorCodes.noToken,
            message: '缺少身份凭据，请重新进入后再试。',
            status: null,
          );
        }),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            LocalErrorCodes.noToken,
          ),
        ),
      );

      expect(sentWithToken, isFalse);
      expect(api.createMemberCalls, 0);
      expect(credentials.memberToken, isNull);
    });

    test('a refused token is replaced and the refusal rethrown', () async {
      credentials.memberToken = 'guest-token';
      api.finishGithubError = unauthorized;

      await expectLater(
        exchange(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );

      expect(credentials.memberToken, 'new-member-token');
      expect(identity().session, 1);
    });

    test('a refusal without a token replaces nothing', () async {
      await expectLater(
        controller.adoptSessionIfIssued((api) async => throw unauthorized),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );

      expect(api.createMemberCalls, 0);
      expect(credentials.memberToken, isNull);
      expect(identity().session, 0);
    });

    test('a profile that cannot be read after a new session keeps the new '
        'token', () async {
      credentials.memberToken = 'guest-token';
      api
        ..githubExchange = issued
        ..getMeError = const ApiException(
          code: LocalErrorCodes.network,
          message: '网络请求失败，请检查网络后重试。',
          status: null,
        );

      final result = await exchange();

      expect(result.signedIn?.memberToken, 'account-token');
      expect(credentials.memberToken, 'account-token');
      expect(identity().member?.id, 'account-member');
      expect(identity().account?.github, isTrue);
      expect(identity().session, 1);
    });

    test('a refusal of the old token during the exchange waits and replaces '
        'nothing', () async {
      credentials.memberToken = 'guest-token';
      api
        ..finishGithubGate = Completer<void>()
        ..githubExchange = issued;

      final exchanging = exchange();
      await pumpEventQueue();
      final refused = controller.replaceAfterUnauthorized(
        rejectedToken: 'guest-token',
      );
      api.finishGithubGate!.complete();
      await exchanging;
      final member = await refused;

      expect(api.createMemberCalls, 0);
      expect(member.id, 'account-member');
      expect(credentials.memberToken, 'account-token');
    });
  });

  group('signOut', () {
    setUp(() async {
      credentials.memberToken = 'account-token';
      api.me = accountMember;
      api.account = const Account(username: 'mao', github: false);
      await controller.restore();
    });

    test('drops the account session and starts a new guest', () async {
      credentials.tickets['room-id'] = 'account-ticket';

      await controller.signOut((api) => api.logout());

      expect(api.logoutCalls, 1);
      expect(credentials.memberToken, 'new-member-token');
      expect(credentials.tickets, isEmpty);
      expect(identity().account, isNull);
      expect(identity().member?.id, 'member-id');
      expect(identity().session, 1);
    });

    test('a session the server already dropped counts as signed out', () async {
      api.logoutError = unauthorized;

      await controller.signOut((api) => api.logout());

      expect(credentials.memberToken, 'new-member-token');
      expect(identity().account, isNull);
    });

    test('a network failure keeps the account', () async {
      api.logoutError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await expectLater(
        controller.signOut((api) => api.logout()),
        throwsA(isA<ApiException>()),
      );

      expect(credentials.memberToken, 'account-token');
      expect(identity().account?.username, 'mao');
      expect(identity().session, 0);
    });

    test('a guest that cannot be created leaves the identity empty', () async {
      api.createMemberError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await controller.signOut((api) => api.logout());

      expect(credentials.memberToken, isNull);
      expect(identity().member, isNull);
      expect(identity().session, 1);
    });

    test('the signed-out token refused later only brings the missing '
        'guest', () async {
      api.createMemberError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );
      await controller.signOut((api) => api.logout());
      api.createMemberError = null;

      await controller.replaceAfterUnauthorized(rejectedToken: 'account-token');

      expect(identity().session, 1);
      expect(identity().member?.id, 'member-id');
      expect(credentials.memberToken, 'new-member-token');
      expect(credentials.deleteMemberCalls, 1);
      expect(localEmail.clearCalls, 1);
    });
  });

  group('a registered account the server no longer accepts', () {
    setUp(() async {
      credentials.memberToken = 'account-token';
      api.me = accountMember;
      api.account = const Account(username: 'mao', github: false);
      await controller.restore();
      api.getMeError = unauthorized;
    });

    test('is announced as signed out when restored', () async {
      credentials.tickets['room-id'] = 'account-ticket';

      final discarded = await controller.restore();

      expect(discarded, isTrue);
      expect(identity().notice, signedOutNotice);
      expect(identity().account, isNull);
      expect(credentials.tickets, isEmpty);
    });

    test('is announced as signed out when replaced', () async {
      await controller.replaceAfterUnauthorized(rejectedToken: 'account-token');

      expect(identity().notice, signedOutNotice);
    });

    test('already discarded by restore, is not discarded again when '
        'replaced', () async {
      await controller.restore();
      final session = identity().session;

      final member = await controller.replaceAfterUnauthorized(
        rejectedToken: 'account-token',
      );

      expect(session, 1);
      expect(identity().session, session);
      expect(member.id, 'member-id');
      expect(identity().member?.id, 'member-id');
      expect(api.createMemberCalls, 1);
      expect(credentials.memberToken, 'new-member-token');
      expect(credentials.deleteMemberCalls, 1);
      expect(localEmail.clearCalls, 1);
      expect(identity().notice, signedOutNotice);
    });
  });

  test('restore reports a valid or missing identity as kept', () async {
    expect(await controller.restore(), isFalse);
    credentials.memberToken = 'stored-token';
    expect(await controller.restore(), isFalse);
  });

  test('updateAccount applies only to the member that asked', () async {
    credentials.memberToken = 'stored-token';
    await controller.restore();

    controller.updateAccount('someone-else', const Account(github: false));
    expect(identity().account, isNull);

    controller.updateAccount(
      'member-id',
      const Account(username: 'mao', github: false),
    );
    expect(identity().account?.username, 'mao');
  });

  test('saving an email for an account keeps it on the account', () async {
    credentials.memberToken = 'account-token';
    api.account = const Account(username: 'mao', github: false);
    await controller.restore();

    await controller.saveProfile(email: '  mao@example.com ');

    expect(identity().account?.email, 'mao@example.com');
  });
}

final _serverProvider = NotifierProvider<_Server, String>(_Server.new);

final class _Server extends Notifier<String> {
  @override
  String build() => 'a';

  void switchTo(String server) => state = server;
}
