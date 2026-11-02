import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart' show roomListing;
import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _unauthorized = ApiException(
  code: 'UNAUTHORIZED',
  message: 'token invalid',
  status: 401,
);
const _forbidden = ApiException(
  code: 'FORBIDDEN',
  message: '后台未启用',
  status: 403,
);

Matcher _ended({required bool resultUnknown}) => isA<AdminSessionEnded>()
    .having((e) => e.resultUnknown, 'resultUnknown', resultUnknown);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdminApi api;
  late DateTime now;
  late Duration elapsed;
  late List<_FakeTimer> timers;
  late ProviderContainer container;

  AdminSession session() => container.read(adminSessionProvider.notifier);
  AdminSessionState state() => container.read(adminSessionProvider);
  Future<List<RoomListing>> listRooms() =>
      session().run((api, token) => api.listRooms(token));

  setUp(() async {
    api = FakeAdminApi()..rooms = [roomListing(id: 'room-1')];
    now = DateTime.utc(2026, 11, 2, 20);
    elapsed = Duration.zero;
    timers = [];
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [
        adminApiProvider.overrideWithValue(api),
        adminNowProvider.overrideWithValue(() => now),
        adminElapsedProvider.overrideWithValue(() => elapsed),
        adminTimerProvider.overrideWithValue((duration, callback) {
          final timer = _FakeTimer(elapsed + duration, callback);
          timers.add(timer);
          return timer;
        }),
      ],
    );
  });

  // 墙上时钟走 [wall]，单调时钟走 [monotonic]（默认同 [wall]）；计时器与平台
  // 一样按单调时钟到点触发。
  void pass(Duration wall, [Duration? monotonic]) {
    now = now.add(wall);
    elapsed += monotonic ?? wall;
    for (final timer in List.of(timers)) {
      if (timer.isActive && timer.deadline <= elapsed) timer.fire();
    }
  }

  void awayFor(Duration wall, [Duration? monotonic]) {
    session().handleLifecycle(AppLifecycleState.paused);
    pass(wall, monotonic);
    session().handleLifecycle(AppLifecycleState.resumed);
  }

  test('a token is verified with its surrounding blanks removed', () async {
    final result = await session().signIn(' t-1 ');

    expect(result, isA<AdminSignedIn>());
    expect(state().active, isTrue);
    expect(state().notice, isNull);
    expect(api.tokens, ['t-1']);
  });

  test('a token refused says why, in the words agreed for each refusal, and '
      'starts no session', () async {
    Future<void> expectRefused(
      Object error,
      String code,
      String message,
    ) async {
      api.listRoomsError = error;
      expect(
        await session().signIn('t-1'),
        isA<AdminSignInRejected>()
            .having((r) => r.code, 'code', code)
            .having((r) => r.message, 'message', message),
      );
      expect(state().active, isFalse);
      await expectLater(listRooms(), throwsA(isA<AdminSessionEnded>()));
    }

    await expectRefused(_unauthorized, 'UNAUTHORIZED', '管理 token 无效');
    await expectRefused(_unauthorized, 'UNAUTHORIZED', adminTokenInvalidText);
    await expectRefused(_forbidden, 'FORBIDDEN', '这个服务器没有启用后台');
    await expectRefused(_forbidden, 'FORBIDDEN', adminDisabledText);
    await expectRefused(
      const ApiException(
        code: 'NETWORK',
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      ),
      'NETWORK',
      '网络请求失败，请检查网络后重试。',
    );
  });

  test('a token that cannot be verified for another reason asks to try again '
      'later, and only the error type is logged', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    api.listRoomsError = StateError('t-secret');

    final result = await session().signIn('t-secret');

    expect(
      result,
      isA<AdminSignInRejected>().having(
        (r) => r.message,
        'message',
        '没能验证管理 token，请稍后重试。',
      ),
    );
    expect(state().active, isFalse);
    expect(records.where((record) => record.contains('t-secret')), isEmpty);
  });

  test('requests go out with the token, and the session ends on a token the '
      'server no longer accepts', () async {
    await session().signIn('t-1');

    expect(await listRooms(), [same(api.rooms.single)]);
    expect(api.tokens, ['t-1', 't-1']);

    api.listRoomsError = const ApiException(
      code: 'CONFLICT',
      message: '冲突',
      status: 409,
    );
    await expectLater(
      listRooms(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CONFLICT')),
    );
    expect(state().active, isTrue);

    api.listRoomsError = _unauthorized;
    await expectLater(listRooms(), throwsA(_ended(resultUnknown: false)));
    expect(state().active, isFalse);
    expect(state().notice, adminTokenExpiredText);
    expect(state().notice, '管理 token 已失效，请重新输入');

    api.listRoomsError = null;
    final calls = api.listRoomsCalls;
    await expectLater(listRooms(), throwsA(isA<AdminSessionEnded>()));
    expect(api.listRoomsCalls, calls);
  });

  test('a server whose site admin was turned off ends the session', () async {
    await session().signIn('t-1');
    api.listRoomsError = _forbidden;

    await expectLater(listRooms(), throwsA(isA<AdminSessionEnded>()));

    expect(state().active, isFalse);
    expect(state().notice, adminDisabledText);
  });

  test('after the session ends nothing is sent', () async {
    await session().signIn('t-1');
    session().end();

    await expectLater(listRooms(), throwsA(_ended(resultUnknown: false)));

    expect(api.listRoomsCalls, 1);
    expect(state().active, isFalse);
    expect(state().notice, isNull);
  });

  test('an answer arriving after the session ended is not used, and what the '
      'request did is unknown', () async {
    await session().signIn('t-1');
    api.listRoomsGate = Completer();
    final pending = listRooms();
    await pumpEventQueue();

    session().end();
    api.listRoomsGate!.complete();

    await expectLater(pending, throwsA(_ended(resultUnknown: true)));
  });

  test('a token is never sent to a server other than the one it was entered '
      'for', () async {
    await session().signIn('t-1');
    await container
        .read(serverDirectoryProvider.notifier)
        .setCurrent(serverB.id);

    await expectLater(listRooms(), throwsA(isA<AdminSessionEnded>()));

    expect(api.listRoomsCalls, 1);
    expect(state().active, isFalse);
  });

  test('an answer from the old server arriving after the server changed is '
      'not used', () async {
    await session().signIn('t-1');
    api.listRoomsGate = Completer();
    final pending = listRooms();
    await pumpEventQueue();

    await container
        .read(serverDirectoryProvider.notifier)
        .setCurrent(serverB.id);
    api.listRoomsGate!.complete();

    await expectLater(pending, throwsA(isA<AdminSessionEnded>()));
    expect(state().active, isFalse);
  });

  test('a token verified while the server changed or the session was ended is '
      'not taken', () async {
    api.listRoomsGate = Completer();
    final changed = session().signIn('t-1');
    await pumpEventQueue();
    await container
        .read(serverDirectoryProvider.notifier)
        .setCurrent(serverB.id);
    api.listRoomsGate!.complete();
    await expectLater(changed, throwsA(isA<AdminSessionEnded>()));
    expect(state().active, isFalse);

    api.listRoomsGate = Completer();
    final ended = session().signIn('t-2');
    await pumpEventQueue();
    session().end();
    api.listRoomsGate!.complete();
    await expectLater(ended, throwsA(isA<AdminSessionEnded>()));
    expect(state().active, isFalse);
    await expectLater(listRooms(), throwsA(isA<AdminSessionEnded>()));
  });

  test('a refusal arriving after the server changed is not reported, since '
      'it was for the old server', () async {
    api
      ..listRoomsGate = Completer()
      ..listRoomsError = _forbidden;
    final refused = session().signIn('t-1');
    await pumpEventQueue();
    await container
        .read(serverDirectoryProvider.notifier)
        .setCurrent(serverB.id);
    api.listRoomsGate!.complete();

    await expectLater(refused, throwsA(isA<AdminSessionEnded>()));
  });

  test(
    'a notice is cleared on request and the session stays as it was',
    () async {
      await session().signIn('t-1');
      session().end(notice: adminTokenExpiredText);
      expect(state().notice, adminTokenExpiredText);

      session().clearNotice();

      expect(state().notice, isNull);
      expect(state().active, isFalse);
    },
  );

  test('coming back after 5 minutes away ends the session; 4:59 does '
      'not', () async {
    await session().signIn('t-1');

    session().handleLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    session().handleLifecycle(AppLifecycleState.resumed);
    expect(state().active, isTrue);

    session().handleLifecycle(AppLifecycleState.hidden);
    now = now.add(const Duration(minutes: 1));
    session().handleLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 4));
    session().handleLifecycle(AppLifecycleState.inactive);
    session().handleLifecycle(AppLifecycleState.resumed);

    expect(state().active, isFalse);
    expect(state().notice, adminAwayText);
    expect(state().notice, '离开后台超过 5 分钟，请重新输入管理 token');
    expect(adminBackgroundLimit, const Duration(minutes: 5));
    await expectLater(listRooms(), throwsA(isA<AdminSessionEnded>()));
  });

  test('time spent away before signing in does not count', () async {
    session().handleLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 10));
    session().handleLifecycle(AppLifecycleState.resumed);
    await session().signIn('t-1');

    session().handleLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 1));
    session().handleLifecycle(AppLifecycleState.resumed);

    expect(state().active, isTrue);
    expect(state().notice, isNull);
  });

  test('a token still being verified when the app comes back after 5 minutes '
      'or more is not taken', () async {
    api.listRoomsGate = Completer();
    final pending = session().signIn('t-1');
    await pumpEventQueue();

    awayFor(const Duration(minutes: 5, seconds: 1));
    api.listRoomsGate!.complete();

    await expectLater(pending, throwsA(isA<AdminSessionEnded>()));
    expect(state().active, isFalse);
    await expectLater(listRooms(), throwsA(isA<AdminSessionEnded>()));
  });

  test('a token being verified across 4:59 away is still taken', () async {
    api.listRoomsGate = Completer();
    final pending = session().signIn('t-1');
    await pumpEventQueue();

    awayFor(const Duration(minutes: 4, seconds: 59));
    api.listRoomsGate!.complete();

    expect(await pending, isA<AdminSignedIn>());
    expect(state().active, isTrue);
  });

  test('coming back after 5 minutes or more starts a new epoch, with or '
      'without a session, so whatever was typed is let go', () async {
    final first = state().epoch;

    awayFor(const Duration(minutes: 4, seconds: 59));
    expect(state().epoch, first);

    awayFor(const Duration(minutes: 6));
    expect(state().epoch, greaterThan(first));
    expect(state().active, isFalse);
    expect(state().notice, isNull);

    await session().signIn('t-1');
    final signedIn = state().epoch;
    awayFor(const Duration(minutes: 6));
    expect(state().epoch, greaterThan(signedIn));
    expect(state().notice, adminAwayText);
  });

  test(
    'a wall clock turned back while away does not keep the session',
    () async {
      await session().signIn('t-1');

      awayFor(const Duration(hours: -1), const Duration(minutes: 1));

      expect(state().active, isFalse);
      expect(state().notice, adminAwayText);
    },
  );

  test('the longer of the wall clock and the monotonic clock decides how long '
      'the app was away', () async {
    await session().signIn('t-1');
    const justUnder = Duration(minutes: 4, seconds: 59);
    awayFor(justUnder, justUnder);
    expect(state().active, isTrue);

    awayFor(const Duration(minutes: 1), const Duration(minutes: 6));
    expect(state().active, isFalse, reason: 'the wall clock was turned back');

    await session().signIn('t-1');
    awayFor(const Duration(minutes: 6), const Duration(minutes: 1));
    expect(
      state().active,
      isFalse,
      reason: 'the monotonic clock stood still while the device slept',
    );
  });

  group('while the app stays away', () {
    test('the session ends at 5 minutes, without coming back', () async {
      await session().signIn('t-1');
      final epoch = state().epoch;
      final calls = api.listRoomsCalls;

      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 4, seconds: 59));
      expect(state().active, isTrue);

      pass(const Duration(seconds: 1));
      expect(state().active, isFalse);
      expect(state().notice, adminAwayText);
      expect(state().epoch, epoch + 1);
      await expectLater(listRooms(), throwsA(_ended(resultUnknown: false)));
      expect(api.listRoomsCalls, calls);
    });

    test('the 5 minutes count from the first report of leaving', () async {
      await session().signIn('t-1');

      session().handleLifecycle(AppLifecycleState.hidden);
      pass(const Duration(minutes: 1));
      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 3, seconds: 59));
      expect(state().active, isTrue);

      pass(const Duration(seconds: 1));
      expect(state().active, isFalse);
    });

    test('coming back stops the count, and the next time away starts it '
        'again', () async {
      await session().signIn('t-1');

      awayFor(const Duration(minutes: 4));
      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 4));

      expect(state().active, isTrue);
      expect(timers.where((timer) => timer.isActive), hasLength(1));
    });

    test('coming back after the session ended away ends it no second '
        'time', () async {
      await session().signIn('t-1');
      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 6));
      final ended = state();

      session().handleLifecycle(AppLifecycleState.resumed);

      expect(state().epoch, ended.epoch);
      expect(state().notice, adminAwayText);
    });

    test('coming back still checks the time away when the count stood '
        'still while the device slept', () async {
      await session().signIn('t-1');
      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 6), const Duration(minutes: 1));
      expect(state().active, isTrue);

      session().handleLifecycle(AppLifecycleState.resumed);

      expect(state().active, isFalse);
      expect(state().notice, adminAwayText);
    });

    test('with no session, 5 minutes away let go of whatever was typed, '
        'with nothing to say', () async {
      final epoch = state().epoch;

      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 5));

      expect(state().epoch, epoch + 1);
      expect(state().active, isFalse);
      expect(state().notice, isNull);
    });

    test('a token still being verified at 5 minutes is not taken', () async {
      api.listRoomsGate = Completer();
      final pending = session().signIn('t-1');
      await pumpEventQueue();

      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 5));
      api.listRoomsGate!.complete();

      await expectLater(pending, throwsA(isA<AdminSessionEnded>()));
      expect(state().active, isFalse);
    });

    test('the count is stopped when the session goes away', () async {
      await session().signIn('t-1');
      session().handleLifecycle(AppLifecycleState.paused);
      expect(timers.single.isActive, isTrue);

      container.dispose();

      expect(timers.single.isActive, isFalse);
    });

    test('the end is logged with nothing but its name', () async {
      final records = <String>[];
      AppLog.onRecord = (name, level, message) => records.add(message);
      addTearDown(() => AppLog.onRecord = null);
      await session().signIn('t-secret');

      session().handleLifecycle(AppLifecycleState.paused);
      pass(const Duration(minutes: 5));

      expect(records, contains('session ended while away'));
      expect(records.where((record) => record.contains('t-secret')), isEmpty);
    });
  });

  group('a change', () {
    const conflict = ApiException(
      code: 'CONFLICT',
      message: 'slug taken',
      status: 409,
    );
    const invalid = ApiException(
      code: 'INVALID_ARGUMENT',
      message: '名字太长',
      status: 400,
    );
    const network = ApiException(
      code: 'NETWORK',
      message: '网络请求失败',
      status: null,
    );

    test('keeps the answer, words the refusals it is given, and takes a lost '
        'answer or an unexpected error as unknown, offering each for a '
        'reread', () async {
      final records = <String>[];
      AppLog.onRecord = (name, level, message) => records.add(message);
      addTearDown(() => AppLog.onRecord = null);
      await session().signIn('t-1');
      final reread = <MutationResult<int>>[];
      Future<MutationResult<int>> change(Object? error) {
        return session().change<int>(
          (api, token) =>
              error == null ? Future.value(7) : Future<int>.error(error),
          unexpected: 'test change ended unexpectedly',
          refusals: const {'CONFLICT': '这个别名已被占用'},
          reread: (result) async => reread.add(result),
        );
      }

      expect(
        await change(null),
        isA<MutationSucceeded<int>>().having((r) => r.value, 'value', 7),
      );
      expect(
        await change(conflict),
        isA<MutationFailed<int>>()
            .having((r) => r.code, 'code', 'CONFLICT')
            .having((r) => r.message, 'message', '这个别名已被占用'),
      );
      expect(
        await change(invalid),
        isA<MutationFailed<int>>()
            .having((r) => r.code, 'code', 'INVALID_ARGUMENT')
            .having((r) => r.message, 'message', '名字太长'),
      );
      expect(await change(network), isA<MutationUnknown<int>>());
      expect(
        await change(const ApiException.protocolMismatch(200)),
        isA<MutationUnknown<int>>(),
      );
      expect(await change(StateError('t-secret')), isA<MutationUnknown<int>>());

      expect(reread, hasLength(6));
      expect(
        records.where((r) => r.contains('test change ended unexpectedly')),
        hasLength(1),
      );
      expect(records.where((record) => record.contains('t-secret')), isEmpty);
    });

    // 后端可能已执行一部分（如修改房间时别名已改、密码未改），或房间稍后才执行
    // 这条输入，重发可能重复执行。
    test('the server could not finish is unknown and offered for a reread, '
        'never sent again', () async {
      await session().signIn('t-1');
      for (final code in ['UNAVAILABLE', 'INTERNAL']) {
        api.deletedRoomIds.clear();
        api.deleteRoomError = ApiException(
          code: code,
          message: '服务器没有及时响应',
          status: code == 'UNAVAILABLE' ? 503 : 500,
        );
        final reread = <MutationResult<void>>[];

        final result = await session().change<void>(
          (api, token) => api.deleteRoom(token, 'r1'),
          unexpected: 'test change ended unexpectedly',
          refusals: const {'CONFLICT': '这个别名已被占用'},
          reread: (result) async => reread.add(result),
        );

        expect(result, isA<MutationUnknown<void>>(), reason: code);
        expect(reread.single, same(result), reason: code);
        expect(api.deletedRoomIds, ['r1'], reason: code);
      }
    });

    test('turned away for coming too often was not carried out: it is not '
        'sent, says so, and is not reread', () async {
      await session().signIn('t-1');
      api.deleteRoomError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
      );
      var rereads = 0;

      final result = await session().change<void>(
        (api, token) => api.deleteRoom(token, 'r1'),
        unexpected: 'test change ended unexpectedly',
        reread: (_) async => rereads++,
      );

      expect(
        result,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          '请求太频繁，请稍后再试。',
        ),
      );
      expect(rereads, 0);
      expect(api.deletedRoomIds, ['r1']);
      expect(state().active, isTrue);
    });

    test('returns only after the reread it asked for', () async {
      await session().signIn('t-1');
      final reread = Completer<void>();
      var returned = false;

      unawaited(
        session()
            .change<void>(
              (api, token) => api.deleteRoom(token, 'r1'),
              unexpected: 'test change ended unexpectedly',
              reread: (_) => reread.future,
            )
            .then((_) => returned = true),
      );
      await pumpEventQueue();
      expect(returned, isFalse);

      reread.complete();
      await pumpEventQueue();
      expect(returned, isTrue);
    });

    test('with no session is not sent, in the words given, and with no '
        'reread', () async {
      var rereads = 0;
      Future<void> delete(AdminApi api, String token) =>
          api.deleteRoom(token, 'r1');
      Future<void> reread(MutationResult<void> _) async => rereads++;

      expect(
        await session().change<void>(
          delete,
          unexpected: 'test change ended unexpectedly',
          reread: reread,
        ),
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          '后台会话已结束',
        ),
      );
      expect(
        await session().change<void>(
          delete,
          unexpected: 'test change ended unexpectedly',
          sessionEnded: '后台已退出，品牌名没有保存。',
          reread: reread,
        ),
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          '后台已退出，品牌名没有保存。',
        ),
      );
      expect(api.deletedRoomIds, isEmpty);
      expect(rereads, 0);
    });

    test('whose session ended while it was waiting is unknown, with no '
        'reread', () async {
      await session().signIn('t-1');
      api.listRoomsGate = Completer();
      var rereads = 0;
      final pending = session().change<List<RoomListing>>(
        (api, token) => api.listRooms(token),
        unexpected: 'test change ended unexpectedly',
        reread: (_) async => rereads++,
      );
      await pumpEventQueue();

      session().end();
      api.listRoomsGate!.complete();

      expect(await pending, isA<MutationUnknown<List<RoomListing>>>());
      expect(rereads, 0);
    });
  });
}

// 只由测试按单调时钟推进触发。
final class _FakeTimer implements Timer {
  _FakeTimer(this.deadline, this._callback);

  final Duration deadline;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    _active = false;
    _callback();
  }
}
