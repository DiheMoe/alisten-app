import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/search_page.dart';
import 'package:alisten/domain/track/track.dart';

/// 失败时抛出 [RoomRequestException]。
final class RoomCommands {
  RoomCommands(this._transport);

  final RoomTransport _transport;

  Future<RoomSnapshot> sync() {
    return _request(
      protocol.RoomRequestTypes.roomSync,
      const protocol.RoomSyncRequest().toJson(),
      (json) => toDomainSnapshot(protocol.RoomSyncResponse.fromJson(json).room),
    );
  }

  Future<QueueEntry> addTrack(Track track) {
    return _request(
      protocol.RoomRequestTypes.queueAdd,
      protocol.QueueAddRequest(track: toProtocolTrack(track)).toJson(),
      (json) => toDomainEntry(protocol.QueueAddResponse.fromJson(json).entry),
    );
  }

  Future<void> removeEntry(String entryId) {
    return _request(
      protocol.RoomRequestTypes.queueRemove,
      protocol.QueueRemoveRequest(entryId: entryId).toJson(),
      _ignore,
    );
  }

  Future<int> likeEntry(String entryId) {
    return _request(
      protocol.RoomRequestTypes.queueLike,
      protocol.QueueLikeRequest(entryId: entryId).toJson(),
      (json) => protocol.QueueLikeResponse.fromJson(json).likes,
    );
  }

  Future<VoteSkipResult> voteSkip() {
    return _request(
      protocol.RoomRequestTypes.playbackVoteSkip,
      const protocol.PlaybackVoteSkipRequest().toJson(),
      (json) {
        final response = protocol.PlaybackVoteSkipResponse.fromJson(json);
        return VoteSkipResult(
          votes: response.votes,
          requiredVotes: response.requiredValue,
          skipped: response.skipped,
        );
      },
    );
  }

  Future<void> setPlayMode(RoomPlayMode mode) {
    return _request(
      protocol.RoomRequestTypes.settingsSetPlayMode,
      protocol.SettingsSetPlayModeRequest(playMode: toProtocolPlayMode(mode))
          .toJson(),
      _ignore,
    );
  }

  Future<void> sendChat(String content) {
    return _request(
      protocol.RoomRequestTypes.chatSend,
      protocol.ChatSendRequest(content: content).toJson(),
      _ignore,
    );
  }

  Future<SearchPage<TrackSummary>> searchTracks({
    required TrackSource source,
    required String keyword,
    required int page,
    int pageSize = 20,
  }) {
    return _request(
      protocol.RoomRequestTypes.searchTracks,
      protocol.SearchTracksRequest(
        source: toProtocolSource(source),
        keyword: keyword,
        page: page,
        pageSize: pageSize,
      ).toJson(),
      (json) {
        final response = protocol.SearchTracksResponse.fromJson(json);
        return SearchPage(
          items: response.items
              .map(toDomainTrackSummary)
              .toList(growable: false),
          total: response.total,
        );
      },
    );
  }

  Future<SearchPage<PlaylistSummary>> searchPlaylists({
    required TrackSource source,
    required String keyword,
    required int page,
    int pageSize = 20,
  }) {
    return _request(
      protocol.RoomRequestTypes.searchPlaylists,
      protocol.SearchPlaylistsRequest(
        source: toProtocolSource(source),
        keyword: keyword,
        page: page,
        pageSize: pageSize,
      ).toJson(),
      (json) {
        final response = protocol.SearchPlaylistsResponse.fromJson(json);
        return SearchPage(
          items: response.items
              .map(toDomainPlaylistSummary)
              .toList(growable: false),
          total: response.total,
        );
      },
    );
  }

  Future<List<TrackSummary>> playlistTracks({
    required TrackSource source,
    required String playlistId,
  }) {
    return _request(
      protocol.RoomRequestTypes.playlistTracks,
      protocol.PlaylistTracksRequest(
        source: toProtocolSource(source),
        playlistId: playlistId,
      ).toJson(),
      (json) =>
          protocol.PlaylistTracksResponse.fromJson(json).items
              .map(toDomainTrackSummary)
              .toList(growable: false),
    );
  }

  Future<List<TrackSummary>> recommendations() {
    return _request(
      protocol.RoomRequestTypes.recommendList,
      const protocol.RecommendListRequest().toJson(),
      (json) =>
          protocol.RecommendListResponse.fromJson(json).items
              .map(toDomainTrackSummary)
              .toList(growable: false),
    );
  }

  Future<T> _request<T>(
    String type,
    Map<String, Object?> data,
    T Function(Map<String, Object?> json) decode,
  ) async {
    final response = await _transport.request(type, data);
    try {
      return decode(response);
    } on FormatException {
      throw RoomRequestException.undecodable(type);
    }
  }
}

void _ignore(Map<String, Object?> json) {}
