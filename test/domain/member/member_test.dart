import 'package:alisten/domain/member/member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the avatar is the Gravatar picture at one size wherever it is shown, '
      'and none without an email', () {
    const member = Member(id: 'm', name: '小明', avatarHash: 'abc123');
    const anonymous = Member(id: 'a', name: '阿柚', avatarHash: '');

    expect(
      member.avatarUrl,
      'https://www.gravatar.com/avatar/abc123?d=404&s=128',
    );
    expect(anonymous.avatarUrl, isNull);
  });

  test('the avatar address is built from the hash alone, as for members', () {
    expect(
      avatarUrlFor('abc123'),
      'https://www.gravatar.com/avatar/abc123?d=404&s=128',
    );
    expect(avatarUrlFor(''), isNull);
  });
}
