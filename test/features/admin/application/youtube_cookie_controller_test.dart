import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _cookies =
    '# Netscape HTTP Cookie File\n'
    '.youtube.com\tTRUE\t/\tTRUE\t1800000000\tSID\tsecret-sid\n';

const _network = ApiException(
  code: 'NETWORK',
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

const _unrecognized = ApiException(
  code: 'INVALID_ARGUMENT',
  message: '没有识别出 YouTube 的 cookies',
  status: 400,
);

final _overhead = utf8.encode(jsonEncode({'cookies': ''})).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdminApi api;
  late ProviderContainer container;

  YoutubeCookieController controller() =>
      container.read(youtubeCookieControllerProvider.notifier);
  YoutubeCookieState state() => container.read(youtubeCookieControllerProvider);

  setUp(() async {
    api = FakeAdminApi();
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    container.listen(youtubeCookieControllerProvider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  group('cookies that are not sent', () {
    test('blank cookies ask for cookies to be pasted', () {
      expect(youtubeCookieProblem(''), youtubeCookieEmptyText);
      expect(youtubeCookieProblem('   '), youtubeCookieEmptyText);
      expect(youtubeCookieProblem(' \n\t '), youtubeCookieEmptyText);
      expect(youtubeCookieProblem(_cookies), isNull);
    });

    test('the limit is on the bytes of the whole request body, which may be '
        '64 KiB and no more', () {
      final fits = 'a' * (youtubeCookieBodyLimit - _overhead);

      expect(_overhead, 14);
      expect(youtubeCookieProblem(fits), isNull);
      expect(youtubeCookieProblem('${fits}a'), youtubeCookieTooLargeText);
    });

    test('characters count by their UTF-8 bytes, and line breaks and tabs as '
        'JSON escapes them', () {
      expect(youtubeCookieProblem('中' * 21840), isNull);
      expect(youtubeCookieProblem('中' * 21841), youtubeCookieTooLargeText);
      expect(youtubeCookieProblem('a${'\t' * 32760}'), isNull);
      expect(
        youtubeCookieProblem('a${'\t' * 32761}'),
        youtubeCookieTooLargeText,
      );
      expect(youtubeCookieProblem('a${'\n' * 32760}'), isNull);
      expect(
        youtubeCookieProblem('a${'\n' * 32761}'),
        youtubeCookieTooLargeText,
      );
    });

    test('blank or oversized cookies are not sent', () async {
      final blank = await controller().save('  \n ');
      final oversized = await controller().save(
        'a' * (youtubeCookieBodyLimit - _overhead + 1),
      );

      expect(
        blank,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          youtubeCookieEmptyText,
        ),
      );
      expect(
        oversized,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          youtubeCookieTooLargeText,
        ),
      );
      expect(api.savedCookies, isEmpty);
    });
  });

  test('the status tells whether cookies are saved and since when, read '
      'with the admin token', () async {
    api.youtubeCookie = const YoutubeCookieStatus(
      saved: true,
      updatedAtMs: 1700000000000,
    );

    await controller().load();

    final status = state().status!;
    expect(status.saved, isTrue);
    expect(status.updatedAtMs, 1700000000000);
    expect(state().loading, isFalse);
    expect(state().error, isNull);
    expect(api.tokens.last, 't-1');
  });

  test(
    'a status that cannot be read says why and keeps what was read',
    () async {
      await controller().load();
      api.getYoutubeCookieError = const ApiException(
        code: 'INTERNAL',
        message: '服务器出错了',
        status: 500,
      );

      await controller().load();

      expect(state().status!.saved, isFalse);
      expect(state().loading, isFalse);
      expect(state().error, '服务器出错了');
    },
  );

  test('a status this version cannot read asks for an upgrade', () async {
    api.getYoutubeCookieError = const ApiException.protocolMismatch(200);

    await controller().load();

    expect(state().error, '服务器返回了无法识别的数据，请升级 Alisten。');
  });

  test('a status read before a later one does not replace it', () async {
    final first = api.getYoutubeCookieGate = Completer();
    final early = controller().load();
    await pumpEventQueue();
    api
      ..getYoutubeCookieGate = null
      ..youtubeCookie = const YoutubeCookieStatus(
        saved: true,
        updatedAtMs: 1700000000000,
      );
    await controller().load();

    first.complete();
    await early;

    expect(state().status!.saved, isTrue);
  });

  test('cookies are sent as pasted, blanks and all, and the status is read '
      'again', () async {
    await controller().load();
    final read = api.getYoutubeCookieCalls;

    final result = await controller().save('  $_cookies');
    await pumpEventQueue();

    expect(result, isA<MutationSucceeded<void>>());
    expect(api.savedCookies.single, '  $_cookies');
    expect(api.tokens.last, 't-1');
    expect(api.getYoutubeCookieCalls, read + 1);
    expect(state().status!.saved, isTrue);
    expect(state().status!.updatedAtMs, 1800000000000);
  });

  test('cookies the server cannot recognise are refused in its own '
      'words', () async {
    api.setYoutubeCookieError = _unrecognized;

    final result = await controller().save(_cookies);

    expect(
      result,
      isA<MutationFailed<void>>()
          .having((r) => r.code, 'code', 'INVALID_ARGUMENT')
          .having((r) => r.message, 'message', '没有识别出 YouTube 的 cookies'),
    );
    expect(api.savedCookies, hasLength(1));
  });

  test('a refusal this version cannot read asks for an upgrade', () async {
    api.setYoutubeCookieError = const ApiException.protocolMismatch(400);

    final result = await controller().save(_cookies);

    expect(
      result,
      isA<MutationFailed<void>>().having(
        (r) => r.message,
        'message',
        '服务器返回了无法识别的数据，请升级 Alisten。',
      ),
    );
  });

  test('cookies sent without an answer may be saved: they are not sent '
      'again and the status is read again', () async {
    await controller().load();
    api.setYoutubeCookieError = _network;
    final read = api.getYoutubeCookieCalls;

    final result = await controller().save(_cookies);
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<void>>());
    expect(api.savedCookies, hasLength(1));
    expect(api.getYoutubeCookieCalls, read + 1);
  });

  test('a save failing unexpectedly is unknown and logged by its type '
      'only', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    api.setYoutubeCookieError = StateError(_cookies);
    final read = api.getYoutubeCookieCalls;

    final result = await controller().save(_cookies);
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<void>>());
    expect(api.getYoutubeCookieCalls, read + 1);
    expect(records, contains(contains('StateError')));
    expect(records.where((r) => r.contains('secret-sid')), isEmpty);
    expect(records.where((r) => r.contains('t-1')), isEmpty);
  });

  test('the cookies never become part of the state', () async {
    final states = <YoutubeCookieState>[];
    container.listen(
      youtubeCookieControllerProvider,
      (_, next) => states.add(next),
    );

    await controller().save(_cookies);
    api.setYoutubeCookieError = _unrecognized;
    await controller().save(_cookies);
    api.setYoutubeCookieError = _network;
    await controller().save(_cookies);
    await pumpEventQueue();

    expect(states, isNotEmpty);
    for (final state in states) {
      for (final text in [
        state.toString(),
        state.status.toString(),
        '${state.error}',
      ]) {
        expect(text, isNot(contains('secret-sid')));
      }
    }
  });

  test('cleared cookies are gone when the status is read again', () async {
    api.youtubeCookie = const YoutubeCookieStatus(
      saved: true,
      updatedAtMs: 1700000000000,
    );
    await controller().load();
    final read = api.getYoutubeCookieCalls;

    final result = await controller().clear();
    await pumpEventQueue();

    expect(result, isA<MutationSucceeded<void>>());
    expect(api.deleteYoutubeCookieCalls, 1);
    expect(api.getYoutubeCookieCalls, read + 1);
    expect(state().status!.saved, isFalse);
  });

  test('a clear without an answer may have taken effect: it is not sent '
      'again and the status is read again', () async {
    api.deleteYoutubeCookieError = _network;
    final read = api.getYoutubeCookieCalls;

    final result = await controller().clear();
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<void>>());
    expect(api.deleteYoutubeCookieCalls, 1);
    expect(api.getYoutubeCookieCalls, read + 1);
  });

  for (final (code, status) in [('UNAVAILABLE', 503), ('INTERNAL', 500)]) {
    test('a save or clear the server could not finish ($code) may have taken '
        'effect: it is not sent again and the status is read again', () async {
      final error = ApiException(code: code, message: '服务器出错了', status: status);
      api
        ..setYoutubeCookieError = error
        ..deleteYoutubeCookieError = error;
      final read = api.getYoutubeCookieCalls;

      final saved = await controller().save(_cookies);
      await pumpEventQueue();

      expect(saved, isA<MutationUnknown<void>>());
      expect(api.savedCookies, hasLength(1));
      expect(api.getYoutubeCookieCalls, read + 1);

      final cleared = await controller().clear();
      await pumpEventQueue();

      expect(cleared, isA<MutationUnknown<void>>());
      expect(api.deleteYoutubeCookieCalls, 1);
      expect(api.getYoutubeCookieCalls, read + 2);
    });
  }

  test('a save or clear turned away for coming too often was not carried '
      'out: it says so and the status is not read again', () async {
    const limited = ApiException(
      code: 'RATE_LIMITED',
      message: '请求太频繁，请稍后再试。',
      status: 429,
    );
    api
      ..setYoutubeCookieError = limited
      ..deleteYoutubeCookieError = limited;
    final read = api.getYoutubeCookieCalls;

    final saved = await controller().save(_cookies);
    final cleared = await controller().clear();
    await pumpEventQueue();

    for (final result in [saved, cleared]) {
      expect(
        result,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          '请求太频繁，请稍后再试。',
        ),
      );
    }
    expect(api.getYoutubeCookieCalls, read);
  });

  test('a token the server no longer takes ends the session; nothing is read '
      'again', () async {
    api.setYoutubeCookieError = const ApiException(
      code: 'UNAUTHORIZED',
      message: 'token invalid',
      status: 401,
    );
    final read = api.getYoutubeCookieCalls;

    final result = await controller().save(_cookies);
    await pumpEventQueue();

    expect(
      result,
      isA<MutationNotSent<void>>().having(
        (r) => r.message,
        'message',
        '后台会话已结束',
      ),
    );
    expect(container.read(adminSessionProvider).active, isFalse);
    expect(api.getYoutubeCookieCalls, read);
  });

  test('cookies are never sent to a server other than the one the session '
      'is for', () async {
    await container
        .read(serverDirectoryProvider.notifier)
        .setCurrent(serverB.id);

    final saved = await controller().save(_cookies);
    final cleared = await controller().clear();

    expect(saved, isA<MutationNotSent<void>>());
    expect(cleared, isA<MutationNotSent<void>>());
    expect(api.savedCookies, isEmpty);
    expect(api.deleteYoutubeCookieCalls, 0);
  });

  test('cookies sent before the session ended may be saved', () async {
    final gate = api.setYoutubeCookieGate = Completer();
    final pending = controller().save(_cookies);
    await pumpEventQueue();

    container.read(adminSessionProvider.notifier).end();
    gate.complete();

    expect(await pending, isA<MutationUnknown<void>>());
  });
}
