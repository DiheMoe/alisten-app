import 'package:alisten/core/protocol/protocol_runtime.dart'
    show isValidLink, normalizeLink;
import 'package:alisten/domain/room/room.dart';

String? linkOf(String input) {
  final link = input.trim();
  return isValidLink(link) ? normalizeLink(link) : null;
}

/// [host] 须为小写。服务端把这些域名的链接识别成 B 站音源的歌。
bool isBilibiliHost(String host) {
  return host == 'b23.tv' ||
      host == 'bilibili.com' ||
      host.endsWith('.bilibili.com');
}

String? pickableLink(String input, RoomKind? kind) {
  final link = linkOf(input);
  if (link == null || kind == null) return null;
  if (kind == RoomKind.persistent) return link;
  return isBilibiliHost(Uri.parse(link).host.toLowerCase()) ? link : null;
}
