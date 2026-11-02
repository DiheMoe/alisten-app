import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';

Member toDomainMember(protocol.Member member) {
  return Member(
    id: member.id,
    name: member.name,
    avatarHash: member.avatarHash,
  );
}

TrackSource toDomainSource(protocol.Source source) {
  return switch (source) {
    protocol.Source.netease => TrackSource.netease,
    protocol.Source.qq => TrackSource.qq,
    protocol.Source.bilibili => TrackSource.bilibili,
    protocol.Source.link => TrackSource.link,
  };
}

protocol.Source toProtocolSource(TrackSource source) {
  return switch (source) {
    TrackSource.netease => protocol.Source.netease,
    TrackSource.qq => protocol.Source.qq,
    TrackSource.bilibili => protocol.Source.bilibili,
    TrackSource.link => protocol.Source.link,
  };
}

RoomPlayMode toDomainPlayMode(protocol.PlayMode mode) {
  return switch (mode) {
    protocol.PlayMode.sequential => RoomPlayMode.sequential,
    protocol.PlayMode.random => RoomPlayMode.random,
    protocol.PlayMode.rotation => RoomPlayMode.rotation,
  };
}

protocol.PlayMode toProtocolPlayMode(RoomPlayMode mode) {
  return switch (mode) {
    RoomPlayMode.sequential => protocol.PlayMode.sequential,
    RoomPlayMode.random => protocol.PlayMode.random,
    RoomPlayMode.rotation => protocol.PlayMode.rotation,
  };
}

RoomKind toDomainRoomKind(protocol.RoomKind kind) {
  return switch (kind) {
    protocol.RoomKind.persistent => RoomKind.persistent,
    protocol.RoomKind.ephemeral => RoomKind.ephemeral,
  };
}

RoomListing toDomainRoomListing(protocol.RoomListing room) {
  return RoomListing(
    id: room.id,
    slug: room.slug,
    name: room.name,
    description: room.description,
    kind: toDomainRoomKind(room.kind),
    hasPassword: room.hasPassword,
    onlineCount: room.onlineCount,
  );
}

final _netEaseCoverHost = RegExp(r'^p[1-4]\.music\.126\.net$');

/// 音源的封面常是 HTTP 地址，而 Release 构建不加载明文地址。已知同样提供 HTTPS
/// 的主机改用 HTTPS；其他 HTTP 地址原样保留，会加载失败。
String secureCoverUrl(String url) {
  const insecure = 'http://';
  if (!url.startsWith(insecure)) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.hasPort) return url;
  final host = uri.host.toLowerCase();
  final secure =
      _netEaseCoverHost.hasMatch(host) ||
      host == 'y.gtimg.cn' ||
      host.endsWith('.hdslb.com');
  return secure ? 'https://${url.substring(insecure.length)}' : url;
}

Track toDomainTrack(protocol.Track track) {
  return Track(source: toDomainSource(track.source), id: track.id);
}

protocol.Track toProtocolTrack(Track track) {
  return protocol.Track(source: toProtocolSource(track.source), id: track.id);
}

TrackMeta toDomainTrackMeta(protocol.TrackMeta meta) {
  return TrackMeta(
    title: meta.title,
    artist: meta.artist,
    album: meta.album,
    coverUrl: secureCoverUrl(meta.coverUrl),
    pageUrl: meta.pageUrl,
    durationMs: meta.durationMs,
  );
}

QueueEntry toDomainEntry(protocol.Entry entry) {
  return QueueEntry(
    id: entry.id,
    track: toDomainTrack(entry.track),
    meta: toDomainTrackMeta(entry.meta),
    requestedBy: entry.by == null ? null : toDomainMember(entry.by!),
    auto: entry.auto,
    likes: entry.likes,
    status: switch (entry.status) {
      protocol.EntryStatus.preparing => QueueEntryStatus.preparing,
      protocol.EntryStatus.ready => QueueEntryStatus.ready,
    },
  );
}

NowPlaying toDomainNowPlaying(protocol.NowPlaying nowPlaying) {
  return NowPlaying(
    entry: toDomainEntry(nowPlaying.entry),
    mediaUrl: nowPlaying.mediaUrl,
    startedAtMs: nowPlaying.startedAtMs,
    durationMs: nowPlaying.durationMs,
    gain: nowPlaying.gain,
    lyric: nowPlaying.lyric,
  );
}

RoomSnapshot toDomainSnapshot(protocol.RoomSnapshot snapshot) {
  return RoomSnapshot(
    term: snapshot.term,
    seq: snapshot.seq,
    room: RoomInfo(
      id: snapshot.room.id,
      name: snapshot.room.name,
      description: snapshot.room.description,
      kind: toDomainRoomKind(snapshot.room.kind),
    ),
    playMode: toDomainPlayMode(snapshot.playMode),
    nowPlaying: snapshot.nowPlaying == null
        ? null
        : toDomainNowPlaying(snapshot.nowPlaying!),
    pending: snapshot.pending == null ? null : toDomainEntry(snapshot.pending!),
    items: snapshot.items.map(toDomainEntry).toList(growable: false),
    members: snapshot.members.sessions
        .map(toDomainMember)
        .toList(growable: false),
    onlineCount: snapshot.members.onlineCount,
  );
}

RoomEvent toDomainEvent(
  String type,
  int term,
  int seq,
  Map<String, Object?> data,
) {
  return switch (type) {
    protocol.RoomEventTypes.playbackUpdated => PlaybackUpdatedEvent(
      term: term,
      seq: seq,
      nowPlaying: switch (protocol.PlaybackUpdated.fromJson(data).nowPlaying) {
        final nowPlaying? => toDomainNowPlaying(nowPlaying),
        null => null,
      },
    ),
    protocol.RoomEventTypes.queueUpdated => _queueUpdated(term, seq, data),
    protocol.RoomEventTypes.membersUpdated => _membersUpdated(term, seq, data),
    protocol.RoomEventTypes.settingsUpdated => SettingsUpdatedEvent(
      term: term,
      seq: seq,
      playMode: toDomainPlayMode(
        protocol.SettingsUpdated.fromJson(data).playMode,
      ),
    ),
    protocol.RoomEventTypes.roomUpdated => _roomUpdated(term, seq, data),
    protocol.RoomEventTypes.chatMessage => _chatMessage(term, seq, data),
    protocol.RoomEventTypes.roomActivity => _roomActivity(term, seq, data),
    _ => throw FormatException('Unknown room event type: $type'),
  };
}

QueueUpdatedEvent _queueUpdated(int term, int seq, Map<String, Object?> data) {
  final event = protocol.QueueUpdated.fromJson(data);
  return QueueUpdatedEvent(
    term: term,
    seq: seq,
    pending: event.pending == null ? null : toDomainEntry(event.pending!),
    items: event.items.map(toDomainEntry).toList(growable: false),
  );
}

MembersUpdatedEvent _membersUpdated(
  int term,
  int seq,
  Map<String, Object?> data,
) {
  final event = protocol.Members.fromJson(data);
  return MembersUpdatedEvent(
    term: term,
    seq: seq,
    members: event.sessions.map(toDomainMember).toList(growable: false),
    onlineCount: event.onlineCount,
  );
}

RoomUpdatedEvent _roomUpdated(int term, int seq, Map<String, Object?> data) {
  final event = protocol.RoomUpdated.fromJson(data);
  return RoomUpdatedEvent(
    term: term,
    seq: seq,
    name: event.name,
    description: event.description,
  );
}

ChatMessageEvent _chatMessage(int term, int seq, Map<String, Object?> data) {
  final event = protocol.ChatMessage.fromJson(data);
  return ChatMessageEvent(
    term: term,
    seq: seq,
    member: toDomainMember(event.member),
    content: event.content,
    sentAtMs: event.sentAtMs,
  );
}

RoomActivityEvent _roomActivity(int term, int seq, Map<String, Object?> data) {
  final event = protocol.RoomActivity.fromJson(data);
  return RoomActivityEvent(
    term: term,
    seq: seq,
    kind: switch (event.kind) {
      protocol.ActivityKind.added => RoomActivityKind.added,
      protocol.ActivityKind.removed => RoomActivityKind.removed,
      protocol.ActivityKind.liked => RoomActivityKind.liked,
      protocol.ActivityKind.voted => RoomActivityKind.voted,
      protocol.ActivityKind.skipped => RoomActivityKind.skipped,
      protocol.ActivityKind.failed => RoomActivityKind.failed,
    },
    message: event.message,
    member: event.member == null ? null : toDomainMember(event.member!),
    entry: event.entry == null ? null : toDomainEntry(event.entry!),
    votes: event.votes,
    requiredVotes: event.requiredValue,
  );
}

TrackSummary toDomainTrackSummary(protocol.TrackSummary summary) {
  return TrackSummary(
    track: toDomainTrack(summary.track),
    meta: toDomainTrackMeta(summary.meta),
  );
}

PlaylistSummary toDomainPlaylistSummary(protocol.PlaylistSummary summary) {
  return PlaylistSummary(
    source: toDomainSource(summary.source),
    id: summary.id,
    name: summary.name,
    coverUrl: secureCoverUrl(summary.coverUrl),
    creator: summary.creator,
    description: summary.description,
    trackCount: summary.trackCount,
    playCount: summary.playCount,
  );
}
