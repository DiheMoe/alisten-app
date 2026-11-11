import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/application/github_controller.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';
import '../account_test_doubles.dart';

const _network = ApiException(
  code: LocalErrorCodes.network,
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

const _rateLimited = ApiException(
  code: 'RATE_LIMITED',
  message: '请求太频繁，请稍后再试。',
  status: 429,
  retryAfter: Duration(seconds: 30),
);

ApiException _refusal(String code, [String message = '服务端']) =>
    ApiException(code: code, message: message, status: 400);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeGithubAuthorizer authorizer;
  late FakeRoomTransportFactory rooms;
  late ProviderContainer container;

  GithubController github() =>
      container.read(githubControllerProvider.notifier);
  IdentityState identity() => container.read(identityControllerProvider);

  Future<void> open([
    Map<String, Object> stored = const {},
    CredentialStore Function(String serverId)? stores,
  ]) async {
    container = ProviderContainer(
      overrides: [
        ...alistenWiring(await loadPreferences(stored)),
        alistenApiProvider.overrideWithValue(api),
        credentialStoreFactoryProvider.overrideWithValue(
          stores ?? (_) => credentials,
        ),
        roomTransportFactoryProvider.overrideWithValue(rooms.call),
        connectivityStatusProvider.overrideWith((ref) => const Stream.empty()),
        githubAuthorizerProvider.overrideWithValue(authorizer),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> signedInAs(Account account) async {
    credentials.memberToken = 'account-token';
    api
      ..me = accountMember
      ..account = account;
    await container.read(identityControllerProvider.notifier).restore();
  }

  Future<void> enterRoom() async {
    await container.read(roomControllerProvider.notifier).openRoom('listen');
    rooms.last.emitHello();
    await pumpEventQueue();
  }

  // 走正式的切换流程：身份换到新服务器的作用域，并按新服务器的凭据恢复。
  Future<void> switchToB() async {
    await container.read(serverSwitcherProvider).switchTo(serverB);
    await pumpEventQueue();
  }

  // 保持监听，否则 autoDispose 的 provider 读完就释放，证明不了失效。
  Future<void> watchSite() async {
    final sub = container.listen(siteCapabilitiesProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(siteCapabilitiesProvider.future);
  }

  setUp(() {
    api = FakeAlistenApi()..rooms = [roomListing()];
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
    authorizer = FakeGithubAuthorizer();
    rooms = FakeRoomTransportFactory();
  });

  group('signing in', () {
    test('a device without an identity gets a guest first', () async {
      credentials.memberToken = null;
      await open();

      final result = await github().signIn();

      expect(result, isA<MutationSucceeded<GithubOutcome>>());
      expect(api.createMemberCalls, 1);
      expect(api.githubStarts.single.intent, GithubIntent.login);
      expect(api.githubStarts.single.currentPassword, isNull);
      expect(authorizer.opened, [api.githubUrl]);
    });

    test('the exchange carries the code and the nonce of its start, and '
        'each start has a new nonce', () async {
      await open();

      await github().signIn();
      await github().signIn();

      final starts = [for (final start in api.githubStarts) start.nonce];
      final finishes = [for (final finish in api.githubFinishes) finish.nonce];
      expect(finishes, starts);
      expect(starts.first, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(starts.last, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(starts.first, isNot(starts.last));
      expect(api.githubFinishes.first.code, 'github-code');
    });

    test('a GitHub bound to an account signs in to it', () async {
      await open();
      api.githubExchange = const GithubExchange(
        signedIn: SignedIn(
          memberToken: 'github-account-token',
          member: accountMember,
          account: Account(username: 'mao', github: true),
        ),
        member: accountMember,
        account: Account(username: 'mao', github: true),
      );

      final result = await github().signIn();

      expect(
        (result as MutationSucceeded<GithubOutcome>).value,
        GithubOutcome.signedIn,
      );
      expect(credentials.memberToken, 'github-account-token');
      expect(identity().account?.username, 'mao');
      expect(identity().session, 1);
    });

    test('a new GitHub registers this guest and moves its local '
        'email', () async {
      await open({'alisten.email': 'guest@example.com'});

      final result = await github().signIn();

      expect(
        (result as MutationSucceeded<GithubOutcome>).value,
        GithubOutcome.registered,
      );
      expect(identity().account?.github, isTrue);
      expect(credentials.memberToken, 'guest-token');
      expect(identity().session, 0);
      expect(api.updatedEmail, 'guest@example.com');
    });

    test('signing in holds a 4401 of the room until the exchange '
        'ends', () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await open();
      await enterRoom();
      api.finishGithubGate = Completer<void>();

      final signingIn = github().signIn();
      await pumpEventQueue();
      rooms.last.disconnect(code: 4401);
      await pumpEventQueue();
      expect(container.read(roomControllerProvider).failure, isNull);

      api.finishGithubGate!.complete();
      await signingIn;
      await pumpEventQueue();
      expect(
        container.read(roomControllerProvider).failure,
        RoomFailure.authorization,
      );
    });
  });

  group('an account', () {
    test('binds GitHub after its current password, without holding the '
        'room', () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await open();
      await signedInAs(const Account(username: 'mao', github: false));
      await enterRoom();
      api
        ..finishGithubGate = Completer<void>()
        ..githubExchange = const GithubExchange(
          member: accountMember,
          account: Account(username: 'mao', github: true),
        );

      final binding = github().bind('password1');
      await pumpEventQueue();
      rooms.last.disconnect(code: 4401);
      await pumpEventQueue();
      expect(
        container.read(roomControllerProvider).failure,
        RoomFailure.authorization,
      );

      api.finishGithubGate!.complete();
      final result = await binding;

      expect(
        (result as MutationSucceeded<GithubOutcome>).value,
        GithubOutcome.bound,
      );
      expect(api.githubStarts.single.currentPassword, 'password1');
      expect(identity().account?.github, isTrue);
      expect(identity().session, 0);
    });

    test('verifies with GitHub without a new session', () async {
      await open();
      await signedInAs(const Account(github: true));
      api.githubExchange = const GithubExchange(
        member: accountMember,
        account: Account(github: true),
      );

      final result = await github().verify();

      expect(
        (result as MutationSucceeded<GithubOutcome>).value,
        GithubOutcome.verified,
      );
      expect(api.githubStarts.single.intent, GithubIntent.verify);
      expect(api.githubStarts.single.currentPassword, isNull);
      expect(credentials.memberToken, 'account-token');
    });

    test('verifies without holding the room', () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await open();
      await signedInAs(const Account(github: true));
      await enterRoom();
      api
        ..finishGithubGate = Completer<void>()
        ..githubExchange = const GithubExchange(
          member: accountMember,
          account: Account(github: true),
        );

      final verifying = github().verify();
      await pumpEventQueue();
      rooms.last.disconnect(code: 4401);
      await pumpEventQueue();
      expect(
        container.read(roomControllerProvider).failure,
        RoomFailure.authorization,
      );

      api.finishGithubGate!.complete();
      final result = await verifying;

      expect(
        (result as MutationSucceeded<GithubOutcome>).value,
        GithubOutcome.verified,
      );
      expect(identity().session, 0);
    });
  });

  group('the running intent', () {
    test('is set while a flow runs and cleared however it ends', () async {
      await open();
      authorizer.gate = Completer<void>();

      final signingIn = github().signIn();
      await pumpEventQueue();
      expect(container.read(githubControllerProvider), GithubIntent.login);
      authorizer.gate!.complete();
      await signingIn;
      expect(container.read(githubControllerProvider), isNull);

      authorizer
        ..gate = null
        ..callback = null;
      await github().signIn();
      expect(container.read(githubControllerProvider), isNull);

      api.startGithubError = _refusal('INTERNAL');
      await github().signIn();
      expect(container.read(githubControllerProvider), isNull);
    });

    test('a second call with the same intent waits for the first, and '
        'another intent is a programming error', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: false));
      authorizer.gate = Completer<void>();

      final first = github().verify();
      final again = github().verify();
      await pumpEventQueue();

      expect(again, same(first));
      expect(() => github().bind('password1'), throwsStateError);
      expect(container.read(githubControllerProvider), GithubIntent.verify);
      authorizer.gate!.complete();
      await first;
      expect(authorizer.opened, hasLength(1));
      expect(api.githubStarts, hasLength(1));
    });

    test('a listener that asks again as the intent is set joins the same '
        'flow', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));
      authorizer.gate = Completer<void>();
      Future<MutationResult<GithubOutcome>>? again;
      final sub = container.listen(githubControllerProvider, (_, next) {
        if (next == GithubIntent.verify) again = github().verify();
      });
      addTearDown(sub.close);

      final first = github().verify();

      expect(again, same(first));
      authorizer.gate!.complete();
      await first;
      expect(api.githubStarts, hasLength(1));
    });
  });

  group('nothing is exchanged when the browser brings no code back', () {
    Uri callback(String fragment) =>
        Uri.parse('moe.dihe.alisten:/auth/github$fragment');

    for (final (name, configure, text) in [
      (
        'closing the browser',
        (FakeGithubAuthorizer a) => a.callback = null,
        githubNoResultText,
      ),
      (
        'a browser that cannot open',
        (FakeGithubAuthorizer a) => a.error = const GithubAuthorizerFailed(),
        '没有从 GitHub 确认你的身份，请稍后再试。',
      ),
      (
        'a refusal on GitHub',
        (FakeGithubAuthorizer a) => a.callback = callback('#error=denied'),
        '你在 GitHub 上取消了授权。',
      ),
      (
        'an authorization that expired',
        (FakeGithubAuthorizer a) => a.callback = callback('#error=expired'),
        'GitHub 授权已经过期，请重新发起。',
      ),
      (
        'a failure on the server',
        (FakeGithubAuthorizer a) => a.callback = callback('#error=failed'),
        '没有从 GitHub 确认你的身份，请稍后再试。',
      ),
      (
        'a callback without a code',
        (FakeGithubAuthorizer a) => a.callback = callback(''),
        githubNoResultText,
      ),
    ]) {
      test(name, () async {
        await open();
        configure(authorizer);

        final result = await github().signIn();

        expect((result as MutationNotSent<GithubOutcome>).message, text);
        expect(api.githubFinishes, isEmpty);
      });
    }

    test('an identity changed while the browser was open', () async {
      await open();
      authorizer.gate = Completer<void>();
      final signingIn = github().signIn();
      await pumpEventQueue();

      await container
          .read(identityControllerProvider.notifier)
          .signOut((api) async {});
      authorizer.gate!.complete();
      final result = await signingIn;

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        'GitHub 登录没有完成，请重新发起。',
      );
      expect(api.githubFinishes, isEmpty);
    });

    test('a server switched while the browser was open', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      authorizer.gate = Completer<void>();
      final signingIn = github().signIn();
      await pumpEventQueue();

      final servers = container.read(serverDirectoryProvider.notifier);
      await servers.add(serverB);
      await servers.setCurrent(serverB.id);
      authorizer.gate!.complete();
      final result = await signingIn;

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        serverChangedNotice,
      );
      expect(api.githubFinishes, isEmpty);
      expect(other.memberToken, isNull);
    });
  });

  group('a server switched before the browser opens', () {
    test('while the guest is made starts nothing', () async {
      final other = FakeCredentialStore();
      credentials.memberToken = null;
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      api.createMemberGate = Completer<void>();
      final signingIn = github().signIn();
      await pumpEventQueue();

      await switchToB();
      api.createMemberGate!.complete();
      final result = await signingIn;

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        serverChangedNotice,
      );
      expect(api.githubStarts, isEmpty);
      expect(authorizer.opened, isEmpty);
      expect(other.memberToken, isNull);
    });

    test('while the start is answered opens no browser', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      api.startGithubGate = Completer<void>();
      final signingIn = github().signIn();
      await pumpEventQueue();

      await switchToB();
      api.startGithubGate!.complete();
      final result = await signingIn;

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        serverChangedNotice,
      );
      expect(api.githubStarts, hasLength(1));
      expect(authorizer.opened, isEmpty);
      expect(api.githubFinishes, isEmpty);
    });
  });

  group('a server switched during the exchange', () {
    for (final (name, run) in [
      ('verifying', (GithubController github) => github.verify()),
      ('binding', (GithubController github) => github.bind('password1')),
    ]) {
      test('$name is told as done on the old server, and the new server is '
          'left alone', () async {
        final other = FakeCredentialStore();
        await open(const {}, (id) => id == serverB.id ? other : credentials);
        await signedInAs(const Account(username: 'mao', github: false));
        api
          ..finishGithubGate = Completer<void>()
          ..githubExchange = const GithubExchange(
            member: accountMember,
            account: Account(username: 'mao', github: true),
          );
        final running = run(github());
        await pumpEventQueue();

        await switchToB();
        api.finishGithubGate!.complete();
        final result = await running;

        expect(
          (result as MutationNotSent<GithubOutcome>).message,
          doneOnOldServerText,
        );
        expect(api.githubFinishes, hasLength(1));
        expect(identity().account, isNull);
        expect(credentials.memberToken, 'account-token');
        expect(other.memberToken, isNull);
      });
    }

    test('a registration does not move the local email into an account on '
        'the new server', () async {
      final other = FakeCredentialStore()..memberToken = 'b-token';
      await open({
        'alisten.email': 'guest@example.com',
      }, (id) => id == serverB.id ? other : credentials);
      api.finishGithubGate = Completer<void>();
      final signingIn = github().signIn();
      await pumpEventQueue();

      api.account = const Account(username: 'b-user', github: false);
      await switchToB();
      expect(identity().account?.username, 'b-user');
      api.finishGithubGate!.complete();
      final result = await signingIn;
      await pumpEventQueue();

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        doneOnOldServerText,
      );
      expect(api.updateMeCalls, 0);
    });

    test('a session for an account stays with the server that issued '
        'it', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      api
        ..finishGithubGate = Completer<void>()
        ..githubExchange = const GithubExchange(
          signedIn: SignedIn(
            memberToken: 'github-account-token',
            member: accountMember,
            account: Account(username: 'mao', github: true),
          ),
          member: accountMember,
          account: Account(username: 'mao', github: true),
        );
      final signingIn = github().signIn();
      await pumpEventQueue();

      await switchToB();
      api.finishGithubGate!.complete();
      final result = await signingIn;

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        doneOnOldServerText,
      );
      expect(credentials.memberToken, 'github-account-token');
      expect(other.memberToken, isNull);
      expect(identity().account, isNull);
    });
  });

  group('a start the server turns down', () {
    test('NOT_FOUND re-reads the site so that GitHub is hidden', () async {
      await open();
      await watchSite();
      api.startGithubError = _refusal('NOT_FOUND', '站点没有开启 GitHub 登录');

      final result = await github().signIn();

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        '站点没有开启 GitHub 登录',
      );
      await container.read(siteCapabilitiesProvider.future);
      expect(api.getSiteCalls, 2);
      expect(authorizer.opened, isEmpty);
    });

    for (final code in ['CONFLICT', 'FORBIDDEN']) {
      test('$code shows the server message and re-reads the profile', () async {
        await open();
        await signedInAs(const Account(username: 'mao', github: false));
        api.startGithubError = _refusal(code, '本机状态过时');
        final before = api.getMeCalls;

        final result = await github().verify();
        await pumpEventQueue();

        expect((result as MutationFailed<GithubOutcome>).message, '本机状态过时');
        expect(api.getMeCalls, greaterThan(before));
      });
    }

    test('a wrong current password is told apart, before sending or from '
        'the server', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: false));

      final local = await github().bind('short');
      expect(
        (local as MutationFailed<GithubOutcome>).code,
        githubWrongPasswordCode,
      );
      expect(local.message, '当前密码不对');
      expect(api.githubStarts, isEmpty);

      api.startGithubError = _refusal('INVALID_CREDENTIALS');
      final refused = await github().bind('password1');
      expect(
        (refused as MutationFailed<GithubOutcome>).code,
        githubWrongPasswordCode,
      );
      expect(authorizer.opened, isEmpty);
    });

    test('UNAUTHORIZED renews a guest and asks for another try', () async {
      await open();
      api.startGithubError = unauthorized;

      final result = await github().signIn();

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        '没有跳转到 GitHub，再试一次。',
      );
      expect(credentials.memberToken, 'new-member-token');
    });

    test('UNAUTHORIZED signs an account out', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: false));
      api.startGithubError = unauthorized;

      final result = await github().verify();

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        signedOutNotice,
      );
      expect(credentials.memberToken, 'new-member-token');
    });

    test('UNAUTHORIZED after a server switch says so and creates no '
        'guest', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      api
        ..startGithubGate = Completer<void>()
        ..startGithubError = unauthorized;
      final signingIn = github().signIn();
      await pumpEventQueue();

      await switchToB();
      api.startGithubGate!.complete();
      final result = await signingIn;

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        serverChangedNotice,
      );
      expect(api.createMemberCalls, 0);
      expect(other.memberToken, isNull);
      expect(authorizer.opened, isEmpty);
    });

    test('rate limiting says when to try again and opens no browser', () async {
      await open();
      api.startGithubError = _rateLimited;

      final result = await github().signIn();

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        '请求太频繁，请 30 秒后再试',
      );
      expect(authorizer.opened, isEmpty);
    });

    test('a network failure opens no browser', () async {
      await open();
      api.startGithubError = _network;

      final result = await github().signIn();

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        _network.message,
      );
      expect(authorizer.opened, isEmpty);
    });
  });

  group('an exchange the server turns down', () {
    test('INVALID_CREDENTIALS shows the server message', () async {
      await open();
      api.finishGithubError = _refusal('INVALID_CREDENTIALS', '兑换码已经过期');

      final result = await github().signIn();

      expect((result as MutationFailed<GithubOutcome>).message, '兑换码已经过期');
    });

    test('INVALID_CREDENTIALS while binding keeps the server code, so the '
        'password panel closes', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: false));
      api.finishGithubError = _refusal('INVALID_CREDENTIALS', '兑换码已经过期');

      final result = await github().bind('password1');

      expect(
        result,
        isA<MutationFailed<GithubOutcome>>()
            .having((r) => r.code, 'code', 'INVALID_CREDENTIALS')
            .having((r) => r.message, 'message', '兑换码已经过期'),
      );
    });

    test('CONFLICT shows the server message and re-reads the '
        'profile', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: false));
      api.finishGithubError = _refusal('CONFLICT', '这个 GitHub 已经绑定了其他账号');
      final before = api.getMeCalls;

      final result = await github().bind('password1');
      await pumpEventQueue();

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        '这个 GitHub 已经绑定了其他账号',
      );
      expect(api.getMeCalls, greaterThan(before));
    });

    test('FORBIDDEN while signing in is a closed registration', () async {
      await open();
      await watchSite();
      api.finishGithubError = _refusal('FORBIDDEN');

      final result = await github().signIn();

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        registrationClosedText,
      );
      await container.read(siteCapabilitiesProvider.future);
      expect(api.getSiteCalls, 2);
    });

    test('FORBIDDEN while verifying shows the server message and re-reads '
        'the profile', () async {
      await open();
      await signedInAs(const Account(github: true));
      api.finishGithubError = _refusal('FORBIDDEN', '本机状态过时');
      final before = api.getMeCalls;

      final result = await github().verify();
      await pumpEventQueue();

      expect((result as MutationFailed<GithubOutcome>).message, '本机状态过时');
      expect(api.getMeCalls, greaterThan(before));
    });

    test('NOT_FOUND re-reads the site', () async {
      await open();
      await watchSite();
      api.finishGithubError = _refusal('NOT_FOUND', '站点没有开启 GitHub 登录');

      await github().signIn();

      await container.read(siteCapabilitiesProvider.future);
      expect(api.getSiteCalls, 2);
    });

    test('UNAUTHORIZED while signing in asks to start again, replacing the '
        'guest once', () async {
      await open();
      api.finishGithubError = unauthorized;

      final result = await github().signIn();

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        'GitHub 登录没有完成，请重新发起。',
      );
      expect(api.createMemberCalls, 1);
      expect(credentials.memberToken, 'new-member-token');
    });

    test('UNAUTHORIZED while binding is a sign-out', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: false));
      api.finishGithubError = unauthorized;

      final result = await github().bind('password1');

      expect(
        (result as MutationFailed<GithubOutcome>).message,
        signedOutNotice,
      );
      expect(api.createMemberCalls, 1);
      expect(credentials.memberToken, 'new-member-token');
    });

    test('rate limiting says when to try again', () async {
      await open();
      api.finishGithubError = _rateLimited;

      final result = await github().signIn();

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        '请求太频繁，请 30 秒后再试',
      );
    });

    test('a missing token asks to start again', () async {
      await open();
      api.finishGithubError = const ApiException(
        code: LocalErrorCodes.noToken,
        message: '缺少身份凭据，请重新进入后再试。',
        status: null,
      );

      final result = await github().signIn();

      expect(
        (result as MutationNotSent<GithubOutcome>).message,
        'GitHub 登录没有完成，请重新发起。',
      );
    });

    test('a lost answer is unknown and re-reads the profile', () async {
      await open();
      api.finishGithubError = _network;
      final before = api.getMeCalls;

      final result = await github().signIn();
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<GithubOutcome>>());
      expect(api.getMeCalls, greaterThan(before));
    });
  });

  group('unbinding', () {
    setUp(() {
      api.site = const SiteCapabilities(
        registrationOpen: true,
        githubLogin: true,
      );
    });

    test('drops GitHub from the account', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));

      final result = await github().unbind('password1');

      expect(result, isA<MutationSucceeded<void>>());
      expect(api.unbindPassword, 'password1');
      expect(identity().account?.github, isFalse);
      expect(identity().account?.username, 'mao');
    });

    test('a password out of the rule is not sent', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));

      final result = await github().unbind('short');

      expect((result as MutationNotSent<void>).message, '当前密码不对');
      expect(api.unbindCalls, 0);
    });

    for (final (code, text) in [
      ('INVALID_CREDENTIALS', '当前密码不对'),
      ('CONFLICT', '这个账号还没有密码，先设置用户名和密码'),
      ('NOT_FOUND', '服务端'),
    ]) {
      test('$code is told as "$text"', () async {
        await open();
        await signedInAs(const Account(username: 'mao', github: true));
        api.unbindError = _refusal(code);

        final result = await github().unbind('password1');

        expect((result as MutationFailed<void>).message, text);
      });
    }

    test('CONFLICT re-reads the profile', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));
      api.unbindError = _refusal('CONFLICT');
      final before = api.getMeCalls;

      await github().unbind('password1');
      await pumpEventQueue();

      expect(api.getMeCalls, greaterThan(before));
    });

    test('NOT_FOUND re-reads the site so that GitHub is hidden', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));
      await watchSite();
      api.unbindError = _refusal('NOT_FOUND');

      await github().unbind('password1');

      await container.read(siteCapabilitiesProvider.future);
      expect(api.getSiteCalls, 2);
    });

    test('rate limiting says when to try again', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));
      api.unbindError = _rateLimited;

      final result = await github().unbind('password1');

      expect((result as MutationNotSent<void>).message, '请求太频繁，请 30 秒后再试');
    });

    test('UNAUTHORIZED signs the account out', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));
      api.unbindError = unauthorized;

      final result = await github().unbind('password1');

      expect((result as MutationFailed<void>).message, signedOutNotice);
      expect(credentials.memberToken, 'new-member-token');
    });

    test('a lost answer is unknown and re-reads the profile', () async {
      await open();
      await signedInAs(const Account(username: 'mao', github: true));
      api.unbindError = _network;
      final before = api.getMeCalls;

      final result = await github().unbind('password1');
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<void>>());
      expect(api.getMeCalls, greaterThan(before));
    });
  });

  test('the nonce, the code, the address and the password stay out of '
      'the log', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add(message);
    addTearDown(() => AppLog.onRecord = null);
    await open();
    await signedInAs(const Account(username: 'mao', github: true));

    api.finishGithubError = const FormatException('github-code');
    final exchanged = await github().bind('password1');
    authorizer.error = const FormatException('moe.dihe.alisten:/auth/github');
    final browsed = await github().bind('password1');
    api.unbindError = const FormatException('password1');
    final unbound = await github().unbind('password1');

    expect(exchanged, isA<MutationUnknown<GithubOutcome>>());
    expect(browsed, isA<MutationNotSent<GithubOutcome>>());
    expect(unbound, isA<MutationUnknown<void>>());
    expect(records, isNotEmpty);
    for (final secret in [
      ...[for (final start in api.githubStarts) start.nonce],
      'github-code',
      'password1',
      '${api.githubUrl}',
      'auth/github',
    ]) {
      expect(records.where((record) => record.contains(secret)), isEmpty);
    }
  });
}
