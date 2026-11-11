import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _unauthorized = 'UNAUTHORIZED';
const _unexpectedText = '请稍后重试。';
const _logSource = 'history';

abstract interface class HistoryExporter {
  Future<void> export(List<Listen> listens, DateTime exportedAt);
}

final historyExporterProvider = Provider<HistoryExporter>((ref) {
  throw UnimplementedError('historyExporter 未注入');
});

final historyNowProvider = Provider<int Function()>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch;
});

final historyControllerProvider =
    NotifierProvider<HistoryController, HistoryState>(HistoryController.new);

final class HistoryState {
  const HistoryState({this.listens, this.error, this.query = ''});

  /// 最近听到的在前；还没有读到时为 null。
  final List<Listen>? listens;

  /// 最近一次读取失败的原因，读取成功后为 null。
  final String? error;

  /// 原样保存筛选词，页面重建时筛选框据此回显。
  final String query;

  List<Listen> get filteredListens {
    final listens = this.listens ?? const <Listen>[];
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return listens;
    return listens
        .where(
          (listen) =>
              listen.meta.title.toLowerCase().contains(keyword) ||
              listen.meta.artist.toLowerCase().contains(keyword) ||
              listen.meta.album.toLowerCase().contains(keyword),
        )
        .toList(growable: false);
  }

  HistoryState copyWith({
    Object? listens = _unchanged,
    Object? error = _unchanged,
    String? query,
  }) {
    return HistoryState(
      listens: identical(listens, _unchanged)
          ? this.listens
          : listens as List<Listen>?,
      error: identical(error, _unchanged) ? this.error : error as String?,
      query: query ?? this.query,
    );
  }
}

const _unchanged = Object();

/// 常驻：重新打开页面时先显示上次读到的列表，再在后台刷新。
final class HistoryController extends Notifier<HistoryState> {
  // 路由切换时新旧两个页面可能同时存在一小段时间，所以计数。
  int _openPages = 0;

  // 每次开始读取、删除或清空成功、身份范围变化时加 1；读取完成时已经不是最新
  // 的，结果直接丢弃。
  int _generation = 0;

  // 会话代号或当前服务器变化时加 1。删除和清空完成时它变了，就不再改动列表。
  int _scope = 0;

  int _reading = 0;

  @override
  HistoryState build() {
    // 监听 roomControllerProvider 而不是 nowPlayingProvider：应用不绘制帧时，
    // 派生 provider 的变化不保证能在 Widget 之外送达。服务端在广播新歌之前
    // 就写入了历史，这时读取能读到这首歌。
    ref.listen(roomControllerProvider.select(_playbackOf), (_, next) {
      if (next != null) _reloadIfOpen();
    });
    // 换服务器不改会话代号，两者都要监听。
    ref.listen(
      identityControllerProvider.select((identity) => identity.session),
      (_, _) => _changeScope(),
    );
    ref.listen(
      currentServerProvider.select((server) => server.id),
      (_, _) => _changeScope(),
    );
    return const HistoryState();
  }

  /// 页面打开时调用，读取一次；页面关闭时调用返回的函数。
  void Function() open() {
    _openPages++;
    unawaited(load());
    var closed = false;
    return () {
      if (closed) return;
      closed = true;
      _openPages--;
    };
  }

  /// 不抛出。
  Future<void> load() async {
    // 延后到微任务里开始的读取，可能在控制器销毁之后才执行。
    if (!ref.mounted) return;
    final generation = ++_generation;
    _reading++;
    try {
      // 读取失败页上的“重试”靠这一步回到加载中。
      if (state.error != null) state = state.copyWith(error: null);
      final credentials = ref.read(credentialStoreProvider);
      final api = ref.read(alistenApiProvider);
      final identity = ref.read(identityControllerProvider.notifier);
      final String? token;
      try {
        token = await credentials.readMemberToken();
      } on Object {
        AppLog.warn(_logSource, 'member token not read');
        _fail(generation, identityUnreadableText);
        return;
      }
      // 这个服务器上还没有身份，也就没有历史，不为此建游客。
      if (token == null || token.isEmpty) {
        _show(generation, const []);
        return;
      }
      try {
        _show(generation, await api.listMyListens());
      } on ApiException catch (error) {
        if (error.code == _unauthorized) {
          // 替换身份会让会话代号变化，列表随之清空并重新读取。
          await identity.recoverFromRefusal(credentials, token);
        } else {
          _fail(generation, rateLimitedText(error));
        }
      } on Object catch (error) {
        AppLog.error(
          _logSource,
          'history read ended unexpectedly',
          type: '${error.runtimeType}',
        );
        _fail(generation, _unexpectedText);
      }
    } finally {
      _reading--;
    }
  }

  void filter(String query) {
    state = state.copyWith(query: query);
  }

  Future<MutationResult<void>> remove(Listen listen) {
    return _change(
      (api) => api.removeMyListen(listen.track),
      (listens) => [
        for (final item in listens)
          if (!item.isSameTrackAs(listen)) item,
      ],
    );
  }

  Future<MutationResult<void>> clear() {
    return _change((api) => api.clearMyListens(), (_) => const []);
  }

  Future<void> exportHistory() {
    final now = DateTime.fromMillisecondsSinceEpoch(
      ref.read(historyNowProvider)(),
      isUtc: true,
    );
    return ref
        .read(historyExporterProvider)
        .export(state.listens ?? const [], now);
  }

  // 删除和清空都可以安全重试，但这里不自动重发：结果未知时重新读取列表来校准。
  Future<MutationResult<void>> _change(
    Future<void> Function(AlistenApi api) request,
    List<Listen> Function(List<Listen> listens) apply,
  ) async {
    final credentials = ref.read(credentialStoreProvider);
    final api = ref.read(alistenApiProvider);
    final identity = ref.read(identityControllerProvider.notifier);
    // 上面的读取可能让还没送达的服务器变化先生效，范围要在取定凭据之后记下。
    final scope = _scope;
    final token = await credentials.readMemberTokenOrNull();
    try {
      await request(api);
    } on ApiException catch (error) {
      if (error.code == _unauthorized) {
        return MutationFailed(
          _unauthorized,
          await identity.recoverFromRefusal(credentials, token),
        );
      }
      if (error.answerLost) {
        if (_isCurrent(scope)) _reloadIfOpen();
        return const MutationUnknown();
      }
      if (error.code == LocalErrorCodes.noToken) {
        return MutationNotSent(error.message);
      }
      return MutationFailed(error.code, rateLimitedText(error));
    } on Object catch (error) {
      AppLog.error(
        _logSource,
        'history change ended unexpectedly',
        type: '${error.runtimeType}',
      );
      if (_isCurrent(scope)) _reloadIfOpen();
      return const MutationUnknown();
    }
    if (_isCurrent(scope)) {
      // 进行中的读取可能带着改动之前的历史返回，作废它们；再读一次，不错过这
      // 期间开播的歌。
      _generation++;
      if (state.listens case final listens?) {
        state = state.copyWith(listens: apply(listens));
      }
      if (_reading > 0) _reloadIfOpen();
    }
    return const MutationSucceeded(null);
  }

  // 置为 null 而不是空列表：新的身份可能是已有历史的账号，游客的历史登录后
  // 也会并入账号，先显示加载中，不先闪一下空状态。
  void _changeScope() {
    _scope++;
    _generation++;
    state = HistoryState(query: state.query);
    _reloadIfOpen();
  }

  // 不在通知回调里同步读取：当前服务器的变化可能在 provider 刷新途中送达，
  // 这时读到的凭据和接口可能还是旧服务器的。
  void _reloadIfOpen() {
    if (_openPages > 0) unawaited(Future.microtask(load));
  }

  bool _isCurrent(int scope) => ref.mounted && scope == _scope;

  void _show(int generation, List<Listen> listens) {
    if (!ref.mounted || generation != _generation) return;
    state = state.copyWith(listens: listens, error: null);
  }

  void _fail(int generation, String error) {
    if (!ref.mounted || generation != _generation) return;
    state = state.copyWith(error: error);
  }

  static PlaybackIdentity? _playbackOf(RoomState room) {
    final nowPlaying = room.snapshot?.nowPlaying;
    if (nowPlaying == null) return null;
    return PlaybackIdentity(
      entryId: nowPlaying.entry.id,
      startedAtMs: nowPlaying.startedAtMs,
    );
  }
}
