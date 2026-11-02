import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart' show roomListing;

void main() {
  group('a change to a room', () {
    final original = roomListing(
      name: 'A',
      description: 'd',
      slug: 'hall',
      hasPassword: true,
    );

    RoomPatch patchOf({
      String name = 'A',
      String description = 'd',
      String slug = 'hall',
      PasswordChoice password = const KeepPassword(),
    }) => roomPatch(
      original,
      RoomForm(
        name: name,
        description: description,
        slug: slug,
        password: password,
      ),
    );

    test('carries only the fields that changed', () {
      final patch = patchOf(description: 'd2');

      expect(patch.description, 'd2');
      expect(patch.name, isNull);
      expect(patch.slug, isNull);
      expect(patch.password, isNull);
      expect(patch.isEmpty, isFalse);
      expect(
        const protocol.AdminUpdateRoomRequest(description: 'd2').toJson(),
        {'description': 'd2'},
      );
    });

    test('a name is compared without its surrounding blanks and sent without '
        'them', () {
      expect(patchOf(name: '  A ').isEmpty, isTrue);
      expect(patchOf(name: ' B ').name, 'B');
    });

    // 服务端不去除简介的首尾空白，原样保存。
    test('a description is compared and sent as typed, blanks and all', () {
      expect(patchOf(description: ' d ').description, ' d ');
      expect(patchOf(description: 'd\n').description, 'd\n');
    });

    test('an emptied alias takes the alias away', () {
      expect(patchOf(slug: '').slug, '');
      expect(patchOf(slug: 'lounge').slug, 'lounge');
    });

    test('a password is set, changed or taken away only when asked', () {
      expect(patchOf(password: const RemovePassword()).password, '');
      expect(patchOf(password: const SetPassword('p')).password, 'p');
      expect(patchOf(password: const KeepPassword()).password, isNull);
    });

    test('the same room changes nothing', () {
      expect(patchOf().isEmpty, isTrue);
    });

    test('taking away a password the room does not have changes nothing', () {
      final open = roomListing(
        name: 'A',
        description: 'd',
        slug: 'hall',
        hasPassword: false,
      );

      final patch = roomPatch(
        open,
        const RoomForm(
          name: 'A',
          description: 'd',
          slug: 'hall',
          password: RemovePassword(),
        ),
      );

      expect(patch.password, isNull);
      expect(patch.isEmpty, isTrue);
    });

    test('a room without an alias compares against an empty alias', () {
      final unnamed = roomListing(name: 'A', description: 'd', slug: null);

      RoomPatch patch(String slug) =>
          roomPatch(unnamed, RoomForm(name: 'A', description: 'd', slug: slug));

      expect(patch('').isEmpty, isTrue);
      expect(patch('hall').slug, 'hall');
    });
  });

  group('a room form', () {
    RoomForm form({
      String name = '大厅',
      String description = '',
      String slug = '',
      PasswordChoice password = const KeepPassword(),
    }) => RoomForm(
      name: name,
      description: description,
      slug: slug,
      password: password,
    );

    test('says what is wrong with it', () {
      expect(roomFormProblem(form(name: '  ')), '请输入房间名称');
      expect(roomFormProblem(form(name: '长' * 81)), '房间名称最多 80 个字');
      expect(roomFormProblem(form(description: '长' * 501)), '简介最多 500 个字');
      expect(roomFormProblem(form(slug: 'Hall')), '别名只能用小写字母、数字和连字符，最多 32 个');
      expect(roomFormProblem(form(slug: 'a' * 33)), '别名只能用小写字母、数字和连字符，最多 32 个');
      expect(roomFormProblem(form(password: const SetPassword(''))), '请输入新密码');
    });

    test('within the limits has nothing wrong', () {
      expect(roomFormProblem(form()), isNull);
      expect(
        roomFormProblem(
          form(
            name: ' ${'长' * 80} ',
            description: '长' * 500,
            slug: 'late-night-2',
            password: const SetPassword('p'),
          ),
        ),
        isNull,
      );
      expect(roomFormProblem(form(slug: 'a' * 32)), isNull);
      expect(roomFormProblem(form(password: const RemovePassword())), isNull);
    });

    test('lengths are counted in characters as the server counts them', () {
      const note = '\u{1F3B5}';

      expect(roomFormProblem(form(name: note * 80)), isNull);
      expect(roomFormProblem(form(name: note * 81)), '房间名称最多 80 个字');
      expect(roomFormProblem(form(description: note * 500)), isNull);
      expect(roomFormProblem(form(description: note * 501)), '简介最多 500 个字');
    });

    test('an alias is either empty or matches the server pattern', () {
      expect(roomSlugProblem(''), isNull);
      expect(roomSlugProblem('hall-2'), isNull);
      for (final slug in ['Hall', 'hall 2', 'hall_2', '大厅', ' hall']) {
        expect(roomSlugProblem(slug), roomSlugRuleText, reason: slug);
      }
    });

    test('a new room is sent with its name trimmed, without an empty alias '
        'and with the password asked for', () {
      final draft = roomDraft(
        form(
          name: ' 大厅 ',
          description: '',
          slug: '',
          password: const SetPassword('p'),
        ),
      );

      expect(draft.name, '大厅');
      expect(draft.description, '');
      expect(draft.slug, isNull);
      expect(draft.password, 'p');
    });

    test('a new room keeps the blanks around its description, which count '
        'toward its length', () {
      expect(roomDraft(form(description: ' 每晚八点\n')).description, ' 每晚八点\n');
      expect(
        roomFormProblem(form(description: ' ${'长' * 499} ')),
        '简介最多 500 个字',
      );
    });

    test('a new room without a password asked for has none', () {
      final draft = roomDraft(form(slug: 'hall'));

      expect(draft.slug, 'hall');
      expect(draft.password, isNull);
    });
  });
}
