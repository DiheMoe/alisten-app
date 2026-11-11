import 'package:alisten/domain/member/member.dart';

final class RoomDraft {
  const RoomDraft({
    required this.name,
    required this.description,
    this.slug,
    this.password,
  });

  final String name;
  final String description;
  final String? slug;
  final String? password;
}

/// 为 null 的字段保持不变。
final class RoomPatch {
  const RoomPatch({this.name, this.description, this.slug, this.password});

  final String? name;
  final String? description;

  /// `''` 表示取消别名。
  final String? slug;

  /// `''` 表示取消密码。
  final String? password;

  bool get isEmpty =>
      name == null && description == null && slug == null && password == null;
}

final class ApiKeyStatus {
  const ApiKeyStatus({required this.generated, required this.createdAtMs});

  final bool generated;

  /// 还没有生成时为 0。
  final int createdAtMs;
}

enum LoginSource { netease, qq, bilibili }

/// QQ 音乐的扫码方式：QQ 或微信。
enum QqLoginType { qq, wx }

final class SourceAccount {
  const SourceAccount({
    required this.id,
    this.name,
    this.vip,
    required this.verified,
  });

  final String id;
  final String? name;
  final bool? vip;

  final bool verified;
}

final class SourceAccountStatus {
  const SourceAccountStatus({required this.saved, this.account});

  final bool saved;

  /// 已保存登录信息、但没能识别出账号时为 null。
  final SourceAccount? account;
}

/// [key] 是查询扫码结果的凭据，只交给发起扫码的控制器，不得进入状态或日志。
final class QrLoginTicket {
  const QrLoginTicket({
    required this.key,
    required this.qrImage,
    required this.expiresAtMs,
  });

  final String key;

  /// `data:` URI 或 https 地址。
  final String qrImage;

  /// 服务端时间。
  final int expiresAtMs;
}

enum QrCheckState { waiting, scanned, success, expired, failed }

final class QrLoginCheck {
  const QrLoginCheck({required this.state, required this.message});

  final QrCheckState state;

  final String message;
}

final class YoutubeCookieStatus {
  const YoutubeCookieStatus({required this.saved, required this.updatedAtMs});

  final bool saved;

  /// 没有保存时为 0。
  final int updatedAtMs;
}

final class AdminAccountView {
  const AdminAccountView({required this.member, required this.username});

  final Member member;
  final String username;
}
