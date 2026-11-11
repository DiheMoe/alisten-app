import 'package:alisten/domain/track/track.dart';

final class MyPlaylist {
  const MyPlaylist({
    required this.id,
    required this.name,
    required this.favorites,
    required this.trackCount,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.coverUrl,
    this.shareId,
  });

  final String id;
  final String name;

  /// “我喜欢”：不能改名或删除，在列表里始终排在最前。
  final bool favorites;
  final int trackCount;
  final int createdAtMs;
  final int updatedAtMs;

  /// 排在最前、有封面的那首歌的封面。
  final String? coverUrl;

  /// 没有分享时为 null。
  final String? shareId;

  MyPlaylist copyWith({String? name, Object? shareId = _unchanged}) {
    return MyPlaylist(
      id: id,
      name: name ?? this.name,
      favorites: favorites,
      trackCount: trackCount,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs,
      coverUrl: coverUrl,
      shareId: identical(shareId, _unchanged)
          ? this.shareId
          : shareId as String?,
    );
  }
}

const _unchanged = Object();

final class SharedPlaylist {
  const SharedPlaylist({
    required this.name,
    required this.favorites,
    required this.ownerName,
    required this.ownerAvatarHash,
    required this.items,
  });

  final String name;
  final bool favorites;
  final String ownerName;

  /// 分享的人没设邮箱时为空字符串。
  final String ownerAvatarHash;

  /// 新加入的在前。
  final List<TrackSummary> items;

  /// 分享歌单没有自己的封面，取第一首有封面的歌的封面。
  String? get coverUrl {
    for (final item in items) {
      if (item.meta.coverUrl.isNotEmpty) return item.meta.coverUrl;
    }
    return null;
  }
}
