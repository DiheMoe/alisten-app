// Gravatar 提供的最大图片边长，单位为像素。
const _gravatarMaxSize = 2048;

final class Member {
  const Member({
    required this.id,
    required this.name,
    required this.avatarHash,
  });

  final String id;
  final String name;

  final String avatarHash;

  /// 固定按 [size] 的两倍取图：在大多数屏幕上足够清晰，
  /// 各台设备请求的也是同一张图片。
  String? avatarUrl(double size) {
    if (avatarHash.isEmpty) return null;
    final pixels = (size * 2).round().clamp(1, _gravatarMaxSize);
    return 'https://www.gravatar.com/avatar/$avatarHash?d=identicon&s=$pixels';
  }
}
