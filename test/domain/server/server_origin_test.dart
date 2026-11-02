import 'package:alisten/domain/server/server_origin.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _valid(String origin) =>
    isA<ValidOrigin>().having((input) => input.origin, 'origin', origin);

Matcher _invalid(OriginProblem problem) =>
    isA<InvalidOrigin>().having((input) => input.problem, 'problem', problem);

void main() {
  group('parseServerOrigin', () {
    test('keeps only the lowercase origin and drops the default port', () {
      for (final (input, origin) in [
        ('https://Example.COM/', 'https://example.com'),
        ('HTTPS://EXAMPLE.com', 'https://example.com'),
        ('https://example.com:443/r/abc?x=1#y', 'https://example.com'),
        ('https://example.com:8443', 'https://example.com:8443'),
        ('https://example.com:1', 'https://example.com:1'),
        ('https://example.com:65535', 'https://example.com:65535'),
        ('https://[::1]:8443/x', 'https://[::1]:8443'),
      ]) {
        expect(
          parseServerOrigin(input, allowCleartext: false),
          _valid(origin),
          reason: input,
        );
      }
    });

    test('an address without a scheme is taken as HTTPS', () {
      expect(
        parseServerOrigin('  example.com  ', allowCleartext: false),
        _valid('https://example.com'),
      );
    });

    test('HTTP is accepted only when cleartext is allowed', () {
      expect(
        parseServerOrigin('http://10.0.2.2:9876', allowCleartext: false),
        _invalid(OriginProblem.cleartext),
      );
      expect(
        parseServerOrigin('http://10.0.2.2:9876', allowCleartext: true),
        _valid('http://10.0.2.2:9876'),
      );
      expect(
        parseServerOrigin('http://example.com:80', allowCleartext: true),
        _valid('http://example.com'),
      );
    });

    test('a trailing dot of the host name is dropped', () {
      expect(
        parseServerOrigin('https://Example.com./r/x', allowCleartext: false),
        _valid('https://example.com'),
      );
      expect(
        parseServerOrigin('example.com.:8443', allowCleartext: false),
        _valid('https://example.com:8443'),
      );
    });

    test('rejects what is not an HTTP(S) origin', () {
      for (final input in [
        '',
        'https://',
        'ftp://example.com',
        'https://user:pw@example.com',
        // Uri 会把非 ASCII 主机名和空格转义为 `%XX`，得到的不是可连接的主机名。
        'https://例子.com',
        'https://a b.com',
        'https://a%20b.com',
        'https://a.com:0',
        'https://a.com:65536',
        'https://a.com:-1',
        'https://a.com:99999999999999999999',
        'https://.',
        'https://example.com..',
        'https://.example.com',
        'https://a..b.com',
        'a..b.com',
      ]) {
        expect(
          parseServerOrigin(input, allowCleartext: false),
          _invalid(OriginProblem.malformed),
          reason: input,
        );
      }
    });
  });

  test('serverIdFor is the 64-bit FNV-1a hash of the UTF-8 origin', () {
    const vectors = {
      '': 'cbf29ce484222325',
      'a': 'af63dc4c8601ec8c',
      'foobar': '85944171f73967e8',
      'https://livehouse.dihe.moe': 'fcd7a878032db68b',
      'https://example.com': '837b2b5793a240b3',
      'https://example.com:8443': 'f475765b53c3272e',
      'http://127.0.0.1:9876': '5a9795ac2ddb76e6',
    };
    for (final MapEntry(key: origin, value: id) in vectors.entries) {
      expect(serverIdFor(origin), id, reason: origin);
    }
  });

  test('originAuthority keeps the port and the IPv6 brackets', () {
    expect(originAuthority('https://example.com:8443'), 'example.com:8443');
    expect(originAuthority('https://[::1]:8443'), '[::1]:8443');
    expect(originAuthority('https://example.com'), 'example.com');
  });
}
