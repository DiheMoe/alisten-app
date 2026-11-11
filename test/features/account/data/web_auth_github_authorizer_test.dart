import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/account/data/web_auth_github_authorizer.dart';
import 'package:alisten/features/account/index.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

final _url = Uri.parse('https://github.com/login/oauth/authorize?state=s');

typedef _Call = ({String url, String scheme, FlutterWebAuth2Options options});

void main() {
  late List<_Call> calls;

  WebAuthGithubAuthorizer authorizer(Future<String> Function() reply) {
    return WebAuthGithubAuthorizer(
      authenticate:
          ({
            required String url,
            required String callbackUrlScheme,
            FlutterWebAuth2Options options = const FlutterWebAuth2Options(),
          }) {
            calls.add((url: url, scheme: callbackUrlScheme, options: options));
            return reply();
          },
    );
  }

  setUp(() => calls = []);

  test('the address the browser lands on is handed back as it is', () async {
    final callback = await authorizer(
      () async => 'moe.dihe.alisten:/auth/github#code=c-1',
    ).authorize(_url);

    expect(callback, Uri.parse('moe.dihe.alisten:/auth/github#code=c-1'));
    final call = calls.single;
    expect(call.url, '$_url');
    expect(call.scheme, 'moe.dihe.alisten');
    expect(call.options.toJson(), const FlutterWebAuth2Options().toJson());
    expect(call.options.preferEphemeral, isFalse);
  });

  test('closing the browser is no result', () async {
    final callback = await authorizer(
      () async => throw PlatformException(
        code: 'CANCELED',
        message: 'User canceled login',
      ),
    ).authorize(_url);

    expect(callback, isNull);
  });

  test('any other failure fails the authorization and logs only its '
      'code', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add(message);
    addTearDown(() => AppLog.onRecord = null);

    await expectLater(
      authorizer(
        () async => throw PlatformException(
          code: 'FAILED',
          message: 'no browser for https://github.com/login?state=s',
        ),
      ).authorize(_url),
      throwsA(isA<GithubAuthorizerFailed>()),
    );
    expect(records, [contains('code=FAILED')]);
    expect(records.where((record) => record.contains('github.com')), isEmpty);
  });

  test('a non-platform error fails the authorization and logs only its '
      'type', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add(message);
    addTearDown(() => AppLog.onRecord = null);

    await expectLater(
      authorizer(() async => throw StateError('x')).authorize(_url),
      throwsA(isA<GithubAuthorizerFailed>()),
    );
    expect(records, [contains('StateError')]);
  });
}
