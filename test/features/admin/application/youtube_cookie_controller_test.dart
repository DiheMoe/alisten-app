import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
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
}
