import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late ProviderContainer container;
  late AccountController account;

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
        roomTransportFactoryProvider.overrideWithValue(
          FakeRoomTransportFactory().call,
        ),
        connectivityStatusProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(container.dispose);
    account = container.read(accountControllerProvider);
  }

  // 走正式的切换流程：身份换到新服务器的作用域，并按新服务器的凭据恢复。
  Future<void> switchToB() async {
    await container.read(serverSwitcherProvider).switchTo(serverB);
    await pumpEventQueue();
  }

  setUp(() {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
  });

  group('login', () {
    test('checks the input before sending anything', () async {
      await open();

      final result = await account.login(
        username: 'Mao',
        password: 'password1',
      );

      expect(result, isA<MutationNotSent<Account>>());
      expect(api.loginCalls, 0);
    });

    test(
      'sends a saved device credential only when it is well formed',
      () async {
        await open();
        credentials.loginDevices['mao'] = deviceCredential;
        await account.login(username: 'mao', password: 'password1');
        expect(api.lastLogin?.device, deviceCredential);

        credentials
          ..memberToken = 'guest-token'
          ..loginDevices['mao'] = 'not-a-credential';
        api.account = null;
        await account.login(username: 'mao', password: 'password1');
        expect(api.lastLogin?.device, isNull);
      },
    );

    test('keeps the issued device credential and adopts the session', () async {
      await open();

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationSucceeded<Account>>());
      expect(credentials.loginDevices['mao'], issuedDevice);
      expect(credentials.memberToken, 'account-token');
      expect(identity().account?.username, 'mao');
    });

    for (final (code, text) in [
      ('INVALID_CREDENTIALS', wrongCredentialsText),
      ('UNAUTHORIZED', '身份已更新，请再登录一次'),
    ]) {
      test('$code is told as "$text"', () async {
        await open();
        api.loginError = ApiException(code: code, message: '服务端', status: 401);

        final result = await account.login(
          username: 'mao',
          password: 'password1',
        );

        expect(result, isA<MutationFailed<Account>>());
        expect((result as MutationFailed<Account>).message, text);
      });
    }

    test('a server switch while the device credential is read sends '
        'nothing to either server', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      final gate = Completer<void>();
      credentials
        ..loginDevices['mao'] = deviceCredential
        ..readLoginDeviceGate = gate;

      final pending = account.login(username: 'mao', password: 'password1');
      await pumpEventQueue();
      final servers = container.read(serverDirectoryProvider.notifier);
      await servers.add(serverB);
      await servers.setCurrent(serverB.id);
      expect(container.read(credentialStoreProvider), same(other));
      gate.complete();
      final result = await pending;

      expect((result as MutationNotSent<Account>).message, '服务器已经切换，这次操作没有完成。');
      expect(api.loginCalls, 0);
      expect(credentials.writeLoginDeviceCalls, 0);
      expect(other.writeLoginDeviceCalls, 0);
      expect(credentials.memberToken, 'guest-token');
    });

    test('rate limiting is not sent and says when to try again', () async {
      await open();
      api.loginError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: Duration(seconds: 30),
      );

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationNotSent<Account>).message, '请求太频繁，请 30 秒后再试');
    });

    test('a server switched during the request is told as done on the old '
        'server', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      api.loginGate = Completer<void>();
      final signingIn = account.login(username: 'mao', password: 'password1');
      await pumpEventQueue();

      final servers = container.read(serverDirectoryProvider.notifier);
      await servers.add(serverB);
      await servers.setCurrent(serverB.id);
      api.loginGate!.complete();
      final result = await signingIn;

      expect((result as MutationNotSent<Account>).message, doneOnOldServerText);
      expect(other.memberToken, isNull);
    });
  });

  group('register', () {
    test('moves the local email into the new account', () async {
      await open({'alisten.email': 'guest@example.com'});
      await container.read(identityControllerProvider.notifier).restore();

      final result = await account.register(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationSucceeded<Account>>());
      expect(identity().account?.username, 'mao');
      expect(api.updatedEmail, 'guest@example.com');
      expect(container.read(settingsControllerProvider).value.email, '');
      expect(identity().account?.email, 'guest@example.com');
    });

    test('an email the server refuses is dropped for good', () async {
      await open({'alisten.email': 'not-an-email'});
      api.updateMeError = const ApiException(
        code: 'INVALID_ARGUMENT',
        message: '邮箱格式不对',
        status: 400,
      );

      await account.register(username: 'mao', password: 'password1');

      expect(container.read(settingsControllerProvider).value.email, '');
    });

    test('an email that could not be sent is kept for later', () async {
      await open({'alisten.email': 'guest@example.com'});
      api.updateMeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await account.register(username: 'mao', password: 'password1');

      expect(
        container.read(settingsControllerProvider).value.email,
        'guest@example.com',
      );
    });

    test(
      'a closed registration is told and the capabilities are re-read',
      () async {
        await open();
        api.registerError = const ApiException(
          code: 'FORBIDDEN',
          message: '站点关闭了注册',
          status: 403,
        );
        // 保持监听，否则 autoDispose 的 provider 读完就释放，证明不了失效。
        final sub = container.listen(siteCapabilitiesProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(siteCapabilitiesProvider.future);

        final result = await account.register(
          username: 'mao',
          password: 'password1',
        );

        expect(
          (result as MutationFailed<Account>).message,
          registrationClosedText,
        );
        await container.read(siteCapabilitiesProvider.future);
        expect(api.getSiteCalls, 2);
      },
    );

    test(
      'a server switched while the guest is made registers nobody',
      () async {
        final other = FakeCredentialStore();
        credentials.memberToken = null;
        await open(const {}, (id) => id == serverB.id ? other : credentials);
        api.createMemberGate = Completer<void>();
        final registering = account.register(
          username: 'mao',
          password: 'password1',
        );
        await pumpEventQueue();

        await switchToB();
        api.createMemberGate!.complete();
        final result = await registering;

        expect(
          (result as MutationNotSent<Account>).message,
          serverChangedNotice,
        );
        expect(api.registerCalls, 0);
        expect(other.memberToken, isNull);
      },
    );

    test('a server switched during the request moves nothing into an '
        'account on the new server', () async {
      final other = FakeCredentialStore()..memberToken = 'b-token';
      await open({
        'alisten.email': 'guest@example.com',
      }, (id) => id == serverB.id ? other : credentials);
      await container.read(identityControllerProvider.notifier).restore();
      api.registerGate = Completer<void>();
      final registering = account.register(
        username: 'mao',
        password: 'password1',
      );
      await pumpEventQueue();

      api.account = const Account(username: 'b-user', github: false);
      await switchToB();
      expect(identity().account?.username, 'b-user');
      api.registerGate!.complete();
      final result = await registering;
      await pumpEventQueue();

      expect((result as MutationNotSent<Account>).message, doneOnOldServerText);
      expect(api.registerCalls, 1);
      expect(identity().account?.username, 'b-user');
      expect(api.updateMeCalls, 0);
      expect(
        container.read(settingsControllerProvider).value.email,
        'guest@example.com',
      );
    });
  });

  group('logout', () {
    test('a network failure keeps the account', () async {
      await open();
      await account.login(username: 'mao', password: 'password1');
      api.logoutError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      final result = await account.logout();

      expect((result as MutationFailed<void>).message, logoutFailedText);
      expect(identity().account?.username, 'mao');
    });

    test('signs out and becomes a guest', () async {
      await open();
      await account.login(username: 'mao', password: 'password1');

      final result = await account.logout();

      expect(result, isA<MutationSucceeded<void>>());
      expect(identity().account, isNull);
      expect(credentials.loginDevices['mao'], issuedDevice);
    });
  });

  group('changePassword', () {
    for (final (code, text) in [
      ('INVALID_CREDENTIALS', wrongCurrentPasswordText),
      ('CONFLICT', '这个账号还没有密码，先设置用户名和密码'),
    ]) {
      test('$code is told as "$text"', () async {
        await open();
        api.changePasswordError = ApiException(
          code: code,
          message: '服务端',
          status: 401,
        );

        final result = await account.changePassword(
          current: 'password1',
          next: 'password2',
        );

        expect((result as MutationFailed<void>).message, text);
      });
    }

    test('a new password out of the rule is not sent', () async {
      await open();

      final result = await account.changePassword(
        current: 'password1',
        next: 'short',
      );

      expect(result, isA<MutationNotSent<void>>());
      expect(api.changePasswordCalls, 0);
    });
  });
  group('redeemPairingCode', () {
    test('a code out of the rule is not sent', () async {
      await open();

      final result = await account.redeemPairingCode('abc');

      expect(
        (result as MutationNotSent<Account>).message,
        invalidPairingCodeText,
      );
      expect(api.redeemCalls, 0);
    });

    test('a code typed loosely is normalized, and signing in keeps no device '
        'credential', () async {
      await open();

      final result = await account.redeemPairingCode(' abcd-2345 ');

      expect(result, isA<MutationSucceeded<Account>>());
      expect(api.redeemedCode, 'ABCD2345');
      expect(credentials.memberToken, 'paired-token');
      expect(credentials.writeLoginDeviceCalls, 0);
      expect(identity().account?.username, 'mao');
      expect(identity().session, 1);
    });

    test('a device without an identity gets a guest first', () async {
      credentials.memberToken = null;
      await open();

      await account.redeemPairingCode('ABCD2345');

      expect(api.createMemberCalls, 1);
      expect(credentials.memberToken, 'paired-token');
    });

    for (final (code, text) in [
      ('INVALID_CREDENTIALS', '配对码不对或已经过期'),
      ('INVALID_ARGUMENT', invalidPairingCodeText),
      ('CONFLICT', '已经登录了账号'),
      ('UNAUTHORIZED', '身份已更新，请再登录一次'),
    ]) {
      test('$code is told as "$text"', () async {
        await open();
        api.redeemError = ApiException(
          code: code,
          message: '配对码不对或已经过期',
          status: 400,
        );

        final result = await account.redeemPairingCode('ABCD2345');

        expect((result as MutationFailed<Account>).message, text);
      });
    }

    test('CONFLICT re-reads the profile', () async {
      await open();
      api.redeemError = const ApiException(
        code: 'CONFLICT',
        message: '服务端',
        status: 409,
      );
      final before = api.getMeCalls;

      await account.redeemPairingCode('ABCD2345');
      await pumpEventQueue();

      expect(api.getMeCalls, greaterThan(before));
    });

    test('UNAUTHORIZED is replaced once, inside the identity queue', () async {
      await open();
      api.redeemError = unauthorized;

      await account.redeemPairingCode('ABCD2345');

      expect(api.createMemberCalls, 1);
      expect(credentials.memberToken, 'new-member-token');
    });

    test('a lost answer is unknown and re-reads the profile', () async {
      await open();
      api.redeemError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );
      final before = api.getMeCalls;

      final result = await account.redeemPairingCode('ABCD2345');
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<Account>>());
      expect(api.getMeCalls, greaterThan(before));
    });

    test('rate limiting says when to try again', () async {
      await open();
      api.redeemError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: Duration(seconds: 10),
      );

      final result = await account.redeemPairingCode('ABCD2345');

      expect((result as MutationNotSent<Account>).message, '请求太频繁，请 10 秒后再试');
    });

    test('a server switched during the request is told as done on the old '
        'server', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      api.redeemGate = Completer<void>();
      final redeeming = account.redeemPairingCode('ABCD2345');
      await pumpEventQueue();

      final servers = container.read(serverDirectoryProvider.notifier);
      await servers.add(serverB);
      await servers.setCurrent(serverB.id);
      api.redeemGate!.complete();
      final result = await redeeming;

      expect((result as MutationNotSent<Account>).message, doneOnOldServerText);
      expect(other.memberToken, isNull);
    });
  });

  group('setCredentials', () {
    Future<void> asGithubAccount() async {
      credentials.memberToken = 'account-token';
      api
        ..me = accountMember
        ..account = const Account(github: true)
        ..registeredAccount = const Account(username: 'mao', github: true);
      await container.read(identityControllerProvider.notifier).restore();
    }

    test('gives a GitHub-only account a username and password and moves '
        'the local email', () async {
      await open({'alisten.email': 'guest@example.com'});
      await asGithubAccount();

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationSucceeded<Account>>());
      expect(identity().account?.username, 'mao');
      expect(identity().account?.github, isTrue);
      expect(api.updatedEmail, 'guest@example.com');
      expect(credentials.memberToken, 'account-token');
    });

    test('input out of the rule is not sent', () async {
      await open();
      await asGithubAccount();

      final result = await account.setCredentials(
        username: 'Mao',
        password: 'password1',
      );

      expect(result, isA<MutationNotSent<Account>>());
      expect(api.registerCalls, 0);
    });

    test('FORBIDDEN means the GitHub check is older than 10 minutes, and '
        'the site is left as it is', () async {
      await open();
      await asGithubAccount();
      api.registerError = const ApiException(
        code: 'FORBIDDEN',
        message: '服务端',
        status: 403,
      );
      final sub = container.listen(siteCapabilitiesProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(siteCapabilitiesProvider.future);

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationFailed<Account>).code, 'FORBIDDEN');
      expect(result.message, githubVerifyExpiredText);
      await container.read(siteCapabilitiesProvider.future);
      expect(api.getSiteCalls, 1);
    });

    test('INVALID_ARGUMENT tells both rules', () async {
      await open();
      await asGithubAccount();
      api.registerError = const ApiException(
        code: 'INVALID_ARGUMENT',
        message: '服务端',
        status: 400,
      );

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );

      expect(
        (result as MutationFailed<Account>).message,
        '用户名要 3–32 位小写字母、数字、_ 或 -，密码要 8–128 位。',
      );
    });

    test('CONFLICT carries the server message and re-reads the '
        'profile', () async {
      await open();
      await asGithubAccount();
      api.registerError = const ApiException(
        code: 'CONFLICT',
        message: '用户名已被占用',
        status: 409,
      );
      final before = api.getMeCalls;

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );
      await pumpEventQueue();

      expect((result as MutationFailed<Account>).message, '用户名已被占用');
      expect(api.getMeCalls, greaterThan(before));
    });

    test('UNAUTHORIZED signs the account out', () async {
      await open();
      await asGithubAccount();
      api.registerError = unauthorized;

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationFailed<Account>).message, signedOutNotice);
      expect(credentials.memberToken, 'new-member-token');
    });

    test('a lost answer is unknown and re-reads the profile', () async {
      await open();
      await asGithubAccount();
      api.registerError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );
      final before = api.getMeCalls;

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<Account>>());
      expect(api.getMeCalls, greaterThan(before));
    });

    test('without a known member nothing is sent', () async {
      await open();

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationNotSent<Account>).message, signedOutNotice);
      expect(api.getMeCalls, 0);
      expect(api.registerCalls, 0);
    });

    test('an account replaced by a new guest on the way registers '
        'nobody', () async {
      await open();
      await asGithubAccount();
      api.getMeError = unauthorized;

      final result = await account.setCredentials(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationNotSent<Account>).message, signedOutNotice);
      expect(api.registerCalls, 0);
      expect(credentials.memberToken, 'new-member-token');
    });

    test('a server switched while a new member is made registers '
        'nobody', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      await asGithubAccount();
      api
        ..getMeError = unauthorized
        ..createMemberGate = Completer<void>();
      final setting = account.setCredentials(
        username: 'mao',
        password: 'password1',
      );
      await pumpEventQueue();

      await switchToB();
      api.createMemberGate!.complete();
      final result = await setting;

      expect((result as MutationNotSent<Account>).message, serverChangedNotice);
      expect(api.registerCalls, 0);
      expect(other.memberToken, isNull);
    });

    test('credentials set on the old server after a switch are told so and '
        'move no email', () async {
      final other = FakeCredentialStore()..memberToken = 'b-token';
      await open({
        'alisten.email': 'guest@example.com',
      }, (id) => id == serverB.id ? other : credentials);
      await asGithubAccount();
      api.registerGate = Completer<void>();
      final setting = account.setCredentials(
        username: 'mao',
        password: 'password1',
      );
      await pumpEventQueue();

      await switchToB();
      api.registerGate!.complete();
      final result = await setting;
      await pumpEventQueue();

      expect((result as MutationNotSent<Account>).message, doneOnOldServerText);
      expect(api.registerCalls, 1);
      expect(api.updateMeCalls, 0);
      expect(
        container.read(settingsControllerProvider).value.email,
        'guest@example.com',
      );
    });
  });

  group('failure mapping', () {
    test('login CONFLICT is told and refreshes the profile', () async {
      await open();
      api.loginError = const ApiException(
        code: 'CONFLICT',
        message: '服务端',
        status: 409,
      );
      final before = api.getMeCalls;

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );
      await pumpEventQueue();

      expect((result as MutationFailed<Account>).message, '已经登录了账号');
      expect(api.getMeCalls, greaterThan(before));
    });

    test('login with a lost answer is unknown', () async {
      await open();
      api.loginError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationUnknown<Account>>());
    });

    test(
      'register CONFLICT carries the server message and refreshes',
      () async {
        await open();
        api.registerError = const ApiException(
          code: 'CONFLICT',
          message: '用户名已被占用',
          status: 409,
        );
        final before = api.getMeCalls;

        final result = await account.register(
          username: 'mao',
          password: 'password1',
        );
        await pumpEventQueue();

        expect((result as MutationFailed<Account>).message, '用户名已被占用');
        expect(api.getMeCalls, greaterThan(before));
      },
    );

    test('register rate limiting says when to try again', () async {
      await open();
      api.registerError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: Duration(seconds: 10),
      );

      final result = await account.register(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationNotSent<Account>).message, '请求太频繁，请 10 秒后再试');
    });

    test('register does not throw when the member cannot be read', () async {
      await open();
      credentials
        ..memberToken = null
        ..readMemberTokenError = Exception('keystore');

      final result = await account.register(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationNotSent<Account>>());
    });

    test('logout answered UNAUTHORIZED still signs out', () async {
      await open();
      await account.login(username: 'mao', password: 'password1');
      api.logoutError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '服务端',
        status: 401,
      );

      final result = await account.logout();

      expect(result, isA<MutationSucceeded<void>>());
      expect(identity().account, isNull);
    });

    test(
      'changePassword UNAUTHORIZED tells a registered user signed out',
      () async {
        await open();
        await account.login(username: 'mao', password: 'password1');
        api.changePasswordError = const ApiException(
          code: 'UNAUTHORIZED',
          message: '服务端',
          status: 401,
        );

        final result = await account.changePassword(
          current: 'password1',
          next: 'password2',
        );

        expect((result as MutationFailed<void>).message, signedOutNotice);
      },
    );

    test('changePassword UNAUTHORIZED after a server switch leaves the new '
        "server's identity alone", () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      final gate = Completer<void>();
      api
        ..changePasswordGate = gate
        ..changePasswordError = unauthorized;

      final pending = account.changePassword(
        current: 'password1',
        next: 'password2',
      );
      await pumpEventQueue();
      final servers = container.read(serverDirectoryProvider.notifier);
      await servers.add(serverB);
      await servers.setCurrent(serverB.id);
      gate.complete();
      final result = await pending;

      expect((result as MutationFailed<void>).message, '服务器已经切换，这次操作没有完成。');
      expect(api.createMemberCalls, 0);
      expect(other.memberToken, isNull);
      expect(other.deleteMemberCalls, 0);
    });

    test(
      'changePassword UNAUTHORIZED tells a guest the identity renewed',
      () async {
        await open();
        api.changePasswordError = const ApiException(
          code: 'UNAUTHORIZED',
          message: '服务端',
          status: 401,
        );

        final result = await account.changePassword(
          current: 'password1',
          next: 'password2',
        );

        expect((result as MutationFailed<void>).message, identityRenewedNotice);
      },
    );

    test('register UNAUTHORIZED gives a guest a new identity and asks to '
        'confirm again', () async {
      await open();
      api.registerError = unauthorized;

      final result = await account.register(
        username: 'mao',
        password: 'password1',
      );

      expect(
        (result as MutationFailed<Account>).message,
        identityRenewedNotice,
      );
      expect(credentials.memberToken, 'new-member-token');
    });
  });

  test('unreadable capabilities fall back to the server deciding', () async {
    await open();
    api.getSiteError = const ApiException(
      code: LocalErrorCodes.network,
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );

    final site = await container.read(siteCapabilitiesProvider.future);

    expect(site.registrationOpen, SiteCapabilities.unknown.registrationOpen);
  });
}
