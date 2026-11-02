import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class AudioLoadRequest {
  const AudioLoadRequest({
    required this.load,
    required this.identity,
    required this.uri,
    required this.meta,
    required this.durationMs,
    required this.positionMs,
    this.coverFile = _noCoverFile,
  });

  /// 关于该音源的事件都带上它，以区分同一次播放中更早加载发出的事件。
  final int load;
  final PlaybackIdentity identity;
  final Uri uri;
  final TrackMeta meta;
  final int durationMs;
  final int positionMs;

  /// 通知和锁屏只显示本地封面文件；取不到时为 null，从不抛出。可能需要下载，
  /// 须在音源加载完成后调用，避免与音频争抢网络。
  final Future<Uri?> Function() coverFile;
}

Future<Uri?> _noCoverFile() async => null;

enum AudioEngineEventKind {
  ready,

  /// 应当播放时正在加载或等待数据。
  buffering,
  playing,
  paused,
  ended,

  /// 加载完成后出错；加载本身失败由 [AudioEngine.load] 抛出。
  error,
  interrupted,

  /// 中断结束，可以再次播放。
  resumed,
  playRequested,

  /// 用户要求暂停，或耳机被拔出。
  pauseRequested,
  skipRequested,

  /// 系统停止播放并结束了媒体会话。
  systemStop,
  taskRemoved,
}

final class AudioEngineEvent {
  const AudioEngineEvent(this.kind, {this.load});

  final AudioEngineEventKind kind;

  /// 音频会话和媒体控件事件为 null。
  final int? load;
}

/// 本设备无法播放（如音频服务未能启动），之后的加载同样会失败，不必重试。
final class AudioUnavailableException implements Exception {
  const AudioUnavailableException();
}

/// 更换音源时保留媒体会话及其通知和前台服务，只有 [release] 才结束它们。
abstract interface class AudioEngine {
  Stream<AudioEngineEvent> get events;
  Duration get position;

  /// 音源可以播放时完成，无法加载时抛出异常。不改变播放状态：正在播放的引擎
  /// 换上新音源后继续播放。
  Future<void> load(AudioLoadRequest request);

  /// 开始播放即返回，不等播放结束。
  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setVolume(double volume);

  Future<void> release();
}

final audioEngineProvider = Provider<AudioEngine>((ref) {
  throw UnimplementedError('audioEngine 未注入');
});
