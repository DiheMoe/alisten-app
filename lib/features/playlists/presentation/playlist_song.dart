import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const linkInEphemeralRoomText = '临时房间不能点链接里的歌';

/// 与服务端一致：临时房间拒绝链接音源的点歌，但 B 站域名的链接会先被解析成 B 站
/// 音源，照样能点。
String? pickBlockedReason(Track track, RoomKind? kind) {
  if (track.source != TrackSource.link || kind != RoomKind.ephemeral) {
    return null;
  }
  return pickableLink(track.id, kind) == null ? linkInEphemeralRoomText : null;
}

/// 歌手和专辑都是空的时为 null，行里不留空的一行。
String? playlistSongSubtitle(TrackMeta meta) {
  final parts = [meta.artist, meta.album].where((part) => part.isNotEmpty);
  return parts.isEmpty ? null : parts.join(' · ');
}

class PlaylistPickControl extends ConsumerWidget {
  const PlaylistPickControl({
    required this.track,
    required this.title,
    required this.onPick,
    super.key,
  });

  final Track track;
  final String title;
  final PickSong onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(
      roomControllerProvider.select((room) => room.snapshot?.room.kind),
    );
    return PickControl(
      track: track,
      title: title,
      subtle: true,
      blockedReason: pickBlockedReason(track, kind),
      onPick: onPick,
    );
  }
}
