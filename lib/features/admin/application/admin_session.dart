import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_api.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const adminBackgroundLimit = Duration(minutes: 5);
const adminTokenInvalidText = '管理 token 无效';
const adminDisabledText = '这个服务器没有启用后台';
const adminTokenExpiredText = '管理 token 已失效，请重新输入';
const adminAwayText = '离开后台超过 5 分钟，请重新输入管理 token';

const _unauthorized = 'UNAUTHORIZED';
const _forbidden = 'FORBIDDEN';
const _unexpected = 'UNEXPECTED';
const _unverifiedText = '没能验证管理 token，请稍后重试。';
const _sessionEndedText = '后台会话已结束';
const _logSource = 'admin';

// 这两种错误下变更可能已部分生效：修改房间依次写入别名、名称和简介、密码，
// 中途失败不回滚；超时之后写入仍可能执行。
const _unfinished = {'UNAVAILABLE', 'INTERNAL'};

// 离开前台的时长同时用两个时钟计量并取较长者：设备休眠时单调时钟可能停走，
// 墙上时钟可能被回拨。
final adminNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final adminElapsedProvider = Provider<Duration Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
});

final adminTimerProvider =
    Provider<Timer Function(Duration duration, void Function() callback)>(
      (ref) => Timer.new,
    );

final class AdminSessionEnded implements Exception {
  const AdminSessionEnded({this.resultUnknown = false});

  final bool resultUnknown;
}

final class AdminSessionState {
  const AdminSessionState({this.active = false, this.notice, this.epoch = 0});

  final bool active;

  final String? notice;

  /// 离开前台满 [adminBackgroundLimit] 时递增，用于丢弃 token 页中尚未提交的
  /// 输入。
  final int epoch;
}

sealed class AdminSignIn {
  const AdminSignIn();
}

final class AdminSignedIn extends AdminSignIn {
  const AdminSignedIn();
}

final class AdminSignInRejected extends AdminSignIn {
  const AdminSignInRejected({required this.code, required this.message});

  final String code;
  final String message;
}

final adminSessionProvider = NotifierProvider<AdminSession, AdminSessionState>(
  AdminSession.new,
);

/// 管理 token 只保存在私有字段中，不得进入状态、存储、日志或崩溃报告。
final class AdminSession extends Notifier<AdminSessionState> {
  String? _token;
  String? _serverId;

  // 会话开始、结束或离开前台超时都会递增，等待期间编号变化的结果一律丢弃。
  int _generation = 0;
  ({DateTime wall, Duration monotonic})? _awaySince;
  Timer? _awayTimer;

  @override
  AdminSessionState build() {
    ref.onDispose(() => _awayTimer?.cancel());
    return const AdminSessionState();
  }

  /// 验证期间会话结束或服务器切换时抛 [AdminSessionEnded]。
  Future<AdminSignIn> signIn(String token) async {
    final trimmed = token.trim();
    final serverId = _currentServerId();
    final generation = _generation;
    try {
      await ref.read(adminApiProvider).listRooms(trimmed);
    } on ApiException catch (error) {
      _ensureCurrent(generation, serverId);
      return AdminSignInRejected(
        code: error.code,
        message: switch (error.code) {
          _unauthorized => adminTokenInvalidText,
          _forbidden => adminDisabledText,
          _ => error.message,
        },
      );
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'sign in not verified',
        type: '${error.runtimeType}',
      );
      _ensureCurrent(generation, serverId);
      return const AdminSignInRejected(
        code: _unexpected,
        message: _unverifiedText,
      );
    }
    _ensureCurrent(generation, serverId);
    _token = trimmed;
    _serverId = serverId;
    _generation++;
    state = AdminSessionState(active: true, epoch: state.epoch);
    return const AdminSignedIn();
  }

  /// 没有 token、token 属于其他服务器或等待期间会话结束时抛
  /// [AdminSessionEnded]，最后一种情况结果未知。服务端回复 `UNAUTHORIZED`、
  /// `FORBIDDEN` 时结束会话并抛 [AdminSessionEnded]，其他错误原样抛出。
  Future<T> run<T>(
    Future<T> Function(AdminApi api, String token) operation,
  ) async {
    final token = _token;
    final serverId = _serverId;
    if (token == null || serverId == null) throw const AdminSessionEnded();
    if (serverId != _currentServerId()) {
      end();
      throw const AdminSessionEnded();
    }
    final generation = _generation;
    final T result;
    try {
      result = await operation(ref.read(adminApiProvider), token);
    } on Object catch (error) {
      _ensureCurrent(generation, serverId);
      if (error is ApiException) {
        switch (error.code) {
          case _unauthorized:
            end(notice: adminTokenExpiredText);
            throw const AdminSessionEnded();
          case _forbidden:
            end(notice: adminDisabledText);
            throw const AdminSessionEnded();
        }
      }
      rethrow;
    }
    _ensureCurrent(generation, serverId);
    return result;
  }

  /// 经 [run] 发出变更，从不重发。会话结束时，未发出的请求得到
  /// [MutationNotSent]（文案为 [sessionEnded]），已发出的得到
  /// [MutationUnknown]；被限流时请求未执行，得到 [MutationNotSent]。这三种情况
  /// 都不调用 [reread]；其余结果交给 [reread]，等它完成后才返回。
  /// [refusals] 按错误码映射服务端拒绝时的文案，[unexpected] 是意外错误的日志
  /// 事件。
  Future<MutationResult<T>> change<T>(
    Future<T> Function(AdminApi api, String token) operation, {
    required String unexpected,
    required Future<void> Function(MutationResult<T> result) reread,
    Map<String, String> refusals = const {},
    String sessionEnded = _sessionEndedText,
  }) async {
    MutationResult<T> result;
    try {
      result = MutationSucceeded(await run(operation));
    } on AdminSessionEnded catch (ended) {
      if (ended.resultUnknown) return MutationUnknown<T>();
      return MutationNotSent<T>(sessionEnded);
    } on ApiException catch (error) {
      if (error.rateLimited) return MutationNotSent<T>(error.message);
      result = switch (refusals[error.code]) {
        final text? => MutationFailed(error.code, text),
        null when error.answerLost || _unfinished.contains(error.code) =>
          MutationUnknown<T>(),
        null => MutationFailed(error.code, error.message),
      };
    } on Object catch (error) {
      AppLog.warn(_logSource, unexpected, type: '${error.runtimeType}');
      result = MutationUnknown<T>();
    }
    await reread(result);
    return result;
  }

  void end({String? notice}) {
    _token = null;
    _serverId = null;
    _generation++;
    state = AdminSessionState(notice: notice, epoch: state.epoch);
  }

  void clearNotice() {
    if (state.notice == null) return;
    state = AdminSessionState(active: state.active, epoch: state.epoch);
  }

  // 从首次报告离开前台时开始计时：离开时平台先后报告 hidden 和 paused，
  // Android 回到前台时还会先报告一次 hidden。
  void handleLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        if (_awaySince == null) _leave();
      case AppLifecycleState.resumed:
        final since = _awaySince;
        final pending = _awayTimer;
        _awaySince = null;
        _awayTimer = null;
        pending?.cancel();
        // 计时器已触发时，会话已按离开超时结束过，不再重复结束。
        if (since != null && pending != null && _awayTooLong(since)) _expire();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  // 后台放歌时进程持续运行，不能等回到前台才清除。设备休眠时计时器可能晚到，
  // 所以回到前台时再按两个时钟检查一次。
  void _leave() {
    _awaySince = (
      wall: ref.read(adminNowProvider)(),
      monotonic: ref.read(adminElapsedProvider)(),
    );
    _awayTimer = ref.read(adminTimerProvider)(adminBackgroundLimit, () {
      _awayTimer = null;
      AppLog.info(_logSource, 'session ended while away');
      _expire();
    });
  }

  bool _awayTooLong(({DateTime wall, Duration monotonic}) since) {
    final wall = ref.read(adminNowProvider)().difference(since.wall);
    final monotonic = ref.read(adminElapsedProvider)() - since.monotonic;
    return wall.isNegative ||
        wall >= adminBackgroundLimit ||
        monotonic >= adminBackgroundLimit;
  }

  // 没有会话时也要作废：等待中的验证和输入框里的 token 同样受离开时限约束。
  void _expire() {
    _generation++;
    state = AdminSessionState(
      active: state.active,
      notice: state.notice,
      epoch: state.epoch + 1,
    );
    if (_token != null) end(notice: adminAwayText);
  }

  String _currentServerId() => ref.read(appConfigProvider).serverId;

  // 调用时请求已经发出，所以结果未知。
  void _ensureCurrent(int generation, String serverId) {
    if (!ref.mounted || generation != _generation) {
      throw const AdminSessionEnded(resultUnknown: true);
    }
    if (serverId != _currentServerId()) {
      if (_serverId != null) end();
      throw const AdminSessionEnded(resultUnknown: true);
    }
  }
}
