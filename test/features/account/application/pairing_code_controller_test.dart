import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/features/account/application/pairing_code_controller.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';

const _startMs = 1700000000000;

void main() {
  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late ProviderContainer container;

  PairingCodeController controller() =>
      container.read(pairingCodeControllerProvider.notifier);
  PairingCodeState state() => container.read(pairingCodeControllerProvider);

  // 时钟随假时间前进，起点是 [_startMs]。
  void open(FakeAsync async) {
    api = FakeAlistenApi()
      ..me = accountMember
      ..account = const Account(username: 'mao', github: false)
      ..pairingCode = const PairingCode(
        code: 'ABCD2345',
        expiresAtMs: _startMs + 300000,
      );
    credentials = FakeCredentialStore()..memberToken = 'account-token';
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(api),
        credentialStoreProvider.overrideWithValue(credentials),
        clearLocalEmailProvider.overrideWithValue(() async {}),
        pairingNowProvider.overrideWithValue(
          () => _startMs + async.elapsed.inMilliseconds,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(pairingCodeControllerProvider, (_, _) {});
    unawaited(container.read(identityControllerProvider.notifier).restore());
    async.flushMicrotasks();
  }

  String? generate(FakeAsync async) {
    String? reason;
    unawaited(controller().generate().then((value) => reason = value));
    async.flushMicrotasks();
    return reason;
  }

  test('a code counts down each second by the clock it is given', () {
    fakeAsync((async) {
      open(async);

      expect(generate(async), isNull);

      final ready = state() as PairingCodeReady;
      expect(ready.code.code, 'ABCD2345');
      expect(ready.secondsLeft, 300);
      async.elapse(const Duration(seconds: 1));
      expect((state() as PairingCodeReady).secondsLeft, 299);
    });
  });

  test('a code runs out and the countdown stops', () {
    fakeAsync((async) {
      open(async);
      generate(async);

      async.elapse(const Duration(seconds: 300));

      expect(state(), isA<PairingCodeExpired>());
      expect(async.periodicTimerCount, 0);
    });
  });

  test('generating again drops the answer of the earlier attempt', () {
    fakeAsync((async) {
      open(async);
      final answers = [Completer<PairingCode>(), Completer<PairingCode>()];
      var calls = 0;
      api.createPairingCodeHandler = () => answers[calls++].future;

      generate(async);
      generate(async);
      answers[1].complete(
        const PairingCode(code: 'WXYZ6789', expiresAtMs: _startMs + 300000),
      );
      async.flushMicrotasks();
      answers[0].complete(
        const PairingCode(code: 'ABCD2345', expiresAtMs: _startMs + 300000),
      );
      async.flushMicrotasks();

      expect((state() as PairingCodeReady).code.code, 'WXYZ6789');
      expect(async.periodicTimerCount, 1);
    });
  });

  test('an older attempt that fails after a newer code keeps the code', () {
    fakeAsync((async) {
      open(async);
      final answers = [Completer<PairingCode>(), Completer<PairingCode>()];
      var calls = 0;
      api.createPairingCodeHandler = () => answers[calls++].future;

      String? stale = '';
      unawaited(controller().generate().then((value) => stale = value));
      async.flushMicrotasks();
      generate(async);
      answers[1].complete(
        const PairingCode(code: 'WXYZ6789', expiresAtMs: _startMs + 300000),
      );
      async.flushMicrotasks();
      answers[0].completeError(
        const ApiException(
          code: LocalErrorCodes.network,
          message: '网络请求失败，请检查网络后重试。',
          status: null,
        ),
      );
      async.flushMicrotasks();

      expect(stale, isNull);
      expect((state() as PairingCodeReady).code.code, 'WXYZ6789');
      expect(async.periodicTimerCount, 1);
    });
  });

  test('an answer after the panel closed sets nothing and starts no '
      'countdown', () {
    fakeAsync((async) {
      open(async);
      final answer = Completer<PairingCode>();
      api.createPairingCodeHandler = () => answer.future;
      String? reason = '';
      unawaited(controller().generate().then((value) => reason = value));
      async.flushMicrotasks();

      container.dispose();
      answer.complete(
        const PairingCode(code: 'ABCD2345', expiresAtMs: _startMs + 300000),
      );
      async.flushMicrotasks();

      expect(reason, isNull);
      expect(async.periodicTimerCount, 0);
    });
  });

  test('closing the panel stops the countdown', () {
    fakeAsync((async) {
      open(async);
      generate(async);
      expect(async.periodicTimerCount, 1);

      container.dispose();

      expect(async.periodicTimerCount, 0);
    });
  });

  test('a code that cannot be made shows the failure and the reason', () {
    fakeAsync((async) {
      open(async);
      api.createPairingCodeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      expect(generate(async), '网络请求失败，请检查网络后重试。');
      expect(state(), isA<PairingCodeFailed>());
    });
  });

  test('rate limiting says when to try again', () {
    fakeAsync((async) {
      open(async);
      api.createPairingCodeError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: Duration(seconds: 20),
      );

      expect(generate(async), '请求太频繁，请 20 秒后再试');
    });
  });

  test('FORBIDDEN shows the server message and re-reads the identity', () {
    fakeAsync((async) {
      open(async);
      api.createPairingCodeError = const ApiException(
        code: 'FORBIDDEN',
        message: '只有账号能生成配对码',
        status: 403,
      );
      final before = api.getMeCalls;

      expect(generate(async), '只有账号能生成配对码');
      expect(api.getMeCalls, before + 1);
    });
  });

  test('a refused account is signed out with the token read before '
      'sending', () {
    fakeAsync((async) {
      open(async);
      api.createPairingCodeError = unauthorized;

      expect(generate(async), signedOutNotice);
      expect(credentials.memberToken, 'new-member-token');
    });
  });
}
