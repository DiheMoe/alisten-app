import 'dart:async';

import 'package:alisten/features/account/data/browser_github_authorizer.dart';
import 'package:alisten/features/account/index.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

final _url = Uri.parse('https://github.com/login/oauth/authorize?state=s');
final _landing = Uri.parse('moe.dihe.alisten:/auth/github#code=c-1');

void main() {
  late StreamController<Uri> links;
  late List<String> steps;

  BrowserGithubAuthorizer authorizer({
    Future<void> Function()? register,
    Future<bool> Function(Uri url)? open,
  }) {
    return BrowserGithubAuthorizer(
      links: links.stream,
      register:
          register ??
          () async {
            steps.add('register');
          },
      open:
          open ??
          (url) async {
            steps.add('open $url');
            return true;
          },
    );
  }

  setUp(() {
    links = StreamController<Uri>.broadcast();
    steps = [];
  });
  tearDown(() => links.close());

  test('the scheme is registered, the page opens in the browser, and the '
      'address the system hands back is returned', () async {
    final callback = authorizer().authorize(_url);
    await pumpEventQueue();
    expect(steps, ['register', 'open $_url']);

    links.add(_landing);

    expect(await callback, _landing);
    expect(links.hasListener, isFalse);
  });

  test('links that are not the landing address are left to others', () async {
    final callback = authorizer().authorize(_url);
    await pumpEventQueue();

    links.add(Uri.parse('https://livehouse.dihe.moe/r/listen'));
    links.add(_landing);

    expect(await callback, _landing);
  });

  test('a browser that never comes back ends the wait after five minutes', () {
    fakeAsync((async) {
      Uri? callback = _landing;
      var done = false;
      unawaited(
        authorizer().authorize(_url).then((value) {
          callback = value;
          done = true;
        }),
      );
      async.elapse(const Duration(minutes: 4, seconds: 59));
      expect(done, isFalse);

      async.elapse(const Duration(seconds: 2));

      expect(done, isTrue);
      expect(callback, isNull);
      expect(links.hasListener, isFalse);
    });
  });

  test('no program to open the page with is a failure, not a wait', () async {
    await expectLater(
      authorizer(open: (_) async => false).authorize(_url),
      throwsA(isA<GithubAuthorizerFailed>()),
    );
    expect(links.hasListener, isFalse);
  });

  test('a scheme that cannot be registered is a failure, and the browser '
      'stays closed', () async {
    await expectLater(
      authorizer(register: () async => throw StateError('no home directory'))
          .authorize(_url),
      throwsA(isA<GithubAuthorizerFailed>()),
    );
    expect(steps, isEmpty);
  });
}
