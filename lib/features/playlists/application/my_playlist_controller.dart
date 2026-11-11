import 'dart:async';
import 'dart:ui' show Rect;

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/track_order.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:alisten/features/playlists/application/playlist_io.dart';
import 'package:alisten/features/playlists/application/playlist_requests.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const exportFailedText = '导出失败，请稍后重试。';

String exportReadFailedText(String message) => '没能导出：$message';

const _notFound = 'NOT_FOUND';
const _invalidArgument = 'INVALID_ARGUMENT';
const _unauthorized = 'UNAUTHORIZED';
const _logSource = 'playlists';

@immutable
final class MyPlaylistState {
  const MyPlaylistState({
    this.items,
    this.error,
    this.gone = false,
    this.selecting = false,
    this.selected = const {},
    this.exporting = false,
  });

  /// 还没读到时为 null。
  final List<TrackSummary>? items;
  final String? error;

  /// 读到的列表里没有它，或者读取曲目返回 `NOT_FOUND`。
  final bool gone;
  final bool selecting;

  /// trackKey。
  final Set<String> selected;
  final bool exporting;

  MyPlaylistState copyWith({
    Object? items = _unchanged,
    Object? error = _unchanged,
    bool? gone,
    bool? selecting,
    Set<String>? selected,
    bool? exporting,
  }) {
    return MyPlaylistState(
      items: identical(items, _unchanged)
          ? this.items
          : items as List<TrackSummary>?,
      error: identical(error, _unchanged) ? this.error : error as String?,
      gone: gone ?? this.gone,
      selecting: selecting ?? this.selecting,
      selected: selected ?? this.selected,
      exporting: exporting ?? this.exporting,
    );
  }
}

const _unchanged = Object();

typedef _Listed = ({bool present, int updatedAtMs});

final myPlaylistControllerProvider = NotifierProvider.autoDispose
    .family<MyPlaylistController, MyPlaylistState, String>(
      MyPlaylistController.new,
    );

final class MyPlaylistController extends Notifier<MyPlaylistState> {
  MyPlaylistController(this.id);

  final String id;
  int _generation = 0;

  // 归属每变一次加 1，之前发起的读取、编辑和导出完成时据此作废。归属变化时
  // Riverpod 复用同一个实例重新 build，ref.mounted 一直是 true；只有 onDispose
  // 在重新 build 之前执行。
  int _scope = 0;

  // 编辑队列属于当前归属，归属变化时清空：旧归属的编辑不挡住新归属的读取，
  // 完成时也不改动新的计数。
  int _pendingEdits = 0;
  int _failedEdits = 0;
  Future<void> _edits = Future<void>.value();

  // 打开页面时的服务器。不在 onDispose 里重置：重新 build 时要拿它和新的比较。
  PlaylistApi? _origin;

  @override
  MyPlaylistState build() {
    ref.onDispose(() {
      _scope++;
      _pendingEdits = 0;
      _edits = Future<void>.value();
    });
    final api = ref.watch(playlistApiProvider);
    ref.watch(
      identityControllerProvider.select((identity) => identity.session),
    );
    final account = ref.watch(
      identityControllerProvider.select((identity) => identity.account != null),
    );
    // 歌单 ID 只属于原来的服务器：换了服务器就不再拿它去读新的服务器，也不按
    // 新服务器的列表说它不存在了。页面随后就会离开。
    if (!identical(_origin ??= api, api)) return const MyPlaylistState();
    // 详情页打开期间列表一直存活。加入、移出、移动和复制都会推进
    // updatedAtMs，歌曲数不变时顺序也可能变了。
    ref.listen(myPlaylistsControllerProvider.select(_listed), (previous, next) {
      if (next == null) return;
      if (!next.present) {
        state = state.copyWith(gone: true);
      } else if (previous != null &&
          previous.present &&
          previous.updatedAtMs != next.updatedAtMs) {
        unawaited(load());
      }
    });
    ref.listen(appVisibleProvider, (previous, visible) {
      if (previous == false && visible) unawaited(load());
    });
    if (!account) return const MyPlaylistState();
    unawaited(Future.microtask(load));
    return MyPlaylistState(
      gone: _listed(ref.read(myPlaylistsControllerProvider))?.present == false,
    );
  }

  _Listed? _listed(MyPlaylistsState list) {
    final playlists = list.playlists;
    if (playlists == null) return null;
    for (final playlist in playlists) {
      if (playlist.id == id) {
        return (present: true, updatedAtMs: playlist.updatedAtMs);
      }
    }
    return (present: false, updatedAtMs: 0);
  }

  /// 编辑进行中不读：读到的可能是编辑之前的列表。最后一次编辑结束后会再读。
  Future<void> load() async {
    if (!ref.mounted) return;
    final scope = _currentScope;
    if (!_onOrigin ||
        _pendingEdits > 0 ||
        ref.read(identityControllerProvider).account == null) {
      return;
    }
    final generation = ++_generation;
    if (state.error != null) state = state.copyWith(error: null);
    final result = await PlaylistRequests(ref).fetch((api) => api.items(id));
    if (!_isCurrent(scope) || generation != _generation || _pendingEdits > 0) {
      return;
    }
    switch (result) {
      case FetchedValue(:final value):
        _show(value);
      case FetchFailed(code: _notFound):
        state = state.copyWith(gone: true);
        unawaited(ref.read(myPlaylistsControllerProvider.notifier).load());
      case FetchFailed(:final message):
        // 旧曲目不保留：它们可能已经不在了，也可能属于之前的账号。
        state = MyPlaylistState(
          error: message,
          gone: state.gone,
          exporting: state.exporting,
        );
      case FetchRefused():
        break;
    }
  }

  void _show(List<TrackSummary> items) {
    final keys = {for (final item in items) trackKey(item.track)};
    state = state.copyWith(
      items: items,
      error: null,
      selected: state.selected.intersection(keys),
      selecting: state.selecting && items.isNotEmpty,
    );
  }

  Future<MutationResult<void>?> move(MovePlan plan) async {
    final scope = _currentScope;
    final items = state.items;
    if (items == null) return null;
    final byKey = {for (final item in items) trackKey(item.track): item};
    final before = plan.before;
    if (plan.order.length != items.length ||
        !plan.order.every(byKey.containsKey) ||
        !plan.moved.every(byKey.containsKey) ||
        (before != null && !byKey.containsKey(before))) {
      return null;
    }
    final moved = [for (final key in plan.moved) byKey[key]!.track];
    final beforeTrack = before == null ? null : byKey[before]!.track;
    return _edit(
      scope,
      [for (final key in plan.order) byKey[key]!],
      state.selected,
      'move',
      (api) => api.move(id, moved, before: beforeTrack),
    );
  }

  Future<MutationResult<void>?> remove(List<Track> tracks) async {
    final scope = _currentScope;
    final items = state.items;
    if (items == null || tracks.isEmpty) return null;
    final keys = {for (final track in tracks) trackKey(track)};
    return _edit(
      scope,
      [
        for (final item in items)
          if (!keys.contains(trackKey(item.track))) item,
      ],
      state.selected.difference(keys),
      'remove',
      (api) => api.remove(id, tracks),
    );
  }

  /// 先改本地，再按发起的先后逐个发出，每次都基于上一次编辑之后的顺序。一次
  /// 失败后，排在它后面的不再发出（返回 null），列表和选中项回到失败的那次编辑
  /// 之前；结果未知同样回滚，随后的重新读取以服务端为准。归属变了时还没发出的
  /// 也返回 null，已经发出的返回真实结果，都不改动新的状态。
  Future<MutationResult<void>?> _edit(
    int scope,
    List<TrackSummary> items,
    Set<String> selected,
    String endpoint,
    Future<void> Function(PlaylistApi api) send,
  ) {
    final before = state;
    final failedBefore = _failedEdits;
    state = before.copyWith(
      items: items,
      selected: selected,
      selecting: before.selecting && items.isNotEmpty,
    );
    _pendingEdits++;
    // 页面关掉之后，排着的编辑照样发出：界面已经按发出之后的样子显示过了。
    final keepAlive = ref.keepAlive();
    final requests = PlaylistRequests(ref);
    final done = _edits.then((_) async {
      if (!_isCurrent(scope) || _failedEdits != failedBefore) return null;
      final result = await requests.change<void>(send);
      if (result is MutationSucceeded<void> || !_isCurrent(scope)) {
        return result;
      }
      _failedEdits++;
      state = state.copyWith(
        items: before.items,
        selected: before.selected,
        selecting: before.selecting,
      );
      if (result case MutationFailed(code: _invalidArgument)) {
        // 例如 before 在被移动的歌里：客户端有缺陷。
        AppLog.error(_logSource, '$endpoint refused', code: _invalidArgument);
      }
      return result;
    });
    _edits = done.then<void>((_) {}, onError: (Object _) {});
    return done.whenComplete(() {
      // 归属变了时，失效已经丢掉了这条保活；再关闭它会让容器释放之后为同一个
      // 歌单新建的控制器。
      if (!_isCurrent(scope)) return;
      if (--_pendingEdits == 0) {
        unawaited(load());
        unawaited(ref.read(myPlaylistsControllerProvider.notifier).load());
      }
      keepAlive.close();
    });
  }

  void startSelecting() {
    if (state.items?.isNotEmpty ?? false) {
      state = state.copyWith(selecting: true);
    }
  }

  void toggle(String key) {
    final selected = {...state.selected};
    if (!selected.remove(key)) selected.add(key);
    state = state.copyWith(selected: selected);
  }

  void selectAll() {
    state = state.copyWith(
      selected: {
        for (final item in state.items ?? const <TrackSummary>[])
          trackKey(item.track),
      },
    );
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  void stopSelecting() {
    state = state.copyWith(selecting: false, selected: const {});
  }

  /// 先重新读一次曲目：页面上的列表可能还没读到，或者带着没同步完的修改。用户
  /// 在系统分享面板里取消不算失败。
  Future<MutationResult<void>> export(Rect? origin) async {
    final scope = _currentScope;
    if (!_onOrigin) return const MutationNotSent(serverChangedNotice);
    final requests = PlaylistRequests(ref);
    final exporter = ref.read(playlistExporterProvider);
    final now = ref.read(playlistsNowProvider);
    // 页面关掉之后照样导出完：只有归属变了才作废。
    final keepAlive = ref.keepAlive();
    state = state.copyWith(exporting: true);
    try {
      final read = await requests.fetch((api) => api.items(id));
      switch (read) {
        case FetchRefused(:final message):
          return MutationFailed(_unauthorized, message);
        // 读取期间换了账号或服务器：读到的不交给分享面板，读不到也不是这边的
        // 失败。
        case _ when !_isCurrent(scope):
          return MutationNotSent(
            requests.serverChanged
                ? serverChangedNotice
                : identityRenewedNotice,
          );
        case FetchFailed(:final code, :final message):
          if (code == _notFound) {
            unawaited(ref.read(myPlaylistsControllerProvider.notifier).load());
          }
          return MutationFailed(code, exportReadFailedText(message));
        case FetchedValue(:final value):
          try {
            await exporter.export(_name(), value, now(), origin: origin);
            return const MutationSucceeded(null);
          } on Object catch (error) {
            AppLog.warn(
              _logSource,
              'playlist not exported',
              type: '${error.runtimeType}',
            );
            return const MutationFailed(null, exportFailedText);
          }
      }
    } finally {
      // 与编辑相同：归属变了时不关闭已经丢掉的保活。
      if (_isCurrent(scope)) {
        state = state.copyWith(exporting: false);
        keepAlive.close();
      }
    }
  }

  String _name() {
    final playlists =
        ref.read(myPlaylistsControllerProvider).playlists ??
        const <MyPlaylist>[];
    for (final playlist in playlists) {
      if (playlist.id == id) return playlist.name;
    }
    return '歌单';
  }

  bool get _onOrigin => identical(ref.read(playlistApiProvider), _origin);

  // 换服务器的通知要等依赖刷新之后才送到：读取 state 会先刷新过期的依赖，归属
  // 变了时 onDispose 就在这一步执行。
  int get _currentScope {
    state;
    return _scope;
  }

  bool _isCurrent(int scope) => ref.mounted && scope == _currentScope;
}
