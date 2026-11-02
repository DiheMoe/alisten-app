import 'package:alisten/domain/room/room_route.dart';
import 'package:alisten/domain/server/server_origin.dart';

final class InviteLink {
  const InviteLink({
    required this.origin,
    required this.authority,
    required this.roomRef,
    required this.route,
  });

  /// [parseServerOrigin] 给出的规整写法。
  final String origin;
  final String authority;
  final String roomRef;
  final String route;
}

/// 路径形如房间页面就算，不论是否为 Alisten 网站：例如 reddit 的
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
  final route = roomRoute(uri.pathSegments, sections: linkRoomSections);
  if (route == null) return null;
  return InviteLink(
    origin: origin,
    authority: originAuthority(origin),
    roomRef: uri.pathSegments[1],
    route: route,
  );
}
