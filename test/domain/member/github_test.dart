import 'package:alisten/domain/member/github.dart';
import 'package:flutter_test/flutter_test.dart';

GithubCallback _read(String uri) => readGithubCallback(Uri.parse(uri));

void main() {
  test('the callback scheme is the package name the server lands on', () {
    expect(githubCallbackScheme, 'moe.dihe.alisten');
  });

  for (final code in ['c-1', 'a' * 128]) {
    test('a code of ${code.length} characters is granted', () {
      expect(
        _read('moe.dihe.alisten:/auth/github#code=$code'),
        isA<GithubGranted>().having((granted) => granted.code, 'code', code),
      );
    });
  }

  test('a code is granted even next to an error', () {
    expect(
      _read('moe.dihe.alisten:/auth/github#code=x&error=denied'),
      isA<GithubGranted>().having((granted) => granted.code, 'code', 'x'),
    );
  });

  for (final (fragment, reason) in [
    ('error=denied', GithubRefusal.denied),
    ('error=expired', GithubRefusal.expired),
    ('error=failed', GithubRefusal.failed),
    ('error=something-new', GithubRefusal.failed),
    ('error=', GithubRefusal.failed),
    ('', GithubRefusal.missing),
    ('state=s', GithubRefusal.missing),
    ('code=', GithubRefusal.missing),
    ('code=${'a' * 129}', GithubRefusal.missing),
    ('code=%FF', GithubRefusal.missing),
  ]) {
    test('"#$fragment" is refused as ${reason.name}', () {
      expect(
        _read('moe.dihe.alisten:/auth/github#$fragment'),
        isA<GithubRefused>().having(
          (refused) => refused.reason,
          'reason',
          reason,
        ),
      );
    });
  }

  for (final uri in [
    'other.app:/auth/github#code=c-1',
    'moe.dihe.alisten:/auth/other#code=c-1',
    'https://alisten.example/auth/github#code=c-1',
  ]) {
    test('$uri is not the callback', () {
      expect(
        _read(uri),
        isA<GithubRefused>().having(
          (refused) => refused.reason,
          'reason',
          GithubRefusal.missing,
        ),
      );
    });
  }
}
