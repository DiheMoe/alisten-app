import 'package:alisten/domain/member/member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the avatar is the Gravatar picture at twice its size, and none '
      'without an email', () {
    const member = Member(id: 'm', name: '小明', avatarHash: 'abc123');
    const anonymous = Member(id: 'a', name: '阿柚', avatarHash: '');

    expect(
      member.avatarUrl(40),
      'https://www.gravatar.com/avatar/abc123?d=identicon&s=80',
    );
    expect(member.avatarUrl(17.6), endsWith('&s=35'));
    expect(anonymous.avatarUrl(40), isNull);
  });
}
