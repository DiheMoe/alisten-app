import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:flutter/material.dart';

typedef LocalPlaybackNote = ({
  String text,
  IconData icon,

  /// 显示转动的指示器而非 [icon]。
  bool busy,

  /// 点按说明会重试。
  bool failed,
});

LocalPlaybackNote? localPlaybackNote(LocalPlaybackStatus status) {
  return switch (status) {
    LocalPlaybackStatus.idle || LocalPlaybackStatus.playing => null,
    LocalPlaybackStatus.waiting => (
      text: '等待开播',
      icon: Icons.schedule_rounded,
      busy: false,
      failed: false,
    ),
    LocalPlaybackStatus.loading => (
      text: '加载中',
      icon: Icons.downloading_rounded,
      busy: true,
      failed: false,
    ),
    LocalPlaybackStatus.buffering => (
      text: '缓冲中',
      icon: Icons.downloading_rounded,
      busy: true,
      failed: false,
    ),
    LocalPlaybackStatus.paused => (
      text: '本机已暂停',
      icon: Icons.pause_circle_rounded,
      busy: false,
      failed: false,
    ),
    LocalPlaybackStatus.ended => (
      text: '等待下一首',
      icon: Icons.hourglass_bottom_rounded,
      busy: false,
      failed: false,
    ),
    LocalPlaybackStatus.error => (
      text: '播放失败，点按重试',
      icon: Icons.error_rounded,
      busy: false,
      failed: true,
    ),
    // 重试无效，所以不像播放失败那样提供重试。
    LocalPlaybackStatus.unavailable => (
      text: '本机无法播放，请重启应用',
      icon: Icons.volume_off_rounded,
      busy: false,
      failed: false,
    ),
  };
}

/// 两首之间暂停会挂起下一首，本设备无法播放时点按无效，因此控件只说明情况。
bool isPlaybackControlInert(LocalPlaybackStatus status) =>
    status == LocalPlaybackStatus.ended ||
    status == LocalPlaybackStatus.unavailable;

/// 此时暂停按钮要表明即将发声，而不是看起来像在播放。
bool isPendingPlayback(LocalPlaybackStatus status) => switch (status) {
  LocalPlaybackStatus.waiting ||
  LocalPlaybackStatus.loading ||
  LocalPlaybackStatus.buffering ||
  LocalPlaybackStatus.ended => true,
  _ => false,
};
