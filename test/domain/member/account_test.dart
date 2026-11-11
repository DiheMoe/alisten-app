import 'package:alisten/domain/member/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('usernameProblem', () {
    for (final valid in ['abc', 'a' * 32, 'dj_mao-2']) {
      test('accepts "$valid"', () => expect(usernameProblem(valid), isNull));
    }
    for (final invalid in ['ab', 'a' * 33, 'Abc', 'a b', '用户名', '']) {
      test('rejects "$invalid"', () {
        expect(usernameProblem(invalid), usernameRuleText);
      });
    }
  });

  group('passwordProblem', () {
    test('counts Unicode code points like the server', () {
      // 8 个表情符号是 16 个 UTF-16 码元，按码点算正好 8 个。
      expect(passwordProblem('🎵' * 8), isNull);
      expect(passwordProblem('🎵' * 7), passwordRuleText);
      expect(passwordProblem('🎵' * 128), isNull);
      expect(passwordProblem('🎵' * 129), passwordRuleText);
    });

    test('accepts 8 to 128 characters', () {
      expect(passwordProblem('a' * 7), passwordRuleText);
      expect(passwordProblem('a' * 8), isNull);
      expect(passwordProblem('a' * 128), isNull);
      expect(passwordProblem('a' * 129), passwordRuleText);
    });
  });

  test('a login device credential is 43 base64url characters', () {
    final valid = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM-_01';
    expect(valid.length, 43);
    expect(isLoginDevice(valid), isTrue);
    expect(isLoginDevice(valid.substring(1)), isFalse);
    expect(isLoginDevice('${valid.substring(1)}='), isFalse);
    expect(isLoginDevice('${valid}a'), isFalse);
  });

  test('withEmail keeps the rest of the account', () {
    const account = Account(username: 'mao', github: true);
    final changed = account.withEmail('mao@example.com');
    expect(changed.username, 'mao');
    expect(changed.github, isTrue);
    expect(changed.email, 'mao@example.com');
    expect(changed.withEmail(null).email, isNull);
  });
}
