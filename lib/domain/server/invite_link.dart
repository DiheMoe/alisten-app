import 'package:alisten/domain/playlist/share_route.dart';
import 'package:alisten/domain/room/room_route.dart';
import 'package:alisten/domain/server/server_origin.dart';

enum SiteLinkKind { room, sharedPlaylist }

final class InviteLink {
  const InviteLink({
    required this.origin,
    required this.authority,
    required this.kind,
    required this.route,
    this.roomRef,
  }) : assert((kind == SiteLinkKind.room) == (roomRef != null));

  /// [parseServerOrigin] 给出的规整写法。
  final String origin;
  final String authority;
  final SiteLinkKind kind;

  /// 只有房间链接有。
  final String? roomRef;
  final String route;
}

/// 路径形如房间页面或分享歌单就算，不论是否为 Alisten 网站：例如 reddit 的
/// `/r/<小写名字>` 也算，只有询问那个服务器才知道。
InviteLink? parseInviteLink(String link, {required bool allowCleartext}) {
  final uri = Uri.tryParse(link);
  if (uri == null || !uri.hasAuthority) return null;
  final origin = switch (parseServerOrigin(
    '${uri.scheme}://${uri.authority}',
    allowCleartext: allowCleartext,
  )) {
    ValidOrigin(:final origin) => origin,
    InvalidOrigin() => null,
  };
  if (origin == null) return null;
  final segments = uri.pathSegments;
  final room = roomRoute(segments, sections: linkRoomSections);
  final route = room ?? sharedPlaylistRoute(segments);
  if (route == null) return null;
  return InviteLink(
    origin: origin,
    authority: originAuthority(origin),
    kind: room == null ? SiteLinkKind.sharedPlaylist : SiteLinkKind.room,
    roomRef: room == null ? null : segments[1],
    route: route,
  );
}
