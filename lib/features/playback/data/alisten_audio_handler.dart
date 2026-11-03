import 'dart:async';

import 'package:alisten/features/playback/application/audio_engine.dart';
import 'package:alisten/features/playback/data/audio_stream_factory.dart';
import 'package:alisten/features/playback/data/media_player.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';

/// 系统媒体控件的操作转为事件交给播放的所有者，因为恢复播放需要房间位置。
final class AlistenAudioHandler extends BaseAudioHandler {
  AlistenAudioHandler(
    this._player,
    this._streams, {
    required Stream<AudioInterruptionEvent> interruptions,
    required Stream<void> becomingNoisy,
  }) {
    _subscriptions
      ..add(_player.playerStateStream.listen(_onPlayerState))
      ..add(_player.errorStream.listen((_) => _onError()))
      ..add(interruptions.listen(_onInterruption))
      ..add(
        becomingNoisy.listen((_) => _emit(AudioEngineEventKind.pauseRequested)),
      );
  }

  /// [dio] 归处理器所有，随之关闭。
  static Future<AlistenAudioHandler> create(Dio dio) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    return AlistenAudioHandler(
      // 中断由播放的所有者处理，因为恢复时要按房间位置而非中断时的位置。
      JustAudioPlayer(AudioPlayer(handleInterruptions: false)),
      AudioStreamFactory(dio),
      interruptions: session.interruptionEventStream,
      becomingNoisy: session.becomingNoisyEventStream,
    );
  }

  final MediaPlayer _player;
  final AudioStreamFactory _streams;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final _events = StreamController<AudioEngineEvent>.broadcast();
  int? _load;
  bool _loading = false;
  bool _failed = false;
  AudioEngineEventKind? _reported;

  Stream<AudioEngineEvent> get events => _events.stream;

  Duration get position => _player.position;

  Future<void> loadSource(AudioLoadRequest request) async {
    final load = _load = request.load;
    _loading = true;
    _failed = false;
    _reported = null;
    _streams.cancelAll();
    final id = '${request.identity.entryId}@${request.identity.startedAtMs}';
    final shown = mediaItem.value;
    mediaItem.add(
      MediaItem(
        id: id,
        title: request.meta.title,
        artist: request.meta.artist,
        album: request.meta.album,
        // 重新加载同一次播放时保留封面，避免闪烁。
        artUri: shown?.id == id ? shown?.artUri : null,
        duration: Duration(milliseconds: request.durationMs),
      ),
    );
    _publish();
    try {
      await _player.setAudioSource(
        _streams.source(request.uri),
        initialPosition: Duration(milliseconds: request.positionMs),
      );
    } on Object {
      if (_load == load) {
        _loading = false;
        _failed = true;
        _publish();
      }
      rethrow;
    }
    if (_load != load) return;
    _loading = false;
    _publish();
    // 加载期间不报告状态变化，此处补报新音源的状态。
    _report(_player.playing, _player.processingState);
    unawaited(_showCover(load, request.coverFile));
  }

  // 只给系统媒体控件本地封面文件：给网络地址时 audio_service 会用自带缓存另行
  // 下载，不计入也无法清理设置里的图片缓存。
  Future<void> _showCover(int load, Future<Uri?> Function() coverFile) async {
    final file = await coverFile();
    final item = mediaItem.value;
    if (file == null || _load != load || item == null) return;
    if (item.artUri == file) return;
    mediaItem.add(item.copyWith(artUri: file));
  }

  Future<void> startPlayback() async {
    // just_audio 的 play() 在播放暂停、停止或结束时才完成，但会立即置
    // `playing`，所以不等待它；失败也会从错误流到达。
    unawaited(_player.play().then((_) {}, onError: (Object _) {}));
    _publish();
  }

  Future<void> pausePlayback() async {
    final paused = _player.pause();
    _publish();
    await paused;
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
    _publish();
  }

  Future<void> setPlayerVolume(double volume) => _player.setVolume(volume);

  Future<void> release() async {
    _load = null;
    _loading = false;
    _failed = false;
    _reported = null;
    _streams.cancelAll();
    await _player.stop();
    _publish();
  }

  @override
  Future<void> play() async => _emit(AudioEngineEventKind.playRequested);

  @override
  Future<void> pause() async => _emit(AudioEngineEventKind.pauseRequested);

  @override
  Future<void> skipToNext() async => _emit(AudioEngineEventKind.skipRequested);

  @override
  Future<void> stop() async {
    _emit(AudioEngineEventKind.systemStop);
    await release();
  }

  // 是否在后台继续由播放的所有者判断：两首曲目之间或通话中播放器同样处于
  // 暂停，无法据此区分本地暂停。
  @override
  Future<void> onTaskRemoved() async => _emit(AudioEngineEventKind.taskRemoved);

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    _streams.close();
    await _events.close();
  }

  void _onPlayerState(PlayerState state) {
    _publish();
    if (_loading || _load == null) return;
    _report(state.playing, state.processingState);
  }

  void _report(bool playing, ProcessingState processing) {
    final kind = switch (processing) {
      ProcessingState.idle => null,
      ProcessingState.loading || ProcessingState.buffering =>
        playing ? AudioEngineEventKind.buffering : null,
      ProcessingState.ready =>
        playing
            ? AudioEngineEventKind.playing
            : _reported == AudioEngineEventKind.playing
            ? AudioEngineEventKind.paused
            : AudioEngineEventKind.ready,
      ProcessingState.completed => AudioEngineEventKind.ended,
    };
    if (kind == null || kind == _reported) return;
    _reported = kind;
    _emit(kind, load: _load);
  }

  // 加载失败由 [loadSource] 抛出，不重复报告。
  void _onError() {
    if (_loading || _load == null) return;
    _failed = true;
    _publish();
    _emit(AudioEngineEventKind.error, load: _load);
  }

  void _onInterruption(AudioInterruptionEvent event) {
    switch (event) {
      // 系统会自动压低音乐的音量。
      case AudioInterruptionEvent(type: AudioInterruptionType.duck):
        return;
      case AudioInterruptionEvent(begin: true):
        _emit(AudioEngineEventKind.interrupted);
      case AudioInterruptionEvent(type: AudioInterruptionType.pause):
        _emit(AudioEngineEventKind.resumed);
      // 系统不允许恢复播放，例如其他应用占用了音频。
      case AudioInterruptionEvent():
        return;
    }
  }

  void _publish() {
    final playing = _player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1],
        processingState: _processingState(),
        playing: playing,
        updatePosition: _player.position,
        errorMessage: _failed ? '音频播放失败' : null,
      ),
    );
  }

  AudioProcessingState _processingState() {
    if (_load == null) return AudioProcessingState.idle;
    if (_failed) return AudioProcessingState.error;
    if (_loading) return AudioProcessingState.loading;
    return switch (_player.processingState) {
      // 两个音源之间播放器处于 idle，仍发布加载中，以免前台服务和锁屏控件消失。
      ProcessingState.idle ||
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  void _emit(AudioEngineEventKind kind, {int? load}) {
    if (_events.isClosed) return;
    _events.add(AudioEngineEvent(kind, load: load));
  }
}

final class RoomAudioEngine implements AudioEngine {
  const RoomAudioEngine(this._handler);

  final AlistenAudioHandler _handler;

  @override
  Stream<AudioEngineEvent> get events => _handler.events;

  @override
  Duration get position => _handler.position;

  @override
  Future<void> load(AudioLoadRequest request) => _handler.loadSource(request);

  @override
  Future<void> play() => _handler.startPlayback();

  @override
  Future<void> pause() => _handler.pausePlayback();

  @override
  Future<void> seek(Duration position) => _handler.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _handler.setPlayerVolume(volume);

  @override
  Future<void> release() => _handler.release();
}
