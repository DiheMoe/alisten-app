import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/application/admin_models.dart';

sealed class PasswordChoice {
  const PasswordChoice();
}

final class KeepPassword extends PasswordChoice {
  const KeepPassword();
}

final class SetPassword extends PasswordChoice {
  const SetPassword(this.password);

  final String password;
}

final class RemovePassword extends PasswordChoice {
  const RemovePassword();
}

final class RoomForm {
  const RoomForm({
    required this.name,
    required this.description,
    required this.slug,
    required this.capacity,
    this.password = const KeepPassword(),
  });

  final String name;
  final String description;

  /// 为空表示没有别名。
  final String slug;
  final PasswordChoice password;

  /// 输入框里的文字，[roomCapacity] 读出人数。
  final String capacity;
}

final roomSlugPattern = RegExp(r'^[a-z0-9-]{1,32}$');

const roomSlugRuleText = '别名只能用小写字母、数字和连字符，最多 32 个';

const roomNameMaxLength = 80;
const _maxDescriptionLength = 500;
const roomCapacityMin = 2;
const roomCapacityMax = 128;
const roomCapacityRuleText = '最多人数要在 $roomCapacityMin 到 $roomCapacityMax 之间';

/// 不是范围内的整数时返回 null。
int? roomCapacity(String input) {
  final capacity = int.tryParse(input.trim());
  if (capacity == null ||
      capacity < roomCapacityMin ||
      capacity > roomCapacityMax) {
    return null;
  }
  return capacity;
}

String? roomCapacityProblem(String input) {
  return roomCapacity(input) == null ? roomCapacityRuleText : null;
}

/// 与服务端一致按码点计长度；发送前会去掉首尾空白，所以不计入。
int roomNameLength(String name) => name.trim().runes.length;

String? roomSlugProblem(String slug) {
  if (slug.isEmpty || roomSlugPattern.hasMatch(slug)) return null;
  return roomSlugRuleText;
}

String? roomFormProblem(RoomForm form) {
  if (form.name.trim().isEmpty) return '请输入房间名称';
  if (roomNameLength(form.name) > roomNameMaxLength) return '房间名称最多 80 个字';
  if (form.description.runes.length > _maxDescriptionLength) {
    return '简介最多 500 个字';
  }
  if (roomSlugProblem(form.slug) case final problem?) return problem;
  if (form.password case SetPassword(password: '')) return '请输入新密码';
  if (roomCapacityProblem(form.capacity) case final problem?) return problem;
  return null;
}

RoomDraft roomDraft(RoomForm form) {
  return RoomDraft(
    name: form.name.trim(),
    description: form.description,
    slug: form.slug.isEmpty ? null : form.slug,
    password: switch (form.password) {
      SetPassword(:final password) => password,
      KeepPassword() || RemovePassword() => null,
    },
    capacity: roomCapacity(form.capacity),
  );
}

RoomPatch roomPatch(RoomListing original, RoomForm form) {
  final name = form.name.trim();
  final capacity = roomCapacity(form.capacity);
  return RoomPatch(
    name: name == original.name ? null : name,
    description: form.description == original.description
        ? null
        : form.description,
    slug: form.slug == (original.slug ?? '') ? null : form.slug,
    password: switch (form.password) {
      SetPassword(:final password) => password,
      RemovePassword() when original.hasPassword => '',
      RemovePassword() || KeepPassword() => null,
    },
    capacity: capacity == original.capacity ? null : capacity,
  );
}
