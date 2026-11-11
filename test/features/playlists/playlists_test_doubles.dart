import 'dart:async';
import 'dart:ui' show Rect;

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/playlist/track_order.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../lobby/lobby_test_doubles.dart';

const shareIdA = 'AbCdEfGhIjKlMnOpQrStUv';
const shareIdB = 'abc-DEF_ghi-JKL_mno-PQ';
const accountToken = 'account-token';
const testAccount = Account(username: 'mao', github: false);

/// 2026-11-11 本地时间 09:30。
final testNowMs = DateTime(2026, 11, 11, 9, 30).millisecondsSinceEpoch;

ApiException apiError(
  String code, {
  String message = '服务端消息',
  int status = 409,
  Duration? retryAfter,
}) {
  return ApiException(
    code: code,
    message: message,
    status: status,
    retryAfter: retryAfter,
  );
}

const networkError = ApiException(
  code: LocalErrorCodes.network,
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

TrackSummary song(
  String id, {
  String? title,
  TrackSource source = TrackSource.netease,
  String artist = '歌手',
  String album = '专辑',
  String coverUrl = '',
}) {
  return TrackSummary(
    track: Track(source: source, id: id),
    meta: TrackMeta(
      title: title ?? '歌$id',
      artist: artist,
      album: album,
      coverUrl: coverUrl,
      pageUrl: 'https://example.com/$id',
      durationMs: 180000,
    ),
  );
}

MyPlaylist playlist(
  String id, {
  String? name,
  bool favorites = false,
  int trackCount = 0,
  int createdAtMs = 1,
  int updatedAtMs = 1,
  String? coverUrl,
  String? shareId,
}) {
  return MyPlaylist(
    id: id,
    name: name ?? '歌单$id',
    favorites: favorites,
    trackCount: trackCount,
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs,
    coverUrl: coverUrl,
    shareId: shareId,
  );
}

final favoritesPlaylist = playlist('fav', name: '我喜欢', favorites: true);

/// 内存里的服务端。读取在发起时就取下结果，挂起的读取因此带着旧数据返回，与
/// 网络上先发后至的回复一样。
final class FakePlaylistApi implements PlaylistApi {
  /// 顺序即 `listMine` 回复的顺序。
  final List<MyPlaylist> playlists = [];

  /// 歌单 ID → 曲目，新加入的在前。
  final Map<String, List<TrackSummary>> contents = {};

  SharedPlaylist? sharedPlaylist;
  ({TrackSource source, String playlistId}) resolved = (
    source: TrackSource.netease,
    playlistId: '24381616',
  );
  int platformTracks = 12;

  /// 按调用顺序记下，例如 `add pl-1 netease:a`。
  final List<String> calls = [];

  /// 在记下调用之后、挂起和失败之前调用，测试可借此在“服务端”做点什么。
  void Function(String method)? onCall;

  final Map<String, List<Completer<void>>> _gates = {};
  final Map<String, List<Exception>> _failures = {};
  int _clock = 100;
  int _created = 0;
  int _shares = 0;

  /// 下一次调用 [method] 时挂起，直到测试完成返回的 Completer。
  Completer<void> hold(String method) {
    final gate = Completer<void>();
    (_gates[method] ??= []).add(gate);
    return gate;
  }

  /// 下一次调用 [method] 时抛出 [error]，在挂起之后。
  void failNext(String method, Exception error) {
    (_failures[method] ??= []).add(error);
  }

  int count(String method) => calls
      .where((call) => call == method || call.startsWith('$method '))
      .length;

  Future<void> _enter(String method, [String detail = '']) async {
    calls.add(detail.isEmpty ? method : '$method $detail');
    onCall?.call(method);
    final gates = _gates[method];
    if (gates != null && gates.isNotEmpty) await gates.removeAt(0).future;
    final failures = _failures[method];
    if (failures != null && failures.isNotEmpty) throw failures.removeAt(0);
  }

  int _indexOf(String id) {
    final index = playlists.indexWhere((playlist) => playlist.id == id);
    if (index < 0) {
      throw apiError('NOT_FOUND', message: '歌单不存在', status: 404);
    }
    return index;
  }

  void _touch(String id) {
    final index = _indexOf(id);
    final old = playlists[index];
    final tracks = contents[id] ?? const <TrackSummary>[];
    playlists[index] = MyPlaylist(
      id: old.id,
      name: old.name,
      favorites: old.favorites,
      trackCount: tracks.length,
      createdAtMs: old.createdAtMs,
      updatedAtMs: ++_clock,
      coverUrl: old.coverUrl,
      shareId: old.shareId,
    );
  }

  MyPlaylist _create(String name) {
    final created = playlist(
      'new-${++_created}',
      name: name,
      createdAtMs: ++_clock,
      updatedAtMs: _clock,
    );
    playlists.add(created);
    contents[created.id] = [];
    return created;
  }

  static String _keys(List<Track> tracks) => tracks.map(trackKey).join(',');

  @override
  Future<List<MyPlaylist>> listMine() async {
    final snapshot = List.of(playlists);
    await _enter('listMine');
    return snapshot;
  }

  @override
  Future<MyPlaylist> create(String name) async {
    await _enter('create', name);
    return _create(name);
  }

  @override
  Future<void> rename(String id, String name) async {
    await _enter('rename', '$id $name');
    final index = _indexOf(id);
    playlists[index] = playlists[index].copyWith(name: name);
  }

  @override
  Future<void> delete(String id) async {
    await _enter('delete', id);
    playlists.removeAt(_indexOf(id));
    contents.remove(id);
  }

  @override
  Future<List<TrackSummary>> items(String id) async {
    final exists = playlists.any((playlist) => playlist.id == id);
    final snapshot = List.of(contents[id] ?? const <TrackSummary>[]);
    await _enter('items', id);
    if (!exists) throw apiError('NOT_FOUND', message: '歌单不存在', status: 404);
    return snapshot;
  }

  @override
  Future<void> add(String id, Track track) async {
    await _enter('add', '$id ${trackKey(track)}');
    _indexOf(id);
    final tracks = contents[id] ??= [];
    if (tracks.any((item) => trackKey(item.track) == trackKey(track))) return;
    tracks.insert(0, song(track.id, source: track.source));
    _touch(id);
  }

  @override
  Future<void> remove(String id, List<Track> tracks) async {
    await _enter('remove', '$id ${_keys(tracks)}');
    _indexOf(id);
    final keys = tracks.map(trackKey).toSet();
    final current = contents[id] ?? [];
    final before = current.length;
    current.removeWhere((item) => keys.contains(trackKey(item.track)));
    if (current.length != before) _touch(id);
  }

  @override
  Future<int> copy({
    required String from,
    required String to,
    required List<Track> tracks,
  }) async {
    await _enter('copy', '$from>$to ${_keys(tracks)}');
    _indexOf(from);
    _indexOf(to);
    // 与服务端相同：只复制来源歌单里确实有的歌，连同它在来源里的信息。
    final source = {
      for (final item in contents[from] ?? const <TrackSummary>[])
        trackKey(item.track): item,
    };
    final target = contents[to] ??= [];
    var added = 0;
    for (final track in tracks.reversed) {
      final item = source[trackKey(track)];
      if (item == null ||
          target.any((old) => trackKey(old.track) == trackKey(track))) {
        continue;
      }
      target.insert(0, item);
      added++;
    }
    if (added > 0) _touch(to);
    return added;
  }

  @override
  Future<void> move(String id, List<Track> tracks, {Track? before}) async {
    await _enter(
      'move',
      '$id ${_keys(tracks)}'
          '${before == null ? '' : ' before ${trackKey(before)}'}',
    );
    _indexOf(id);
    final current = contents[id] ?? const <TrackSummary>[];
    final byKey = {for (final item in current) trackKey(item.track): item};
    final moved = tracks.map(trackKey).toSet();
    // 与服务端相同：before 在要移动的歌里是 INVALID_ARGUMENT，已经不在歌单里是
    // CONFLICT。
    if (before != null && moved.contains(trackKey(before))) {
      throw apiError(
        'INVALID_ARGUMENT',
        message: 'before 不能是要移动的歌',
        status: 400,
      );
    }
    final List<String> order;
    try {
      order = moveTracks(
        [for (final item in current) trackKey(item.track)],
        moved,
        before == null ? null : trackKey(before),
      );
    } on ArgumentError {
      throw apiError('CONFLICT', message: '歌单已经变了，刷新之后再试');
    }
    final unchanged = [for (final item in current) trackKey(item.track)].indexed
        .every((entry) => entry.$2 == order[entry.$1]);
    contents[id] = [for (final key in order) byKey[key]!];
    if (!unchanged) _touch(id);
  }

  @override
  Future<Set<String>> containing(Track track) async {
    final key = trackKey(track);
    final snapshot = {
      for (final playlist in playlists)
        if ((contents[playlist.id] ?? const <TrackSummary>[]).any(
          (item) => trackKey(item.track) == key,
        ))
          playlist.id,
    };
    await _enter('containing', key);
    return snapshot;
  }

  @override
  Future<ImportedPlaylist> importFile(
    String name,
    List<PlaylistFileTrack> tracks,
  ) async {
    await _enter('importFile', '$name ${tracks.length}');
    final created = _create(name.isEmpty ? '导入的歌单' : name);
    contents[created.id] = [
      for (final track in tracks)
        song(track.track.id, title: track.title, source: track.track.source),
    ];
    _touch(created.id);
    return (playlist: playlists[_indexOf(created.id)], imported: tracks.length);
  }

  @override
  Future<({TrackSource source, String playlistId})> resolveLink(
    String link,
  ) async {
    await _enter('resolveLink', link);
    return resolved;
  }

  @override
  Future<ImportedPlaylist> importPlatform({
    required String name,
    required TrackSource source,
    required String playlistId,
  }) async {
    await _enter('importPlatform', '$name ${source.name}:$playlistId');
    return (playlist: _create(name), imported: platformTracks);
  }

  @override
  Future<String> share(String id) async {
    await _enter('share', id);
    final index = _indexOf(id);
    final shareId = (++_shares).isOdd ? shareIdA : shareIdB;
    playlists[index] = playlists[index].copyWith(shareId: shareId);
    return shareId;
  }

  @override
  Future<void> unshare(String id) async {
    await _enter('unshare', id);
    final index = _indexOf(id);
    playlists[index] = playlists[index].copyWith(shareId: null);
  }

  @override
  Future<SharedPlaylist> shared(String shareId) async {
    final found = sharedPlaylist;
    await _enter('shared', shareId);
    if (found == null) {
      throw apiError('NOT_FOUND', message: '分享不存在', status: 404);
    }
    return found;
  }

  @override
  Future<MyPlaylist> copyShared(String shareId, String name) async {
    await _enter('copyShared', '$shareId $name');
    final source = sharedPlaylist;
    if (source == null) {
      throw apiError('NOT_FOUND', message: '分享不存在', status: 404);
    }
    final created = _create(name);
    contents[created.id] = List.of(source.items);
    _touch(created.id);
    return playlists[_indexOf(created.id)];
  }
}

final class FakePlaylistFileSource implements PlaylistFileSource {
  PlaylistFileResult? next;
  int picks = 0;

  /// 不为 null 时下一次选择挂起，就像系统的文件选择器还开着，直到它完成。
  Completer<void>? held;

  @override
  Future<PlaylistFileResult?> pick() async {
    picks++;
    final gate = held;
    held = null;
    if (gate != null) await gate.future;
    return next;
  }
}

final class FakePlaylistExporter implements PlaylistExporter {
  /// 每次调用都记下，抛出 [error] 的也算。
  final List<
    ({String name, List<TrackSummary> items, int exportedAtMs, Rect? origin})
  >
  exports = [];
  Exception? error;

  @override
  Future<void> export(
    String name,
    List<TrackSummary> items,
    int exportedAtMs, {
    Rect? origin,
  }) async {
    exports.add((
      name: name,
      items: items,
      exportedAtMs: exportedAtMs,
      origin: origin,
    ));
    final error = this.error;
    if (error != null) throw error;
  }
}

typedef OpenedPlaylists = ({
  ProviderContainer container,
  FakeAlistenApi api,
  FakeCredentialStore credentials,
});

/// 默认服务器上的成员：memberToken 是 [accountToken]；[signedIn] 时 `getMe`
/// 带回 [testAccount]，否则是游客。[restored] 时身份已经读到，否则还没读。
Future<OpenedPlaylists> playlistsContainer({
  FakePlaylistApi? playlists,
  Override? playlistApi,
  bool signedIn = true,
  bool restored = true,
  FakePlaylistExporter? exporter,
  List<Override> overrides = const [],
}) async {
  final api = FakeAlistenApi()..account = signedIn ? testAccount : null;
  final credentials = FakeCredentialStore()..memberToken = accountToken;
  final container = ProviderContainer(
    overrides: [
      ...alistenWiring(await loadPreferences()),
      alistenApiProvider.overrideWithValue(api),
      credentialStoreFactoryProvider.overrideWithValue((_) => credentials),
      playlistApi ??
          playlistApiProvider.overrideWithValue(playlists ?? FakePlaylistApi()),
      playlistExporterProvider.overrideWithValue(
        exporter ?? FakePlaylistExporter(),
      ),
      playlistsNowProvider.overrideWithValue(() => testNowMs),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  if (restored) {
    await container.read(identityControllerProvider.notifier).restore();
  }
  return (container: container, api: api, credentials: credentials);
}
