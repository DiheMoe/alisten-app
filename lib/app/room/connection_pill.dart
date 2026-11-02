import 'dart:async';

import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectionPill extends ConsumerStatefulWidget {
  const ConnectionPill({
    required this.status,
    required this.nextRetryAt,
    required this.onRetryNow,
    super.key,
  });

  final RoomConnectionStatus status;
  final DateTime? nextRetryAt;
  final VoidCallback? onRetryNow;

  @override
  ConsumerState<ConnectionPill> createState() => _ConnectionPillState();
}

class _ConnectionPillState extends ConsumerState<ConnectionPill> {
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(ConnectionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nextRetryAt != widget.nextRetryAt ||
        oldWidget.status != widget.status) {
      _follow();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // 页面不可见时不刷新倒计时，重新可见时按当前时间重新计算。
  void _follow() {
    _tick?.cancel();
    _tick = null;
    if (_waiting && _secondsLeft > 0 && TickerMode.valuesOf(context).enabled) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {});
        if (_secondsLeft <= 0) {
          _tick?.cancel();
          _tick = null;
        }
      });
    }
  }

  bool get _waiting =>
      widget.status == RoomConnectionStatus.reconnecting &&
      widget.nextRetryAt != null;

  int get _secondsLeft {
    final at = widget.nextRetryAt;
    if (at == null) return 0;
    final left = at.difference(ref.read(roomNowProvider)()).inMilliseconds;
    // 向上取整：尝试开始之前至少显示“1 秒”。
    return left <= 0 ? 0 : (left + 999) ~/ 1000;
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _secondsLeft;
    // 读屏只播报状态变化，不逐秒播报倒计时。
    final (label, spoken, icon, tone, busy) = switch (widget.status) {
      RoomConnectionStatus.open => (null, null, null, null, false),
      RoomConnectionStatus.connecting => (
        '正在连接',
        '正在连接房间',
        Icons.sync_rounded,
        StatusTone.warning,
        true,
      ),
      RoomConnectionStatus.reconnecting when _waiting && seconds > 0 => (
        '正在重连 · $seconds 秒后重试',
        '连接中断，稍后自动重连',
        Icons.cloud_off_rounded,
        StatusTone.warning,
        false,
      ),
      RoomConnectionStatus.reconnecting => (
        '正在重连',
        '连接中断，正在重连',
        Icons.sync_rounded,
        StatusTone.warning,
        true,
      ),
      RoomConnectionStatus.stopped => (
        '连接已停止',
        '与房间的连接已经停止',
        Icons.error_rounded,
        StatusTone.danger,
        false,
      ),
    };
    if (label == null || icon == null || tone == null) {
      return const SizedBox.shrink();
    }
    final onRetryNow = _waiting && seconds > 0 ? widget.onRetryNow : null;
    final retryable = onRetryNow != null;
    return Semantics(
      container: true,
      liveRegion: true,
      label: spoken,
      button: retryable,
      onTap: onRetryNow,
      onTapHint: retryable ? '立即重试' : null,
      child: ExcludeSemantics(
        child: Pressable(
          onPressed: onRetryNow,
          dimWhenDisabled: false,
          child: StatusPill(label: label, icon: icon, tone: tone, busy: busy),
        ),
      ),
    );
  }
}
