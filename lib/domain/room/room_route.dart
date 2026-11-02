const linkRoomSections = {'queue', 'chat', 'search'};

final _roomRef = RegExp(
  r'^(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[a-z0-9-]{1,32})$',
);
final _playlistId = RegExp(r'^[0-9]+$');

bool isRoomRef(String value) => _roomRef.hasMatch(value);

String? roomRoute(List<String> segments, {required Set<String> sections}) {
  if (segments.length < 2 || segments.first != 'r') return null;
  final room = segments[1];
  if (!isRoomRef(room)) return null;
  if (segments.length == 2) return '/r/$room';
  if (segments.length == 3 && sections.contains(segments[2])) {
    return '/r/$room/${segments[2]}';
  }
  if (segments.length == 5 &&
      segments[2] == 'playlists' &&
      segments[3] == 'netease' &&
      _playlistId.hasMatch(segments[4])) {
    return '/r/$room/playlists/netease/${segments[4]}';
  }
  return null;
}
