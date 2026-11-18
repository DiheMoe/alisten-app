import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';

final class RoomDraft {
  const RoomDraft({
    required this.name,
    required this.description,
    this.slug,
    this.password,
    this.capacity,
  });

  final String name;
  final String description;
  final String? slug;
  final String? password;

  /// 为 null 时服务端用 [AdminRoomList.defaultCapacity]。
  final int? capacity;
}

/// 为 null 的字段保持不变。
final class RoomPatch {
  const RoomPatch({
    this.name,
    this.description,
    this.slug,
    this.password,
    this.capacity,
  });

  final String? name;
  final String? description;

  /// `''` 表示取消别名。
  final String? slug;

  /// `''` 表示取消密码。
  final String? password;

  final int? capacity;

  bool get isEmpty =>
      name == null &&
      description == null &&
      slug == null &&
      password == null &&
      capacity == null;
}

final class AdminRoomList {
  const AdminRoomList({required this.rooms, required this.defaultCapacity});

  final List<RoomListing> rooms;
  final int defaultCapacity;
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

final class GithubAppStatus {
  const GithubAppStatus({
    required this.clientId,
    required this.clientSecretSet,
    required this.callbackUrl,
  });

  /// 为 null 表示没有配置，GitHub 登录没有开启。
  final String? clientId;
  final bool clientSecretSet;
  final String callbackUrl;

  bool get enabled => clientId != null;
}

final class AdminAccountView {
  const AdminAccountView({required this.member, required this.username});

  final Member member;
  final String username;
}

enum MediaOrder { stored, idle, size }

final class StoredTrack {
  const StoredTrack({
    required this.key,
    required this.source,
    required this.link,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.bytes,
    required this.storedAtMs,
    required this.lastPlayedAtMs,
  });

  final String key;
  final TrackSource source;
  final String link;
  final String title;

  /// 不知道歌手时为空字符串。
  final String artist;

  /// 没有封面时为 null。
  final String? coverUrl;
  final int bytes;
  final int storedAtMs;

  /// 从没播放过时为 null。
  final int? lastPlayedAtMs;
}

final class MediaPage {
  const MediaPage({
    required this.items,
    required this.total,
    required this.totalBytes,
    required this.page,
    required this.pageSize,
  });

  final List<StoredTrack> items;
  final int total;
  final int totalBytes;
  final int page;
  final int pageSize;
}

final class MediaRemoval {
  const MediaRemoval({required this.deleted, required this.inUse});

  final List<String> deleted;

  /// 正在房间里播放、没有删除的。
  final List<String> inUse;
}
