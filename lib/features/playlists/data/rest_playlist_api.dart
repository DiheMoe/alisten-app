import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/http.gen.dart' as http;
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';

const _logSource = 'playlists';

// 服务端要先从网易云取回整个歌单，每次向网易云请求最多等 30 秒，大歌单要请求
// 好几次；客户端先断开会让服务端已经创建的歌单变成结果未知。
const _platformImportTimeout = Duration(seconds: 45);

final class RestPlaylistApi implements PlaylistApi {
  const RestPlaylistApi(this._transport, this._memberTokenReader);

  final ApiTransport _transport;
  final Future<String?> Function() _memberTokenReader;

  @override
  Future<List<MyPlaylist>> listMine() {
    return _request(
      http.RestEndpoints.listMyPlaylists,
      decode: (json) =>
          protocol.ListMyPlaylistsResponse.fromJson(json).items
              .map(_playlist)
              .toList(growable: false),
    );
  }

  @override
  Future<MyPlaylist> create(String name) {
    return _request(
      http.RestEndpoints.createMyPlaylist,
      body: protocol.CreateMyPlaylistRequest(name: name).toJson(),
      decode: (json) => _playlist(protocol.MyPlaylist.fromJson(json)),
    );
  }

  @override
  Future<void> rename(String id, String name) {
    return _send(
      http.RestEndpoints.renameMyPlaylist,
      pathParameters: {'id': id},
      body: protocol.RenameMyPlaylistRequest(name: name).toJson(),
    );
  }

  @override
  Future<void> delete(String id) {
    return _send(
      http.RestEndpoints.deleteMyPlaylist,
      pathParameters: {'id': id},
    );
  }

  @override
  Future<List<TrackSummary>> items(String id) {
    return _request(
      http.RestEndpoints.listMyPlaylistItems,
      pathParameters: {'id': id},
      decode: (json) =>
          protocol.ListMyPlaylistItemsResponse.fromJson(json).items
              .map(_item)
              .toList(growable: false),
    );
  }

  @override
  Future<void> add(String id, Track track) {
    return _request(
      http.RestEndpoints.addMyPlaylistItem,
      pathParameters: {'id': id},
      body: protocol.AddMyPlaylistItemRequest(track: toProtocolTrack(track))
          .toJson(),
      decode: (json) {
        protocol.AddMyPlaylistItemResponse.fromJson(json);
      },
    );
  }

  @override
  Future<void> remove(String id, List<Track> tracks) {
    return _send(
      http.RestEndpoints.removeMyPlaylistItems,
      pathParameters: {'id': id},
      body: protocol.RemoveMyPlaylistItemsRequest(
        tracks: tracks.map(toProtocolTrack).toList(growable: false),
      ).toJson(),
    );
  }

  @override
  Future<int> copy({
    required String from,
    required String to,
    required List<Track> tracks,
  }) {
    return _request(
      http.RestEndpoints.copyMyPlaylistItems,
      pathParameters: {'id': to},
      body: protocol.CopyMyPlaylistItemsRequest(
        from: from,
        tracks: tracks.map(toProtocolTrack).toList(growable: false),
      ).toJson(),
      decode: (json) =>
          protocol.CopyMyPlaylistItemsResponse.fromJson(json).added,
    );
  }

  @override
  Future<void> move(String id, List<Track> tracks, {Track? before}) {
    return _send(
      http.RestEndpoints.moveMyPlaylistItems,
      pathParameters: {'id': id},
      body: protocol.MoveMyPlaylistItemsRequest(
        tracks: tracks.map(toProtocolTrack).toList(growable: false),
        before: before == null ? null : toProtocolTrack(before),
      ).toJson(),
    );
  }

  @override
  Future<Set<String>> containing(Track track) {
    return _request(
      http.RestEndpoints.listMyTrackPlaylists,
      body: protocol.ListMyTrackPlaylistsRequest(track: toProtocolTrack(track))
          .toJson(),
      decode: (json) =>
          protocol.ListMyTrackPlaylistsResponse.fromJson(json).playlistIds
              .toSet(),
    );
  }

  @override
  Future<ImportedPlaylist> importFile(
    String name,
    List<PlaylistFileTrack> tracks,
  ) {
    return _request(
      http.RestEndpoints.importMyPlaylist,
      body: protocol.ImportMyPlaylistRequest(
        name: name,
        tracks: tracks.map(_importedTrack).toList(growable: false),
      ).toJson(),
      decode: (json) {
        final response = protocol.ImportMyPlaylistResponse.fromJson(json);
        return (
          playlist: _playlist(response.playlist),
          imported: response.imported,
        );
      },
    );
  }

  @override
  Future<({TrackSource source, String playlistId})> resolveLink(String link) {
    return _request(
      http.RestEndpoints.resolveMyPlaylistLink,
      body: protocol.ResolveMyPlaylistLinkRequest(link: link).toJson(),
      decode: (json) {
        final response = protocol.ResolveMyPlaylistLinkResponse.fromJson(json);
        return (
          source: toDomainSource(response.source),
          playlistId: response.playlistId,
        );
      },
    );
  }

  @override
  Future<ImportedPlaylist> importPlatform({
    required String name,
    required TrackSource source,
    required String playlistId,
  }) {
    return _request(
      http.RestEndpoints.importMyPlatformPlaylist,
      timeout: _platformImportTimeout,
      body: protocol.ImportMyPlatformPlaylistRequest(
        name: name,
        playlistId: playlistId,
        source: toProtocolSource(source),
      ).toJson(),
      decode: (json) {
        final response = protocol.ImportMyPlatformPlaylistResponse.fromJson(
          json,
        );
        return (
          playlist: _playlist(response.playlist),
          imported: response.imported,
        );
      },
    );
  }

  @override
  Future<String> share(String id) {
    return _request(
      http.RestEndpoints.shareMyPlaylist,
      pathParameters: {'id': id},
      body: const protocol.ShareMyPlaylistRequest().toJson(),
      decode: (json) => protocol.ShareMyPlaylistResponse.fromJson(json).shareId,
    );
  }

  @override
  Future<void> unshare(String id) {
    return _send(
      http.RestEndpoints.unshareMyPlaylist,
      pathParameters: {'id': id},
    );
  }

  @override
  Future<SharedPlaylist> shared(String shareId) {
    return _request(
      http.RestEndpoints.getSharedPlaylist,
      pathParameters: {'shareId': shareId},
      decode: (json) {
        final shared = protocol.SharedPlaylist.fromJson(json);
        return SharedPlaylist(
          name: shared.name,
          favorites: shared.favorites,
          ownerName: shared.ownerName,
          ownerAvatarHash: shared.ownerAvatarHash,
          items: shared.items.map(_item).toList(growable: false),
        );
      },
    );
  }

  @override
  Future<MyPlaylist> copyShared(String shareId, String name) {
    return _request(
      http.RestEndpoints.copySharedPlaylist,
      pathParameters: {'shareId': shareId},
      body: protocol.CopySharedPlaylistRequest(name: name).toJson(),
      decode: (json) => _playlist(protocol.MyPlaylist.fromJson(json)),
    );
  }

  // 读不出 token 与没有 token 一样：请求没有发出，不是结果未知。
  Future<String?> _tokenFor(http.RestEndpoint endpoint) async {
    if (endpoint.auth != http.HttpAuth.member) return null;
    try {
      return await _memberTokenReader();
    } on Object {
      throw const ApiException(
        code: LocalErrorCodes.noToken,
        message: identityUnreadableText,
        status: null,
      );
    }
  }

  // 成功时没有回复体（204）的接口。
  Future<void> _send(
    http.RestEndpoint endpoint, {
    Map<String, String> pathParameters = const {},
    Map<String, Object?> body = const {},
  }) async {
    final token = await _tokenFor(endpoint);
    await _transport.execute(
      endpoint,
      pathParameters: pathParameters,
      body: body,
      token: token,
    );
  }

  Future<T> _request<T>(
    http.RestEndpoint endpoint, {
    required T Function(Map<String, Object?> json) decode,
    Duration? timeout,
    Map<String, String> pathParameters = const {},
    Map<String, Object?> body = const {},
  }) async {
    final token = await _tokenFor(endpoint);
    final response = await _transport.execute(
      endpoint,
      pathParameters: pathParameters,
      body: body,
      token: token,
      timeout: timeout,
    );
    try {
      if (response is! Map<String, Object?>) {
        throw const FormatException('Response must be an object');
      }
      return decode(response);
    } on FormatException {
      AppLog.debug(
        _logSource,
        'response not understood',
        type: endpoint.name,
        code: LocalErrorCodes.protocolMismatch,
      );
      throw ApiException.protocolMismatch(endpoint.successStatus);
    }
  }
}

MyPlaylist _playlist(protocol.MyPlaylist playlist) {
  final coverUrl = playlist.coverUrl;
  return MyPlaylist(
    id: playlist.id,
    name: playlist.name,
    favorites: playlist.favorites,
    trackCount: playlist.trackCount,
    createdAtMs: playlist.createdAtMs,
    updatedAtMs: playlist.updatedAtMs,
    coverUrl: coverUrl == null ? null : secureCoverUrl(coverUrl),
    shareId: playlist.shareId,
  );
}

TrackSummary _item(protocol.MyPlaylistItem item) {
  return TrackSummary(
    track: toDomainTrack(item.track),
    meta: toDomainTrackMeta(item.meta),
  );
}

// 为 null 的项由生成的 `toJson` 省略，不写进请求体。
protocol.ImportedTrack _importedTrack(PlaylistFileTrack track) {
  return protocol.ImportedTrack(
    track: toProtocolTrack(track.track),
    title: track.title,
    artist: track.artist,
    album: track.album,
    durationMs: track.durationMs,
    coverUrl: track.coverUrl,
    pageUrl: track.pageUrl,
  );
}
