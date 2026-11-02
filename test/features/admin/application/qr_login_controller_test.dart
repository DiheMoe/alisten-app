import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_test_doubles.dart';

const _startMs = 1700000000000;

QrLoginTicket _ticket({
  String key = 'k-1',
  String qrImage = 'data:image/png;base64,iVBORw0KGgo=',
  int expiresAtMs = _startMs + 120000,
}) {
  return QrLoginTicket(key: key, qrImage: qrImage, expiresAtMs: expiresAtMs);
}

void main() {
  late FakeAdminApi api;
  late FakeQrImageLoader images;
  late FakeImageGallery gallery;
  late ProviderContainer container;
  late ProviderSubscription<QrLoginState> subscription;

  // 时钟随假时间前进，起点为 [_startMs] 加上设备时钟领先服务端的 [clockAhead]。
  void open(
    FakeAsync async, {
    LoginSource source = LoginSource.netease,
    Duration clockAhead = Duration.zero,
  }) {
    api = FakeAdminApi();
    images = FakeQrImageLoader();
    gallery = FakeImageGallery();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(baseUrl: 'https://livehouse.dihe.moe', isRelease: false),
        ),
        adminApiProvider.overrideWithValue(api),
        qrImageLoaderProvider.overrideWithValue(images),
        imageGalleryProvider.overrideWithValue(gallery),
        adminNowProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(
            _startMs + clockAhead.inMilliseconds + async.elapsed.inMilliseconds,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    subscription = container.listen(
      qrLoginControllerProvider(source),
      (_, _) {},
    );
    unawaited(container.read(adminSessionProvider.notifier).signIn('t-1'));
    async.flushMicrotasks();
  }

  QrLoginController controller([LoginSource source = LoginSource.netease]) =>
      container.read(qrLoginControllerProvider(source).notifier);
  QrLoginState state([LoginSource source = LoginSource.netease]) =>
      container.read(qrLoginControllerProvider(source));

  void start(
    FakeAsync async, {
    LoginSource source = LoginSource.netease,
    QqLoginType? qqType,
  }) {
    unawaited(controller(source).start(qqType: qqType));
    async.flushMicrotasks();
  }

  test('a code shows the seconds it has left, counted each second, and is '
      'checked 2 seconds after it is shown and after each answer', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.add(
        const FakeQrCheck(
          QrCheckState.waiting,
          delay: Duration(milliseconds: 500),
        ),
      );

      start(async);

      expect(state().phase, QrPhase.waiting);
      expect(state().statusText, '等待扫码');
      expect(state().remainingSeconds, 120);
      expect(state().expiresAtMs, _startMs + 120000);
      expect(state().image, images.bytes);
      expect(images.loaded, ['data:image/png;base64,iVBORw0KGgo=']);

      async.elapse(const Duration(seconds: 1));
      expect(state().remainingSeconds, 119);
      expect(api.checkCalls, 0);

      async.elapse(const Duration(milliseconds: 999));
      expect(api.checkCalls, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(api.checkCalls, 1);
      expect(api.checkedKeys, ['k-1']);

      // 回复在 2.5 秒到达，下一次查询在其后 2 秒。
      async.elapse(const Duration(milliseconds: 2499));
      expect(api.checkCalls, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(api.checkCalls, 2);
      expect(state().phase, QrPhase.waiting);
    });
  });

  test('a scanned code asks to confirm on the phone, and a sign-in taken '
      'stops checking', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.addAll(const [
        FakeQrCheck(QrCheckState.scanned),
        FakeQrCheck(QrCheckState.success),
      ]);

      start(async);
      async.elapse(const Duration(seconds: 2));
      expect(state().phase, QrPhase.scanned);
      expect(state().statusText, '已扫码，请在手机上确认');

      async.elapse(const Duration(seconds: 2));
      expect(state().phase, QrPhase.success);
      expect(state().statusText, '登录成功');

      final calls = api.checkCalls;
      async.elapse(const Duration(seconds: 10));
      expect(api.checkCalls, calls);
    });
  });

  test('the countdown stops at 0 without running the code out, and a '
      'sign-in answered after that still counts', () {
    fakeAsync((async) {
      open(async);
      api
        ..qrTicket = _ticket(expiresAtMs: _startMs + 3000)
        ..checkResults.add(
          const FakeQrCheck(
            QrCheckState.success,
            delay: Duration(milliseconds: 1500),
          ),
        );

      start(async);
      expect(state().remainingSeconds, 3);

      async.elapse(const Duration(seconds: 3));
      expect(state().phase, QrPhase.waiting);
      expect(state().statusText, '等待扫码');
      expect(state().remainingSeconds, 0);

      async.elapse(const Duration(milliseconds: 500));
      expect(state().phase, QrPhase.success);
      expect(api.checkCalls, 1);
    });
  });

  test('a code past its countdown is checked until the server says it ran '
      'out, the countdown staying at 0', () {
    fakeAsync((async) {
      open(async);
      api.qrTicket = _ticket(expiresAtMs: _startMs + 3000);

      start(async);
      async.elapse(const Duration(seconds: 20));
      expect(state().phase, QrPhase.waiting);
      expect(state().remainingSeconds, 0);
      expect(api.checkCalls, 10);

      api.checkResults.add(const FakeQrCheck(QrCheckState.expired));
      async.elapse(const Duration(seconds: 2));
      expect(state().phase, QrPhase.expired);
      expect(state().statusText, '二维码已过期');

      async.elapse(const Duration(seconds: 10));
      expect(api.checkCalls, 11);
    });
  });

  test('the server saying the code ran out or the sign-in failed stops '
      'checking', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.add(const FakeQrCheck(QrCheckState.expired));

      start(async);
      async.elapse(const Duration(seconds: 2));
      expect(state().phase, QrPhase.expired);

      api.checkResults.add(
        const FakeQrCheck(QrCheckState.failed, message: '账号存在风险'),
      );
      start(async);
      async.elapse(const Duration(seconds: 2));
      expect(state().phase, QrPhase.failed);
      expect(state().statusText, '登录失败：账号存在风险');

      final calls = api.checkCalls;
      async.elapse(const Duration(seconds: 10));
      expect(api.checkCalls, calls);
    });
  });

  test('a check the server refuses fails the sign-in with its reason and '
      'stops checking', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.add(
        const FakeQrCheck.error(
          ApiException(code: 'PROVIDER_ERROR', message: '网易云出错了', status: 502),
        ),
      );

      start(async);
      async.elapse(const Duration(seconds: 2));
      expect(state().phase, QrPhase.failed);
      expect(state().statusText, '登录失败：网易云出错了');

      async.elapse(const Duration(seconds: 10));
      expect(api.checkCalls, 1);
    });
  });

  test('the answer to a check of a replaced code is not used', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.add(
        const FakeQrCheck(
          QrCheckState.failed,
          message: '账号存在风险',
          delay: Duration(seconds: 1),
        ),
      );

      start(async);
      async.elapse(const Duration(seconds: 2));
      api.qrTicket = _ticket(key: 'k-2');
      start(async);
      async.elapse(const Duration(seconds: 1));

      expect(state().phase, QrPhase.waiting);
    });
  });

  test('away from the foreground nothing is checked or counted; back, the '
      'code is checked at once with the seconds really left', () {
    fakeAsync((async) {
      open(async);
      start(async);

      async.elapse(const Duration(seconds: 1));
      controller().pause();
      async.elapse(const Duration(seconds: 60, milliseconds: 500));
      expect(api.checkCalls, 0);
      expect(state().remainingSeconds, 119);

      // 还剩 58.5 秒，不足一秒的部分算一秒。
      controller().resume();
      async.flushMicrotasks();
      expect(api.checkCalls, 1);
      expect(state().remainingSeconds, 59);

      async.elapse(const Duration(milliseconds: 1999));
      expect(api.checkCalls, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(api.checkCalls, 2);

      async.elapse(const Duration(seconds: 1));
      expect(state().remainingSeconds, 56);
    });
  });

  test('a check answered while away is applied without sending the next; '
      'back, the code is checked at once', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.add(
        const FakeQrCheck(QrCheckState.scanned, delay: Duration(seconds: 1)),
      );

      start(async);
      async.elapse(const Duration(seconds: 2));
      controller().pause();
      async.elapse(const Duration(seconds: 1));
      expect(state().phase, QrPhase.scanned);

      async.elapse(const Duration(seconds: 10));
      expect(api.checkCalls, 1);

      controller().resume();
      async.flushMicrotasks();
      expect(api.checkCalls, 2);
    });
  });

  test('coming back while a check is still out does not send another; the '
      'next follows 2 seconds after its answer', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.add(
        const FakeQrCheck(QrCheckState.waiting, delay: Duration(seconds: 3)),
      );

      start(async);
      async.elapse(const Duration(seconds: 2));
      controller().pause();
      async.elapse(const Duration(seconds: 1));
      controller().resume();
      async.flushMicrotasks();
      expect(api.checkCalls, 1);

      // 回复在 5 秒到达。
      async.elapse(const Duration(milliseconds: 3999));
      expect(api.checkCalls, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(api.checkCalls, 2);
    });
  });

  test('back after the countdown ran out while away, the code is still '
      'checked at once and the server decides whether it ran out', () {
    fakeAsync((async) {
      open(async);
      start(async);

      controller().pause();
      async.elapse(const Duration(minutes: 3));
      controller().resume();
      async.flushMicrotasks();

      expect(state().phase, QrPhase.waiting);
      expect(state().remainingSeconds, 0);
      expect(api.checkCalls, 1);
    });
  });

  test('QQ music is signed in through WeChat when asked, and checked the '
      'same way', () {
    fakeAsync((async) {
      open(async, source: LoginSource.qq);

      start(async, source: LoginSource.qq, qqType: QqLoginType.wx);
      expect(api.startedSources, [LoginSource.qq]);
      expect(api.startedQqTypes, [QqLoginType.wx]);
      expect(state(LoginSource.qq).qqType, QqLoginType.wx);

      async.elapse(const Duration(seconds: 2));
      expect(api.checkedQqTypes.first, QqLoginType.wx);

      // 重新获取沿用当前的扫码方式。
      start(async, source: LoginSource.qq);
      expect(api.startedQqTypes, [QqLoginType.wx, QqLoginType.wx]);
    });
  });

  test('a check answered with an expired admin token ends the session and '
      'checking', () {
    fakeAsync((async) {
      open(async);
      api.checkResults.add(
        const FakeQrCheck.error(
          ApiException(code: 'UNAUTHORIZED', message: 'token', status: 401),
        ),
      );

      start(async);
      async.elapse(const Duration(seconds: 2));
      expect(container.read(adminSessionProvider).active, isFalse);

      async.elapse(const Duration(seconds: 10));
      expect(api.checkCalls, 1);
    });
  });

  test('a code whose image cannot be loaded fails the sign-in and is never '
      'checked', () {
    fakeAsync((async) {
      open(async);
      images.error = const QrImageUnavailable();

      start(async);
      expect(state().phase, QrPhase.failed);
      expect(state().statusText, '登录失败：二维码加载失败，请重新获取');
      expect(state().image, isNull);

      async.elapse(const Duration(seconds: 10));
      expect(api.checkCalls, 0);
    });
  });

  test('a code the server will not make fails the sign-in with its '
      'reason', () {
    fakeAsync((async) {
      open(async);
      api.startQrError = const ApiException(
        code: 'PROVIDER_ERROR',
        message: '暂时无法获取二维码',
        status: 502,
      );

      start(async);

      expect(state().phase, QrPhase.failed);
      expect(state().statusText, '登录失败：暂时无法获取二维码');
      expect(images.loaded, isEmpty);
    });
  });

  test('a code asked for while another is on its way replaces it', () {
    fakeAsync((async) {
      open(async);
      images.images['qr-1'] = Uint8List.fromList(const [1]);
      images.images['qr-2'] = Uint8List.fromList(const [2]);
      final gate = Completer<void>();
      api
        ..qrTicket = _ticket(qrImage: 'qr-1')
        ..startQrGate = gate;
      start(async);
      expect(state().phase, QrPhase.starting);
      expect(state().statusText, '正在获取二维码');

      api
        ..startQrGate = null
        ..qrTicket = _ticket(key: 'k-2', qrImage: 'qr-2');
      start(async);
      expect(state().image, [2]);

      gate.complete();
      async.flushMicrotasks();
      expect(state().image, [2]);
      expect(images.loaded, ['qr-2']);

      async.elapse(const Duration(seconds: 2));
      expect(api.checkedKeys, ['k-2']);
    });
  });

  test('a new code stops the checks of the one it replaces', () {
    fakeAsync((async) {
      open(async);
      start(async);
      async.elapse(const Duration(seconds: 1));

      api.qrTicket = _ticket(key: 'k-2');
      start(async);
      async.elapse(const Duration(seconds: 2));

      expect(api.checkedKeys, ['k-2']);
    });
  });

  test('nothing is asked for once the session has ended', () {
    fakeAsync((async) {
      open(async);
      container.read(adminSessionProvider.notifier).end();

      start(async);

      expect(state().phase, QrPhase.starting);
      expect(api.startedSources, isEmpty);
    });
  });

  test('no longer watched, the code is not checked again', () {
    fakeAsync((async) {
      open(async);
      start(async);

      subscription.close();
      async.elapse(const Duration(seconds: 10));

      expect(api.checkCalls, 0);
      expect(async.periodicTimerCount, 0);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('an unexpected failure fails the sign-in and only its type is '
      'logged', () {
    fakeAsync((async) {
      final records = <String>[];
      AppLog.onRecord = (name, level, message) => records.add(message);
      addTearDown(() => AppLog.onRecord = null);
      open(async);
      api
        ..qrTicket = _ticket(key: 'k-secret')
        ..checkResults.add(FakeQrCheck.error(StateError('k-secret')));

      start(async);
      async.elapse(const Duration(seconds: 2));

      expect(state().phase, QrPhase.failed);
      expect(state().statusText, '登录失败');
      expect(records, isNotEmpty);
      expect(records.where((record) => record.contains('k-secret')), isEmpty);
    });
  });

  group('a check whose answer was lost', () {
    test('keeps the code waiting and checks again 2 seconds later, and a '
        'sign-in then counts', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.addAll(const [
          FakeQrCheck.error(
            ApiException(
              code: 'NETWORK',
              message: '网络请求失败，请检查网络后重试。',
              status: null,
            ),
          ),
          FakeQrCheck(QrCheckState.success),
        ]);

        start(async);
        async.elapse(const Duration(seconds: 2));
        expect(api.checkCalls, 1);
        expect(state().phase, QrPhase.waiting);
        expect(state().statusText, '等待扫码');

        async.elapse(const Duration(milliseconds: 1999));
        expect(api.checkCalls, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(api.checkCalls, 2);
        expect(state().phase, QrPhase.success);
      });
    });

    test('by running out of time is lost too: the code keeps waiting and is '
        'checked again', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.addAll(const [
          FakeQrCheck.error(
            ApiException(
              code: 'NETWORK',
              message: '请求超时，请检查网络后重试。',
              status: null,
            ),
          ),
          FakeQrCheck(QrCheckState.success),
        ]);

        start(async);
        async.elapse(const Duration(seconds: 2));
        expect(state().phase, QrPhase.waiting);
        expect(controller().holdsKey, isTrue);

        async.elapse(const Duration(seconds: 2));
        expect(api.checkCalls, 2);
        expect(state().phase, QrPhase.success);
      });
    });

    test('back in the foreground keeps the code waiting', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(
          const FakeQrCheck.error(
            ApiException(
              code: 'NETWORK',
              message: '网络请求失败，请检查网络后重试。',
              status: null,
            ),
          ),
        );

        start(async);
        controller().pause();
        async.elapse(const Duration(seconds: 30));
        controller().resume();
        async.flushMicrotasks();
        expect(api.checkCalls, 1);
        expect(state().phase, QrPhase.waiting);

        async.elapse(const Duration(seconds: 2));
        expect(api.checkCalls, 2);
      });
    });

    // 收到回复却无法解码说明协议不兼容，重试无效，必须明确提示升级。
    test('is only one that never arrived: an answer this version cannot read '
        'fails the sign-in with the upgrade notice and stops checking', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(
          const FakeQrCheck.error(ApiException.protocolMismatch(200)),
        );

        start(async);
        async.elapse(const Duration(seconds: 2));
        expect(state().phase, QrPhase.failed);
        expect(state().statusText, '登录失败：服务器返回了无法识别的数据，请升级 Alisten。');
        expect(controller().holdsKey, isFalse);

        async.elapse(const Duration(seconds: 10));
        expect(api.checkCalls, 1);
      });
    });

    test('keeps being checked past the countdown until the server says the '
        'code ran out', () {
      fakeAsync((async) {
        open(async);
        api.qrTicket = _ticket(expiresAtMs: _startMs + 5000);
        for (var i = 0; i < 10; i++) {
          api.checkResults.add(
            const FakeQrCheck.error(
              ApiException(code: 'NETWORK', message: '网络不通', status: null),
            ),
          );
        }
        api.checkResults.add(const FakeQrCheck(QrCheckState.expired));

        start(async);
        async.elapse(const Duration(seconds: 20));
        expect(state().phase, QrPhase.waiting);
        expect(state().remainingSeconds, 0);
        expect(api.checkCalls, 10);

        async.elapse(const Duration(seconds: 2));
        expect(state().phase, QrPhase.expired);
        async.elapse(const Duration(seconds: 10));
        expect(api.checkCalls, 11);
      });
    });
  });

  group('a check turned away for coming too often', () {
    FakeQrCheck limited([Duration? retryAfter]) => FakeQrCheck.error(
      ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: retryAfter,
      ),
    );

    // 第 [calls] 次查询恰好在开始之后 [at] 发出。
    void checkedAt(FakeAsync async, Duration at, int calls) {
      async.elapse(at - async.elapsed - const Duration(milliseconds: 1));
      expect(api.checkCalls, calls - 1, reason: '$at');
      async.elapse(const Duration(milliseconds: 1));
      expect(api.checkCalls, calls, reason: '$at');
    }

    test('keeps the code waiting and checks again after the wait the server '
        'gives', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.addAll([
          limited(const Duration(seconds: 10)),
          const FakeQrCheck(QrCheckState.success),
        ]);

        start(async);
        checkedAt(async, const Duration(seconds: 2), 1);
        expect(state().phase, QrPhase.waiting);
        expect(state().statusText, '等待扫码');
        expect(controller().holdsKey, isTrue);

        checkedAt(async, const Duration(seconds: 12), 2);
        expect(state().phase, QrPhase.success);
      });
    });

    test('with no wait given backs off from 4 seconds, doubling up to 30, '
        'and back to every 2 seconds once a check is answered', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.addAll([
          limited(),
          limited(),
          limited(),
          limited(),
          limited(),
          const FakeQrCheck(QrCheckState.waiting),
          limited(),
          const FakeQrCheck(QrCheckState.success),
        ]);

        start(async);
        checkedAt(async, const Duration(seconds: 2), 1);
        checkedAt(async, const Duration(seconds: 6), 2);
        checkedAt(async, const Duration(seconds: 14), 3);
        checkedAt(async, const Duration(seconds: 30), 4);
        checkedAt(async, const Duration(seconds: 60), 5);
        checkedAt(async, const Duration(seconds: 90), 6);
        checkedAt(async, const Duration(seconds: 92), 7);
        checkedAt(async, const Duration(seconds: 96), 8);
        expect(state().phase, QrPhase.success);
      });
    });

    test('waits no longer than 30 seconds and no less than 2', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.addAll([
          limited(const Duration(minutes: 2)),
          limited(Duration.zero),
          const FakeQrCheck(QrCheckState.success),
        ]);

        start(async);
        checkedAt(async, const Duration(seconds: 2), 1);
        checkedAt(async, const Duration(seconds: 32), 2);
        checkedAt(async, const Duration(seconds: 34), 3);
        expect(state().phase, QrPhase.success);
      });
    });
  });

  group('a device clock ahead of the server', () {
    test('by more than the life of the code shows no seconds left and does '
        'not run the code out here; the server says when it has', () {
      fakeAsync((async) {
        open(async, clockAhead: const Duration(minutes: 3));

        start(async);
        expect(state().phase, QrPhase.waiting);
        expect(state().remainingSeconds, 0);
        expect(state().statusText, '等待扫码');

        async.elapse(const Duration(seconds: 10));
        expect(state().phase, QrPhase.waiting);
        expect(api.checkCalls, 5);

        api.checkResults.add(const FakeQrCheck(QrCheckState.expired));
        async.elapse(const Duration(seconds: 2));
        expect(state().phase, QrPhase.expired);

        final calls = api.checkCalls;
        async.elapse(const Duration(seconds: 10));
        expect(api.checkCalls, calls);
      });
    });

    test('back from the background, still leaves running out to the '
        'server', () {
      fakeAsync((async) {
        open(async, clockAhead: const Duration(minutes: 3));
        start(async);

        controller().pause();
        async.elapse(const Duration(seconds: 30));
        controller().resume();
        async.flushMicrotasks();

        expect(state().phase, QrPhase.waiting);
        expect(api.checkCalls, 1);
      });
    });

    test('by 100 seconds keeps the code scannable and checked for as long '
        'as the server holds it, the countdown stopping at 0', () {
      fakeAsync((async) {
        open(async, clockAhead: const Duration(seconds: 100));

        start(async);
        expect(state().remainingSeconds, 20);

        async.elapse(const Duration(seconds: 20));
        expect(state().remainingSeconds, 0);
        expect(state().phase, QrPhase.waiting);

        // 服务端的有效期是 120 秒，在此之前一直可扫码、一直在查询。
        async.elapse(const Duration(seconds: 98));
        expect(state().phase, QrPhase.waiting);
        expect(state().remainingSeconds, 0);
        expect(api.checkCalls, 59);

        api.checkResults.add(const FakeQrCheck(QrCheckState.expired));
        async.elapse(const Duration(seconds: 2));
        expect(state().phase, QrPhase.expired);
      });
    });
  });

  group('the code key', () {
    test('is let go once the sign-in is taken', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(const FakeQrCheck(QrCheckState.success));

        start(async);
        expect(controller().holdsKey, isTrue);
        async.elapse(const Duration(seconds: 2));

        expect(state().phase, QrPhase.success);
        expect(controller().holdsKey, isFalse);
      });
    });

    test('is let go once the sign-in fails', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(const FakeQrCheck(QrCheckState.failed));

        start(async);
        async.elapse(const Duration(seconds: 2));

        expect(controller().holdsKey, isFalse);
      });
    });

    test('is let go once the server says the code ran out', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(const FakeQrCheck(QrCheckState.expired));

        start(async);
        async.elapse(const Duration(seconds: 2));

        expect(controller().holdsKey, isFalse);
      });
    });

    test('is kept while the countdown is at 0 and the code is still '
        'checked', () {
      fakeAsync((async) {
        open(async);
        api.qrTicket = _ticket(expiresAtMs: _startMs + 3000);

        start(async);
        async.elapse(const Duration(seconds: 5));

        expect(state().remainingSeconds, 0);
        expect(controller().holdsKey, isTrue);
      });
    });

    test('is let go when the session ends', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(
          const FakeQrCheck.error(
            ApiException(code: 'UNAUTHORIZED', message: 'token', status: 401),
          ),
        );

        start(async);
        async.elapse(const Duration(seconds: 2));

        expect(controller().holdsKey, isFalse);
      });
    });

    test('is let go when the controller is gone', () {
      fakeAsync((async) {
        open(async);
        start(async);
        final login = controller();
        expect(login.holdsKey, isTrue);

        subscription.close();
        async.elapse(const Duration(seconds: 1));

        expect(login.holdsKey, isFalse);
      });
    });

    test('is kept while a lost answer is checked again', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(
          const FakeQrCheck.error(
            ApiException(code: 'NETWORK', message: '网络不通', status: null),
          ),
        );

        start(async);
        async.elapse(const Duration(seconds: 2));

        expect(controller().holdsKey, isTrue);
      });
    });
  });

  group('saving the code', () {
    QrSaveResult? save(FakeAsync async) {
      QrSaveResult? result;
      unawaited(controller().saveImage().then((saved) => result = saved));
      async.flushMicrotasks();
      return result;
    }

    test('puts the code shown into the gallery under the name of its '
        'source', () {
      fakeAsync((async) {
        open(async, source: LoginSource.qq);
        unawaited(controller(LoginSource.qq).start());
        async.flushMicrotasks();
        QrSaveResult? result;
        unawaited(
          controller(LoginSource.qq)
              .saveImage()
              .then((saved) => result = saved),
        );
        async.flushMicrotasks();

        expect(result, QrSaveResult.saved);
        expect(gallery.saved.single.name, 'alisten-qq-login');
        expect(gallery.saved.single.bytes, images.bytes);
      });
    });

    test('tells a refused access apart from another failure', () {
      fakeAsync((async) {
        open(async);
        start(async);

        gallery.deny = true;
        expect(save(async), QrSaveResult.denied);

        gallery
          ..deny = false
          ..error = StateError('disk full');
        expect(save(async), QrSaveResult.failed);
        expect(gallery.saved, isEmpty);
      });
    });

    test('leaves a code that can no longer be scanned out of the '
        'gallery', () {
      fakeAsync((async) {
        open(async);
        api.checkResults.add(const FakeQrCheck(QrCheckState.expired));
        start(async);
        async.elapse(qrPollInterval);
        expect(state().phase, QrPhase.expired);

        expect(save(async), QrSaveResult.failed);
        expect(gallery.saved, isEmpty);
      });
    });
  });
}
