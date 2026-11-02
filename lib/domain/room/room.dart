import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/track/track.dart';

enum RoomKind { persistent, ephemeral }

enum RoomPlayMode { sequential, random, rotation }

enum QueueEntryStatus { preparing, ready }

enum RoomActivityKind { added, removed, liked, voted, skipped, failed }

final class RoomInfo {
  const RoomInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
  });

  final String id;
  final String name;
  final String description;
  final RoomKind kind;
}

final class RoomListing {
  const RoomListing({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.kind,
    required this.hasPassword,
    required this.onlineCount,
  });

  final String id;
  final String? slug;
  final String name;
  final String description;
  final RoomKind kind;
  final bool hasPassword;
  final int onlineCount;
}

final class QueueEntry {
  const QueueEntry({
    required this.id,
    required this.track,
    required this.meta,
    required this.requestedBy,
    required this.auto,
    required this.likes,
    required this.status,
  });

  final String id;
  final Track track;
  final TrackMeta meta;
  final Member? requestedBy;
  final bool auto;
  final int likes;
  final QueueEntryStatus status;
}

final class VoteSkipResult {
  const VoteSkipResult({
    required this.votes,
    required this.requiredVotes,
    required this.skipped,
  });

  final int votes;
  final int requiredVotes;
  final bool skipped;
}

final class NowPlaying {
  const NowPlaying({
    required this.entry,
    required this.mediaUrl,
    required this.startedAtMs,
    required this.durationMs,
    required this.gain,
    required this.lyric,
  });

  final QueueEntry entry;
  final String mediaUrl;
  final int startedAtMs;
  final int durationMs;
  final double gain;
  final String lyric;
}

final class RoomSnapshot {
  const RoomSnapshot({
    required this.term,
    required this.seq,
    required this.room,
    required this.playMode,
    required this.nowPlaying,
    required this.pending,
    required this.items,
    required this.members,
    required this.onlineCount,
  });

  final int term;
  final int seq;
  final RoomInfo room;
  final RoomPlayMode playMode;
  final NowPlaying? nowPlaying;
  final QueueEntry? pending;
  final List<QueueEntry> items;
  final List<Member> members;
  final int onlineCount;

  RoomSnapshot copyWith({
    required int term,
    required int seq,
    RoomInfo? room,
    RoomPlayMode? playMode,
    Object? nowPlaying = _unchanged,
    Object? pending = _unchanged,
    List<QueueEntry>? items,
    List<Member>? members,
    int? onlineCount,
  }) {
    return RoomSnapshot(
      term: term,
      seq: seq,
      room: room ?? this.room,
      playMode: playMode ?? this.playMode,
      nowPlaying: identical(nowPlaying, _unchanged)
          ? this.nowPlaying
          : nowPlaying as NowPlaying?,
      pending: identical(pending, _unchanged)
          ? this.pending
          : pending as QueueEntry?,
      items: items ?? this.items,
      members: members ?? this.members,
      onlineCount: onlineCount ?? this.onlineCount,
    );
  }
}

const _unchanged = Object();

sealed class RoomEvent {
  const RoomEvent({required this.term, required this.seq});

  final int term;
  final int seq;
}

final class PlaybackUpdatedEvent extends RoomEvent {
  const PlaybackUpdatedEvent({
    required super.term,
    required super.seq,
    required this.nowPlaying,
  });

  final NowPlaying? nowPlaying;
}

final class QueueUpdatedEvent extends RoomEvent {
  const QueueUpdatedEvent({
    required super.term,
    required super.seq,
    required this.pending,
    required this.items,
  });

  final QueueEntry? pending;
  final List<QueueEntry> items;
}

final class MembersUpdatedEvent extends RoomEvent {
  const MembersUpdatedEvent({
    required super.term,
    required super.seq,
    required this.members,
    required this.onlineCount,
  });

  final List<Member> members;
  final int onlineCount;
}

final class SettingsUpdatedEvent extends RoomEvent {
  const SettingsUpdatedEvent({
    required super.term,
    required super.seq,
    required this.playMode,
  });

  final RoomPlayMode playMode;
}

final class RoomUpdatedEvent extends RoomEvent {
  const RoomUpdatedEvent({
    required super.term,
    required super.seq,
    required this.name,
    required this.description,
  });

  final String name;
  final String description;
}

final class ChatMessageEvent extends RoomEvent {
  const ChatMessageEvent({
    required super.term,
    required super.seq,
    required this.member,
    required this.content,
    required this.sentAtMs,
  });

  final Member member;
  final String content;
  final int sentAtMs;
}

/// 客户端无法解析的事件。从这里开始房间状态未知，直到重新同步房间。
final class UnreadableRoomEvent extends RoomEvent {
  const UnreadableRoomEvent({required super.term, required super.seq});
}

final class RoomActivityEvent extends RoomEvent {
  const RoomActivityEvent({
    required super.term,
    required super.seq,
    required this.kind,
    required this.message,
    this.member,
    this.entry,
    this.votes,
    this.requiredVotes,
  });

  final RoomActivityKind kind;
  final String message;
  final Member? member;
  final QueueEntry? entry;
  final int? votes;
  final int? requiredVotes;
}
