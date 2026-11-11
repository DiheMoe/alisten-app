import 'package:alisten/domain/member/member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the avatar is the Gravatar picture at twice its size, and none '
      'without an email', () {
    const member = Member(id: 'm', name: '小明', avatarHash: 'abc123');
    const anonymous = Member(id: 'a', name: '阿柚', avatarHash: '');

    expect(
      member.avatarUrl(40),
      'https://www.gravatar.com/avatar/abc123?d=404&s=80',
    );
    expect(member.avatarUrl(17.6), endsWith('&s=35'));
    expect(anonymous.avatarUrl(40), isNull);
  });

  test('the avatar address is built from the hash alone, as for members', () {
    expect(
      avatarUrlFor('abc123', 40),
      'https://www.gravatar.com/avatar/abc123?d=404&s=80',
    );
    expect(avatarUrlFor('abc123', 17.6), endsWith('&s=35'));
    expect(avatarUrlFor('abc123', 5000), endsWith('&s=2048'));
    expect(avatarUrlFor('', 40), isNull);
  });
}
