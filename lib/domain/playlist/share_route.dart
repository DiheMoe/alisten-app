// 服务端的分享 ID 是 16 个随机字节的无填充 base64url；长度不对时服务端直接
// 返回 NOT_FOUND，这里不放行。
final _shareId = RegExp(r'^[A-Za-z0-9_-]{22}$');

bool isShareId(String value) => _shareId.hasMatch(value);

/// 只认恰好两段 `['s', <shareId>]` 的路径。路由检查、深层链接和邀请识别都用它。
String? sharedPlaylistRoute(List<String> segments) {
  if (segments.length != 2 || segments.first != 's') return null;
  return isShareId(segments[1]) ? '/s/${segments[1]}' : null;
}
