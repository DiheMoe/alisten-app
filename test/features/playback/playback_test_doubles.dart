import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/application/audio_engine.dart';
import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:alisten/features/playback/application/playback_controller.dart';
import 'package:alisten/features/playback/application/track_start_reminder.dart';
import 'package:alisten/features/playback/data/media_player.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/cover_cache_test_doubles.dart';
import '../../domain/room/room_fixtures.dart';
import '../lobby/lobby_test_doubles.dart';
import '../room/room_test_doubles.dart';
import '../settings/settings_test_doubles.dart';

const trackStart = 1000000;

const playbackIdentity = PlaybackIdentity(
  entryId: 'entry-id',
  startedAtMs: trackStart,
);

final testAppConfig = AppConfig(
  baseUrl: 'http://server.test',
  isRelease: false,
  allowCleartext: true,
);

NowPlaying nowPlayingWith({
  String entryId = 'entry-id',
  int startedAtMs = trackStart,
  int durationMs = 180000,
  double gain = 1,
  String mediaUrl = '/media/netease/track-id',
}) {
  return NowPlaying(
    entry: QueueEntry(
      id: entryId,
      track: testTrack,
      meta: testTrackMeta,
      requestedBy: testMember,
      auto: false,
      likes: 0,
      status: QueueEntryStatus.ready,
    ),
    mediaUrl: mediaUrl,
    startedAtMs: startedAtMs,
    durationMs: durationMs,
    gain: gain,
    lyric: '',
  );
}

RoomSnapshot snapshotWith(NowPlaying? nowPlaying) {
  final snapshot = testRoomSnapshot();
  return RoomSnapshot(
    term: snapshot.term,
    seq: snapshot.seq,
    room: snapshot.room,
    playMode: snapshot.playMode,
    nowPlaying: nowPlaying,
    pending: snapshot.pending,
    items: snapshot.items,
    members: snapshot.members,
    onlineCount: snapshot.onlineCount,
  );
}

/// 契约与基于 just_audio 的 audio handler 相同：事件异步到达；[load] 耗时
/// [loadDuration]，保留播放意图后报告新音源的状态；[play] 开始播放即返回；
/// 只有播放已加载的音源时位置才前进，播放中 seek 之后要再过 [seekLag] 才前进；
/// [release] 停止播放并卸载音源。
final class FakeAudioEngine implements AudioEngine {
  FakeAudioEngine({int Function()? now}) : _now = now ?? (() => 0);

  final int Function() _now;
  final _events = StreamController<AudioEngineEvent>.broadcast();
  final List<AudioLoadRequest> requests = [];
  final List<Duration> seeks = [];
  final List<double> volumes = [];

  final List<String> calls = [];
  Duration loadDuration = Duration.zero;
  Duration seekLag = Duration.zero;
  int loadFailures = 0;

  Exception loadError = Exception('load failed');
  int playCalls = 0;
  int pauseCalls = 0;
  int releaseCalls = 0;
  bool _playing = false;
  int? _loaded;
  int _anchorMs = 0;
  int? _runningSince;

  int get loadCalls => requests.length;

  /// 播放意图，语义同 just_audio 的 `playing`。
  bool get playing => _playing;

  @override
  Stream<AudioEngineEvent> get events => _events.stream;

  @override
  Duration get position => Duration(milliseconds: _positionMs);

  int get _positionMs {
    final since = _runningSince;
    return since == null ? _anchorMs : _anchorMs + math.max(0, _now() - since);
  }

  @override
  Future<void> load(AudioLoadRequest request) async {
    requests.add(request);
    calls.add('load');
    _loaded = null;
    _hold(request.positionMs);
    if (loadDuration > Duration.zero) {
      await Future<void>.delayed(loadDuration);
    }
    if (!identical(requests.last, request)) {
      throw StateError('Loading interrupted');
    }
    if (loadFailures > 0) {
      loadFailures--;
      throw loadError;
    }
    _loaded = request.load;
    if (_playing) _runningSince = _now();
    _emitSource(
      _playing ? AudioEngineEventKind.playing : AudioEngineEventKind.ready,
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    calls.add('play');
    if (_playing) return;
    _playing = true;
    if (_loaded == null) return;
    _runningSince = _now();
    _emitSource(AudioEngineEventKind.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    calls.add('pause');
    if (!_playing) return;
    _playing = false;
    _hold(_positionMs);
    if (_loaded != null) _emitSource(AudioEngineEventKind.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    calls.add('seek ${position.inMilliseconds}');
    _anchorMs = position.inMilliseconds;
    if (_runningSince != null) {
      _runningSince = _now() + seekLag.inMilliseconds;
    }
  }

  // 模拟一次平台往返。
  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> release() async {
    releaseCalls++;
    calls.add('release');
    _playing = false;
    _loaded = null;
    _hold(0);
  }

  void drift(int ms) => _anchorMs += ms;

  /// 模拟 just_audio 自行收回 `playing`，例如无法激活音频会话时。
  void pauseItself() {
    _playing = false;
    _hold(_positionMs);
    _emitSource(AudioEngineEventKind.paused);
  }

  /// 与 just_audio 一致：播放到结尾后 `playing` 保持不变。
  void end() {
    _hold(_positionMs);
    _emitSource(AudioEngineEventKind.ended);
  }

  void fail() {
    _hold(_positionMs);
    _emitSource(AudioEngineEventKind.error);
    _loaded = null;
  }

  void emit(AudioEngineEventKind kind) => _events.add(AudioEngineEvent(kind));

  void _hold(int positionMs) {
    _anchorMs = positionMs;
    _runningSince = null;
  }

  void _emitSource(AudioEngineEventKind kind) {
    _events.add(AudioEngineEvent(kind, load: _loaded));
  }
}

/// 语义与 just_audio 相同：状态只在确有变化时异步到达；[play] 立即设置
/// `playing`，播放暂停、停止或结束后才完成；播放结束后 `playing` 保持不变；
/// [stop] 使播放器回到 idle。
final class FakeMediaPlayer implements MediaPlayer {
  final _states = StreamController<PlayerState>.broadcast();
  final _errors = StreamController<PlayerException>.broadcast();
  bool _playing = false;
  ProcessingState _processing = ProcessingState.idle;
  PlayerState? _lastState;
  Completer<void>? _playback;
  Duration _position = Duration.zero;
  int sourceLoads = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  @override
  Stream<PlayerException> get errorStream => _errors.stream;

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState => _processing;

  @override
  Duration get position => _position;

  @override
  Future<void> setAudioSource(
    AudioSource source, {
    Duration? initialPosition,
  }) async {
    sourceLoads++;
    _position = initialPosition ?? Duration.zero;
    _setProcessing(ProcessingState.loading);
    await Future<void>.delayed(Duration.zero);
    _setProcessing(ProcessingState.ready);
  }

  @override
  Future<void> play() {
    playCalls++;
    if (_playing) return Future.value();
    _playing = true;
    _emit();
    return (_playback = Completer<void>()).future;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (!_playing) return;
    _playing = false;
    _emit();
    _finishPlayback();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
  }

  // 模拟一次平台往返。
  @override
  Future<void> setVolume(double volume) async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _playing = false;
    _processing = ProcessingState.idle;
    _emit();
    _finishPlayback();
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _errors.close();
  }

  void complete() {
    _setProcessing(ProcessingState.completed);
    _finishPlayback();
  }

  void _setProcessing(ProcessingState processing) {
    _processing = processing;
    _emit();
  }

  void _emit() {
    final state = PlayerState(_playing, _processing);
    final last = _lastState;
    if (last != null &&
        last.playing == state.playing &&
        last.processingState == state.processingState) {
      return;
    }
    _lastState = state;
    _states.add(state);
  }

  void _finishPlayback() {
    final playback = _playback;
    _playback = null;
    if (playback != null && !playback.isCompleted) playback.complete();
  }
}

final class FakeTrackStartReminder implements TrackStartReminder {
  final List<String> entryIds = [];

  final List<bool> visibility = [];

  @override
  Future<bool> notify({
    required bool appVisible,
    required bool enabled,
    required bool systemEnabled,
    required bool permissionGranted,
    required String roomId,
    required String entryId,
    required String title,
  }) async {
    entryIds.add(entryId);
    visibility.add(appVisible);
    return true;
  }
}

/// 房间控制器和播放控制器是真实的，并像应用中一样由根监听器保持存活；连接、
/// 音频、时间和封面缓存是假的。
final class PlaybackHarness {
  /// 传入 [audioEngine] 时由它取代 [engine]，[engine] 不再使用。
  PlaybackHarness(
    this.async, {
    AppConfig? config,
    AudioEngine? audioEngine,
    FakeCoverCache? covers,
  }) : covers = covers ?? FakeCoverCache() {
    // 偏好设置只经微任务加载，在 fake-async 中清空微任务即可取得。
    SharedPreferences.setMockInitialValues({});
    late final SharedPreferences preferences;
    unawaited(
      SharedPreferences.getInstance().then((loaded) => preferences = loaded),
    );
    async.flushMicrotasks();
    int localNow() => 5000000 + async.elapsed.inMilliseconds;
    engine = FakeAudioEngine(now: localNow);
    factory = FakeRoomTransportFactory(now: localNow);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        alistenApiProvider.overrideWithValue(
          FakeAlistenApi()..rooms = [roomListing()],
        ),
        credentialStoreProvider.overrideWithValue(
          FakeCredentialStore()..tickets['room-id'] = 'saved-ticket',
        ),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(),
        audioEngineProvider.overrideWithValue(audioEngine ?? engine),
        appConfigProvider.overrideWithValue(config ?? testAppConfig),
        trackStartReminderProvider.overrideWithValue(reminder),
        coverCacheProvider.overrideWithValue(this.covers),
        ...settingsOverrides(),
      ],
    );
    container.listen(
      playbackControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    unawaited(room.openRoom('listen'));
    async.flushMicrotasks();
  }

  int livePosition() => container.read(livePositionProvider)();

  final FakeAsync async;
  final FakeCoverCache covers;
  final reminder = FakeTrackStartReminder();
  late final FakeAudioEngine engine;
  late final FakeRoomTransportFactory factory;
  late final ProviderContainer container;
  int _seq = 1;

  FakeRoomTransport get transport => factory.last;

  RoomController get room => container.read(roomControllerProvider.notifier);

  PlaybackController get playback =>
      container.read(playbackControllerProvider.notifier);

  LocalPlaybackState get state => container.read(playbackControllerProvider);

  int get serverNow => room.serverNow!;

  void hello(NowPlaying? nowPlaying, {required int serverNow}) {
    transport.emitHello(snapshotWith(nowPlaying), serverNow);
    async.flushMicrotasks();
  }

  void play(NowPlaying? nowPlaying) {
    transport.emit(
      RoomEventReceived(
        PlaybackUpdatedEvent(term: 1, seq: ++_seq, nowPlaying: nowPlaying),
      ),
    );
    async.flushMicrotasks();
  }

  /// 模拟发现服务端时钟比当前估计快 [ms]。
  void shiftClock(int ms) {
    final local = transport.clock.now();
    transport.clock.addSample(local, local, serverNow + ms);
  }

  void dispose() {
    container.dispose();
    async.flushMicrotasks();
  }
}
