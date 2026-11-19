final class Member {
  const Member({
    required this.id,
    required this.name,
    required this.avatarHash,
  });

  final String id;
  final String name;

  final String avatarHash;

  String? get avatarUrl => avatarUrlFor(avatarHash);
}

/// 头像不论画多大都取同一张图，边长是最大的头像（64 点）的两倍：同一个人的头像
/// 只下载、解码一次，换个地方显示第一帧就有图；各台设备请求的也是同一张。
const avatarPixels = 128;

String? avatarUrlFor(String avatarHash) {
  if (avatarHash.isEmpty) return null;
  // 没设头像时要 404 而不是生成的图案：各镜像生成的图案不同，界面改显示首字。
  return 'https://www.gravatar.com/avatar/$avatarHash?d=404&s=$avatarPixels';
}
