import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:alisten/features/playlists/application/playlist_io.dart';
import 'package:alisten/features/playlists/application/playlist_requests.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const invalidPlaylistNameText = '歌单名要 1 到 50 个字。';
const invalidImportFileText = '文件里有不符合要求的内容，没有导入。';
const linkTooLongText = '文字太长了，只粘贴歌单的链接或分享文字就好。';
const unknownResultText = '结果未知，已重新读取';
const maxPlaylistLinkBytes = 2048;

const _invalidArgument = 'INVALID_ARGUMENT';
const _notFound = 'NOT_FOUND';
const _rateLimited = 'RATE_LIMITED';
const _unauthorized = 'UNAUTHORIZED';

@immutable
final class MyPlaylistsState {
  const MyPlaylistsState({
    this.guest = false,
    this.playlists,
    this.error,
    this.loadedAtMs = 0,
    this.memberships = const {},
  });

  /// 确认不是账号之后才为 true；身份还没读到时为 false。
  final bool guest;

  /// 游客或者还没读到时为 null，顺序与服务端相同。
  final List<MyPlaylist>? playlists;

  /// 最近一次读取失败的原因，读到后清空。
  final String? error;

  /// 列表最近一次读到的时间，日期文字以它为“现在”。
  final int loadedAtMs;

  /// trackKey → 包含这首歌的歌单 ID，只有读过的歌才有。
  final Map<String, Set<String>> memberships;

  MyPlaylistsState copyWith({
    bool? guest,
    List<MyPlaylist>? playlists,
    Object? error = _unchanged,
    int? loadedAtMs,
    Map<String, Set<String>>? memberships,
  }) {
    return MyPlaylistsState(
      guest: guest ?? this.guest,
      playlists: playlists ?? this.playlists,
      error: identical(error, _unchanged) ? this.error : error as String?,
      loadedAtMs: loadedAtMs ?? this.loadedAtMs,
      memberships: memberships ?? this.memberships,
    );
  }
}

const _unchanged = Object();

/// [truncated]：文件里超过 [playlistFileTrackLimit] 首，只导入了前面的。
typedef ImportedFile = ({MyPlaylist playlist, int imported, bool truncated});

/// 有页面、面板或详情控制器在用时存活。变更都把失败放进结果，不抛出。
final myPlaylistsControllerProvider =
    NotifierProvider.autoDispose<MyPlaylistsController, MyPlaylistsState>(
      MyPlaylistsController.new,
    );

final class MyPlaylistsController extends Notifier<MyPlaylistsState> {
  int _generation = 0;

  // 归属每变一次加 1，之前发起的操作完成时据此作废。归属变化时 Riverpod 复用同一个
  // 实例重新 build，ref.mounted 一直是 true；只有 onDispose 在重新 build 之前执行。
  int _scope = 0;

  final Map<String, int> _membershipReads = {};

  // （归属，歌单 ID，trackKey）。带上归属：归属变化后旧的同步还在等回复，它不能
  // 挡住新归属里对同一首歌、同一个歌单的点击，也不能让新归属的读取以为它在同步。
  final Set<(int, String, String)> _syncing = {};

  @override
  MyPlaylistsState build() {
    ref.onDispose(() => _scope++);
    // 歌单属于某个服务器上的某个账号，任何一项变了都重新开始。游客注册账号时
    // token 和会话代号都不变，只有 account 从无到有。换服务器时身份清空、会话
    // 代号不变，列表可能先按旧身份重新开始，所以还要看身份是否已经读到。
    ref.watch(playlistApiProvider);
    ref.watch(
      identityControllerProvider.select((identity) => identity.session),
    );
    final account = ref.watch(
      identityControllerProvider.select((identity) => identity.account != null),
    );
    final known = ref.watch(
      identityControllerProvider.select((identity) => identity.member != null),
    );
    ref.listen(appVisibleProvider, (previous, visible) {
      if (previous == false && visible) unawaited(load());
    });
    if (account) {
      unawaited(Future.microtask(load));
      return const MyPlaylistsState();
    }
    if (known) return const MyPlaylistsState(guest: true);
    unawaited(Future.microtask(_restoreIdentity));
    return const MyPlaylistsState();
  }

  /// 只有最后发起的那次读取能写入。
  Future<void> load() async {
    if (!ref.mounted || ref.read(identityControllerProvider).account == null) {
      return;
    }
    final scope = _currentScope;
    final generation = ++_generation;
    if (state.error != null) state = state.copyWith(error: null);
    final now = ref.read(playlistsNowProvider);
    final result = await PlaylistRequests(ref).fetch((api) => api.listMine());
    if (!_isCurrent(scope) || generation != _generation) return;
    switch (result) {
      case FetchedValue(:final value):
        state = state.copyWith(
          playlists: value,
          error: null,
          loadedAtMs: now(),
        );
      case FetchFailed(:final message):
        state = state.copyWith(error: message);
      case FetchRefused():
        break;
    }
  }

  /// 身份没读到时再读身份，否则重新读取列表。
  Future<void> retry() {
    if (ref.read(identityControllerProvider).account != null) return load();
    return _restoreIdentity();
  }

  /// 返回读取失败的原因；读到、被后来的读取取代、被拒或者归属已经变了时返回
  /// null。
  Future<String?> containing(Track track) async {
    if (!ref.mounted || ref.read(identityControllerProvider).account == null) {
      return null;
    }
    final scope = _currentScope;
    final key = trackKey(track);
    final read = (_membershipReads[key] ?? 0) + 1;
    _membershipReads[key] = read;
    final result = await PlaylistRequests(ref)
        .fetch((api) => api.containing(track));
    if (!_isCurrent(scope) || _membershipReads[key] != read) return null;
    switch (result) {
      case FetchedValue(:final value):
        // 正在同步的歌单以本地为准：这次读到的可能是同步完成之前的状态。
        bool syncing(String id) => _syncing.contains((scope, id, key));
        final ids = {
          for (final id in value)
            if (!syncing(id)) id,
          for (final id in state.memberships[key] ?? const <String>{})
            if (syncing(id)) id,
        };
        state = state.copyWith(memberships: {...state.memberships, key: ids});
        return null;
      case FetchFailed(:final message):
        return message;
      case FetchRefused():
        return null;
    }
  }

  /// 最后一次点击为准：本地的勾选立即改成 [included]；同一首歌在同一个歌单上
  /// 已有同步在进行时只改意图，返回 null，结果由发起同步的那次点击报告。失败、
  /// 被限流或者结果未知时勾选回到最后确认的状态，不再发出。归属变化之后不再
  /// 发出，也不改新归属的勾选，返回最后一次请求的结果。
  Future<MutationResult<void>?> setMembership(
    MyPlaylist playlist,
    Track track, {
    required bool included,
  }) async {
    if (!ref.mounted) return null;
    final scope = _currentScope;
    final key = trackKey(track);
    final sync = (scope, playlist.id, key);
    var confirmed = _includes(key, playlist.id);
    _tick(key, playlist.id, included: included);
    if (_syncing.contains(sync) || included == confirmed) return null;
    _syncing.add(sync);
    // 面板关掉之后也要活到同步结束，否则最后一次点击发不出去。
    final alive = ref.keepAlive();
    final requests = PlaylistRequests(ref);
    MutationResult<void> result = const MutationSucceeded(null);
    try {
      while (_isCurrent(scope)) {
        final wanted = _includes(key, playlist.id);
        if (wanted == confirmed) break;
        result = await requests.change<void>(
          (api) => wanted
              ? api.add(playlist.id, track)
              : api.remove(playlist.id, [track]),
        );
        if (result is! MutationSucceeded<void>) {
          if (_isCurrent(scope)) _tick(key, playlist.id, included: confirmed);
          break;
        }
        confirmed = wanted;
      }
    } finally {
      _syncing.remove(sync);
      // 同步期间发出的读取可能带着旧的勾选返回；请求超时而服务端其实已生效时，
      // 也要以服务端为准。归属变化时保活已经随失效释放，再关闭这个旧的会让之后
      // 新建的控制器被回收。
      if (_isCurrent(scope)) {
        unawaited(containing(track));
        unawaited(load());
        alive.close();
      }
    }
    return result;
  }

  /// 每个目标的结果里，`int` 是新加入的首数。
  Future<List<(MyPlaylist, MutationResult<int>)>> copyTracks(
    MyPlaylist from,
    List<Track> tracks,
    List<MyPlaylist> targets,
  ) async {
    final scope = _currentScope;
    final requests = PlaylistRequests(ref);
    final results = await Future.wait([
      for (final target in targets)
        requests.change(
          (api) => api.copy(from: from.id, to: target.id, tracks: tracks),
        ),
    ]);
    if (_isCurrent(scope)) {
      _saved(scope, tracks, [
        for (final (index, target) in targets.indexed)
          if (results[index] is MutationSucceeded<int>) target.id,
      ]);
      unawaited(load());
    }
    return [
      for (final (index, target) in targets.indexed) (target, results[index]),
    ];
  }

  // 只改读过的歌：没读过的打开面板时会读。正在同步的歌单以本地的勾选为准。
  void _saved(int scope, List<Track> tracks, List<String> playlistIds) {
    if (playlistIds.isEmpty) return;
    final memberships = {...state.memberships};
    for (final track in tracks) {
      final key = trackKey(track);
      final ids = memberships[key];
      if (ids == null) continue;
      memberships[key] = {
        ...ids,
        for (final id in playlistIds)
          if (!_syncing.contains((scope, id, key))) id,
      };
    }
    state = state.copyWith(memberships: memberships);
  }

  bool _includes(String key, String playlistId) =>
      state.memberships[key]?.contains(playlistId) ?? false;

  void _tick(String key, String playlistId, {required bool included}) {
    final ids = {...?state.memberships[key]};
    if (included) {
      ids.add(playlistId);
    } else {
      ids.remove(playlistId);
    }
    state = state.copyWith(memberships: {...state.memberships, key: ids});
  }

  // 身份还没读到（启动时恢复失败、刚换了服务器）：先分清“确实不是账号”和
  // “还没读到”。restore 失败时不当作游客，免得已登录的用户看到注册提示。
  Future<void> _restoreIdentity() async {
    if (!ref.mounted) return;
    final scope = _currentScope;
    if (state.error != null) state = state.copyWith(error: null);
    final identity = ref.read(identityControllerProvider.notifier);
    try {
      await identity.restore();
    } on Object catch (error) {
      if (_isCurrent(scope)) {
        state = state.copyWith(
          error: error is ApiException
              ? (error.rateLimited ? rateLimitedText(error) : error.message)
              : identityUnreadableText,
        );
      }
      return;
    }
    // 读到成员或账号时，身份的变化已让控制器重新开始；还在原来的归属里说明本机
    // 在这个服务器上没有身份。
    if (_isCurrent(scope)) state = state.copyWith(guest: true);
  }

  Future<MutationResult<MyPlaylist>> create(String name) async {
    final scope = _currentScope;
    final result = await PlaylistRequests(ref)
        .change((api) => api.create(name.trim()));
    if (result case MutationSucceeded(:final value)) _added(scope, value);
    return _settled(scope, _named(result));
  }

  Future<MutationResult<void>> rename(MyPlaylist playlist, String name) async {
    final scope = _currentScope;
    final trimmed = name.trim();
    final result = await PlaylistRequests(ref)
        .change((api) => api.rename(playlist.id, trimmed));
    if (result is MutationSucceeded) {
      _changed(scope, playlist.id, (old) => old.copyWith(name: trimmed));
    }
    return _settled(scope, _named(result));
  }

  Future<MutationResult<void>> delete(MyPlaylist playlist) async {
    final scope = _currentScope;
    final result = await PlaylistRequests(ref)
        .change((api) => api.delete(playlist.id));
    if (result is MutationSucceeded) _changed(scope, playlist.id, (_) => null);
    return _settled(scope, result);
  }

  /// 返回新的分享 ID。旧链接随之失效。
  Future<MutationResult<String>> share(MyPlaylist playlist) async {
    final scope = _currentScope;
    final result = await PlaylistRequests(ref)
        .change((api) => api.share(playlist.id));
    if (result case MutationSucceeded(:final value)) {
      _changed(scope, playlist.id, (old) => old.copyWith(shareId: value));
    }
    return _settled(scope, result);
  }

  Future<MutationResult<void>> unshare(MyPlaylist playlist) async {
    final scope = _currentScope;
    final result = await PlaylistRequests(ref)
        .change((api) => api.unshare(playlist.id));
    if (result is MutationSucceeded) {
      _changed(scope, playlist.id, (old) => old.copyWith(shareId: null));
    }
    return _settled(scope, result);
  }

  String shareLink(String shareId) =>
      ref.read(appConfigProvider).sharedPlaylistLinkFor(shareId);

  Future<MutationResult<ImportedPlaylist>> importFile(PlaylistFile file) async {
    final scope = _currentScope;
    final result = await PlaylistRequests(ref)
        .change((api) => api.importFile(file.name, file.tracks));
    return _imported(scope, switch (result) {
      MutationFailed(code: _invalidArgument) => const MutationFailed(
        _invalidArgument,
        invalidImportFileText,
      ),
      _ => result,
    });
  }

  /// 用户取消选择时返回 null；文件读不出来或者解析出错时返回那条错误，不发
  /// 请求。
  Future<MutationResult<ImportedFile>?> importFromFile() async {
    final source = ref.read(playlistFileSourceProvider);
    final scope = _currentScope;
    final PlaylistFile file;
    switch (await source.pick()) {
      case null:
        return null;
      case PlaylistFileProblem(:final message):
        return MutationFailed(null, message);
      case final PlaylistFile picked:
        file = picked;
    }
    // 选文件期间身份变了：再导入就记到了之后的身份名下。
    if (!_isCurrent(scope)) return const MutationNotSent(identityRenewedNotice);
    return switch (await importFile(file)) {
      MutationSucceeded(value: (:final playlist, :final imported)) =>
        MutationSucceeded((
          playlist: playlist,
          imported: imported,
          truncated: file.truncated,
        )),
      MutationFailed(:final code, :final message) => MutationFailed(
        code,
        message,
      ),
      MutationNotSent(:final message) => MutationNotSent(message),
      MutationUnknown() => const MutationUnknown(),
    };
  }

  /// 链接按 UTF-8 计算超过 2048 字节时不发请求。解析或导入任何一步失败都返回
  /// 那一步的结果。解析的消息原样给用户看；解析已排除非网易云的歌单，导入这一步
  /// 的 INVALID_ARGUMENT 只可能是名字不合法，按命名规则改写。
  Future<MutationResult<ImportedPlaylist>> importLink(
    String link,
    String name,
  ) async {
    final text = link.trim();
    if (utf8.encode(text).length > maxPlaylistLinkBytes) {
      return const MutationNotSent(linkTooLongText);
    }
    final scope = _currentScope;
    final requests = PlaylistRequests(ref);
    // 解析不改动服务端，按读取处理：回复丢了就是没解析出来，不是结果未知。
    final resolved = await requests.fetch((api) => api.resolveLink(text));
    final ({TrackSource source, String playlistId}) target;
    switch (resolved) {
      case FetchRefused(:final message):
        return MutationFailed(_unauthorized, message);
      // 解析期间身份或服务器变了：再导入就记到了之后的身份或服务器名下。
      case _ when !_isCurrent(scope):
        return MutationNotSent(
          requests.serverChanged ? serverChangedNotice : identityRenewedNotice,
        );
      case FetchFailed(:final code, :final message)
          when code == _rateLimited || code == LocalErrorCodes.noToken:
        return MutationNotSent(message);
      case FetchFailed(:final code, :final message):
        return MutationFailed(code, message);
      case FetchedValue(:final value):
        target = value;
    }
    return _imported(
      scope,
      _named(
        await requests.change(
          (api) => api.importPlatform(
            name: name.trim(),
            source: target.source,
            playlistId: target.playlistId,
          ),
        ),
      ),
    );
  }

  Future<MutationResult<ImportedPlaylist>> importPlatform({
    required TrackSource source,
    required String playlistId,
    required String name,
  }) async {
    final scope = _currentScope;
    final result = await PlaylistRequests(ref).change(
      (api) => api.importPlatform(
        name: name.trim(),
        source: source,
        playlistId: playlistId,
      ),
    );
    return _imported(scope, _named(result));
  }

  Future<MutationResult<MyPlaylist>> copyShared(
    String shareId,
    String name,
  ) async {
    final scope = _currentScope;
    final result = await PlaylistRequests(ref)
        .change((api) => api.copyShared(shareId, name.trim()));
    if (result case MutationSucceeded(:final value)) _added(scope, value);
    return _settled(scope, _named(result));
  }

  // 换服务器的通知要等依赖刷新之后才送到：读取 state 会先刷新过期的依赖，归属
  // 变了时 onDispose 就在这一步执行。
  int get _currentScope {
    state;
    return _scope;
  }

  bool _isCurrent(int scope) => ref.mounted && scope == _currentScope;

  MutationResult<ImportedPlaylist> _imported(
    int scope,
    MutationResult<ImportedPlaylist> result,
  ) {
    if (result case MutationSucceeded(:final value)) {
      _added(scope, value.playlist);
    }
    return _settled(scope, result);
  }

  // 新建的歌单先放进列表：打开它时列表里必须已经有它，否则详情页会以为它被
  // 删了。之后的重新读取以服务端为准。
  void _added(int scope, MyPlaylist playlist) {
    if (!_isCurrent(scope)) return;
    state = state.copyWith(
      playlists: [
        for (final old in state.playlists ?? const <MyPlaylist>[])
          if (old.id != playlist.id) old,
        playlist,
      ],
    );
    unawaited(load());
  }

  /// [change] 返回 null 时从列表里去掉这个歌单。
  void _changed(
    int scope,
    String id,
    MyPlaylist? Function(MyPlaylist old) change,
  ) {
    if (!_isCurrent(scope)) return;
    final playlists = state.playlists;
    if (playlists != null) {
      state = state.copyWith(
        playlists: [
          for (final old in playlists)
            if (old.id != id) old else ?change(old),
        ],
      );
    }
    unawaited(load());
  }

  // 结果未知或歌单已经不在：重新读取，以服务端为准。
  MutationResult<T> _settled<T>(int scope, MutationResult<T> result) {
    final calibrate = switch (result) {
      MutationUnknown() => true,
      MutationFailed(code: _notFound) => true,
      _ => false,
    };
    if (calibrate && _isCurrent(scope)) unawaited(load());
    return result;
  }

  static MutationResult<T> _named<T>(MutationResult<T> result) {
    return switch (result) {
      MutationFailed(code: _invalidArgument) => MutationFailed(
        _invalidArgument,
        invalidPlaylistNameText,
      ),
      _ => result,
    };
  }
}
