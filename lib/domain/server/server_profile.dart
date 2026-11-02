import 'package:alisten/domain/server/server_origin.dart';

const defaultBrandName = 'Alisten';

// 与服务端对品牌名“看得见”的判断一致：字母、组合符号、数字、标点和符号。
final _visible = RegExp(r'[\p{L}\p{M}\p{N}\p{P}\p{S}]', unicode: true);

bool hasVisibleCharacter(String text) => _visible.hasMatch(text);

final class ServerProfile {
  factory ServerProfile({
    required String origin,
    required String brandName,
    required int addedAtMs,
  }) {
    if (!_isCanonical(origin)) {
      throw ArgumentError.value(origin, 'origin', 'Must be a canonical origin');
    }
    return ServerProfile._(
      id: serverIdFor(origin),
      origin: origin,
      brandName: brandName,
      addedAtMs: addedAtMs,
    );
  }

  const ServerProfile._({
    required this.id,
    required this.origin,
    required this.brandName,
    required this.addedAtMs,
  });

  final String id;
  final String origin;
  final String brandName;
  final int addedAtMs;

  String get authority => originAuthority(origin);

  String get displayName =>
      hasVisibleCharacter(brandName) ? brandName : authority;

  ServerProfile withBrandName(String brandName) {
    return ServerProfile._(
      id: id,
      origin: origin,
      brandName: brandName,
      addedAtMs: addedAtMs,
    );
  }

  Map<String, Object?> toJson() => {
    'origin': origin,
    'brandName': brandName,
    'addedAtMs': addedAtMs,
  };

  static ServerProfile? tryParse(Object? json) {
    if (json
        case {
          'origin': final String origin,
          'brandName': final String brandName,
          'addedAtMs': final int addedAtMs,
        }
        when _isCanonical(origin)) {
      return ServerProfile(
        origin: origin,
        brandName: brandName,
        addedAtMs: addedAtMs,
      );
    }
    return null;
  }

  static bool _isCanonical(String origin) {
    return switch (parseServerOrigin(origin, allowCleartext: true)) {
      ValidOrigin(origin: final canonical) => canonical == origin,
      InvalidOrigin() => false,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ServerProfile &&
        other.id == id &&
        other.origin == origin &&
        other.brandName == brandName &&
        other.addedAtMs == addedAtMs;
  }

  @override
  int get hashCode => Object.hash(id, origin, brandName, addedAtMs);
}
