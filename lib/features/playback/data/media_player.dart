import 'package:just_audio/just_audio.dart';

/// just_audio [AudioPlayer] 的子集，测试替身须保持相同语义：[play] 要等播放
/// 暂停、停止或结束才完成；[playing] 表示播放意图，由 [play] 和 [pause] 立即
/// 设置，播放结束后仍为 true；[stop] 释放平台播放器并回到 idle。
abstract interface class MediaPlayer {
  Stream<PlayerState> get playerStateStream;
  Stream<PlayerException> get errorStream;
  bool get playing;
  ProcessingState get processingState;
  Duration get position;

  /// 无法加载或被后一次调用替换时抛出异常。
  Future<void> setAudioSource(AudioSource source, {Duration? initialPosition});

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

final class JustAudioPlayer implements MediaPlayer {
  JustAudioPlayer(this._player);

  final AudioPlayer _player;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<PlayerException> get errorStream => _player.errorStream;

  @override
  bool get playing => _player.playing;

  @override
  ProcessingState get processingState => _player.processingState;

  @override
  Duration get position => _player.position;

  @override
  Future<void> setAudioSource(
    AudioSource source, {
    Duration? initialPosition,
  }) async {
    await _player.setAudioSource(source, initialPosition: initialPosition);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
