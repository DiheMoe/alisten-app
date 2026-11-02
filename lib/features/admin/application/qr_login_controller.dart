import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/image_gallery.dart';
import 'package:alisten/features/admin/application/qr_image_loader.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const qrPollInterval = Duration(seconds: 2);
const qrImageFailedText = '二维码加载失败，请重新获取';

const _rateLimitedMaxWait = Duration(seconds: 30);
const _logSource = 'admin';

enum QrPhase { starting, waiting, scanned, success, expired, failed }

enum QrSaveResult { saved, denied, failed }

final class QrLoginState {
  const QrLoginState({
    this.phase = QrPhase.starting,
    this.qqType = QqLoginType.qq,
    this.image,
    this.expiresAtMs = 0,
    this.remainingSeconds = 0,
    this.message = '',
  });

  final QrPhase phase;
  final QqLoginType qqType;
  final Uint8List? image;
  final int expiresAtMs;

  /// 只用于显示：按设备时钟计算，可能与服务端有偏差，二维码是否过期以服务端
  /// 回复为准。
  final int remainingSeconds;

  final String message;

  bool get scanning => phase == QrPhase.waiting || phase == QrPhase.scanned;

  String get statusText => switch (phase) {
    QrPhase.starting => '正在获取二维码',
    QrPhase.waiting => '等待扫码',
    QrPhase.scanned => '已扫码，请在手机上确认',
    QrPhase.success => '登录成功',
    QrPhase.expired => '二维码已过期',
    QrPhase.failed => message.isEmpty ? '登录失败' : '登录失败：$message',
  };

  QrLoginState _with({QrPhase? phase, int? remainingSeconds, String? message}) {
    return QrLoginState(
      phase: phase ?? this.phase,
      qqType: qqType,
      image: image,
      expiresAtMs: expiresAtMs,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      message: message ?? this.message,
    );
  }
}

final qrLoginControllerProvider = NotifierProvider.autoDispose
    .family<QrLoginController, QrLoginState, LoginSource>(
      QrLoginController.new,
    );

/// 扫码 key 只保存在私有字段中，不进入状态和日志，扫码结束即丢弃。
final class QrLoginController extends Notifier<QrLoginState> {
  QrLoginController(this.source);

  final LoginSource source;

  int _attempt = 0;
  ({String key, QqLoginType type})? _ticket;
  bool _paused = false;
  bool _checking = false;
  Duration _backoff = qrPollInterval;
  Timer? _tick;
  Timer? _poll;

  @override
  QrLoginState build() {
    ref.onDispose(() {
      _attempt++;
      _finish();
    });
    return const QrLoginState();
  }

  @visibleForTesting
  bool get holdsKey => _ticket != null;

  /// [qqType] 为 null 时沿用当前的扫码方式。
  Future<void> start({QqLoginType? qqType}) async {
    final attempt = ++_attempt;
    _stopTimers();
    _ticket = null;
    _checking = false;
    _backoff = qrPollInterval;
    final type = qqType ?? state.qqType;
    state = QrLoginState(qqType: type);
    final QrLoginTicket ticket;
    final Uint8List image;
    try {
      ticket = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.startQrLogin(token, source, qqType: type));
      if (!_current(attempt)) return;
      image = await ref.read(qrImageLoaderProvider).load(ticket.qrImage);
    } on AdminSessionEnded {
      return;
    } on QrImageUnavailable {
      if (_current(attempt)) _fail(qrImageFailedText);
      return;
    } on ApiException catch (error) {
      if (_current(attempt)) _fail(error.message);
      return;
    } on Object catch (error) {
      AppLog.warn(_logSource, 'qr login not started', type: _type(error));
      if (_current(attempt)) _fail('');
      return;
    }
    if (!_current(attempt)) return;
    _ticket = (key: ticket.key, type: type);
    state = QrLoginState(
      phase: QrPhase.waiting,
      qqType: type,
      image: image,
      expiresAtMs: ticket.expiresAtMs,
      remainingSeconds: _remainingSeconds(ticket.expiresAtMs),
    );
    if (_paused) return;
    _startTicking(attempt);
    _schedulePoll(attempt);
  }

  /// 已发出的查询照常采用结果，只是不再安排下一次。
  void pause() {
    _paused = true;
    _stopTimers();
  }

  /// 仍在等待扫码时立即查询一次；已有查询在途时等它返回。
  void resume() {
    if (!_paused) return;
    _paused = false;
    if (!state.scanning) return;
    _refresh();
    final attempt = _attempt;
    _startTicking(attempt);
    if (!_checking) unawaited(_check(attempt));
  }

  Future<QrSaveResult> saveImage() async {
    final image = state.image;
    if (image == null || !state.scanning) return QrSaveResult.failed;
    try {
      await ref
          .read(imageGalleryProvider)
          .saveImage(image, 'alisten-${source.name}-login');
    } on GalleryAccessDenied {
      return QrSaveResult.denied;
    } on Object {
      return QrSaveResult.failed;
    }
    return QrSaveResult.saved;
  }

  bool _current(int attempt) => ref.mounted && attempt == _attempt;

  int _remainingSeconds(int expiresAtMs) {
    final nowMs = ref.read(adminNowProvider)().millisecondsSinceEpoch;
    return math.max(0, ((expiresAtMs - nowMs) / 1000).ceil());
  }

  void _startTicking(int attempt) {
    _tick?.cancel();
    _tick = null;
    if (state.remainingSeconds == 0) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_current(attempt)) _refresh();
    });
  }

  void _schedulePoll(int attempt, [Duration wait = qrPollInterval]) {
    _poll?.cancel();
    _poll = Timer(wait, () => unawaited(_check(attempt)));
  }

  Duration _rateLimitedWait(Duration? retryAfter) {
    _backoff = _backoff * 2;
    if (_backoff > _rateLimitedMaxWait) _backoff = _rateLimitedMaxWait;
    final wait = retryAfter ?? _backoff;
    if (wait < qrPollInterval) return qrPollInterval;
    if (wait > _rateLimitedMaxWait) return _rateLimitedMaxWait;
    return wait;
  }

  void _refresh() {
    if (!state.scanning) return;
    final remaining = _remainingSeconds(state.expiresAtMs);
    if (remaining != state.remainingSeconds) {
      state = state._with(remainingSeconds: remaining);
    }
    if (remaining == 0) {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _check(int attempt) async {
    final ticket = _ticket;
    if (ticket == null || _checking || !_current(attempt)) return;
    _checking = true;
    final QrLoginCheck result;
    try {
      result = await ref
          .read(adminSessionProvider.notifier)
          .run(
            (api, token) => api.checkQrLogin(
              token,
              source,
              ticket.key,
              qqType: ticket.type,
            ),
          );
    } on AdminSessionEnded {
      if (!_current(attempt)) return;
      _checking = false;
      _finish();
      return;
    } on ApiException catch (error) {
      if (!_current(attempt)) return;
      _checking = false;
      if (!state.scanning) return;
      // 只在回复丢失或被限流时重试：查询只读取扫码状态，重发无害，而服务端可能
      // 已经保存了登录信息。收到回复却无法解码说明协议不兼容，重试无用，需提示
      // 升级。
      if (error.code == LocalErrorCodes.network) {
        AppLog.debug(_logSource, 'qr login check lost', code: error.code);
        if (!_paused) _schedulePoll(attempt);
      } else if (error.rateLimited) {
        AppLog.debug(_logSource, 'qr login check limited', code: error.code);
        final wait = _rateLimitedWait(error.retryAfter);
        if (!_paused) _schedulePoll(attempt, wait);
      } else {
        _fail(error.message);
      }
      return;
    } on Object catch (error) {
      AppLog.warn(_logSource, 'qr login not checked', type: _type(error));
      if (!_current(attempt)) return;
      _checking = false;
      if (state.scanning) _fail('');
      return;
    }
    if (!_current(attempt)) return;
    _checking = false;
    _backoff = qrPollInterval;
    _apply(result, attempt);
  }

  void _apply(QrLoginCheck result, int attempt) {
    if (!state.scanning) return;
    switch (result.state) {
      case QrCheckState.waiting || QrCheckState.scanned:
        state = state._with(
          phase: result.state == QrCheckState.waiting
              ? QrPhase.waiting
              : QrPhase.scanned,
          message: result.message,
        );
        if (!_paused) _schedulePoll(attempt);
      case QrCheckState.success:
        _finish();
        state = state._with(phase: QrPhase.success, message: result.message);
      case QrCheckState.expired:
        _finish();
        state = state._with(phase: QrPhase.expired, message: result.message);
      case QrCheckState.failed:
        _fail(result.message);
    }
  }

  void _fail(String message) {
    _finish();
    state = state._with(phase: QrPhase.failed, message: message);
  }

  void _finish() {
    _stopTimers();
    _ticket = null;
  }

  void _stopTimers() {
    _tick?.cancel();
    _tick = null;
    _poll?.cancel();
    _poll = null;
  }

  static String _type(Object error) => '${error.runtimeType}';
}
