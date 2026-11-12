import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/playback/play_reminder.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/playback/playback_timeline.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/application/app_visibility.dart';
import 'package:alisten/features/playback/application/audio_engine.dart';
import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:alisten/features/playback/application/track_start_reminder.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final playbackControllerProvider =
    NotifierProvider<PlaybackController, LocalPlaybackState>(
      PlaybackController.new,
    );

typedef LivePosition = int Function();

final livePositionProvider = Provider<LivePosition>((ref) {
  final controller = ref.read(playbackControllerProvider.notifier);
  return () => controller.livePositionMs;
});

const _tick = Duration(milliseconds: 500);
final _ticksPerDriftCheck =
    playbackDriftCheckIntervalMs ~/ _tick.inMilliseconds;
const _reloadDelay = Duration(seconds: 1);
const _clockRetryDelay = Duration(milliseconds: 500);
// seek 会造成可闻的卡顿，起播位置与房间位置相差不超过此值时不 seek。
const _startToleranceMs = 100;
// 起播前在缓冲区内补跳时，目标之后要有这么多数据才能立即播放：ExoPlayer 默认
// 缓冲 2.5 秒才开始播放。
const _bufferedAheadMs = 3000;
// 下载通常比播放快得多，缓冲区很快就能越过房间位置；差得更远或等满时限时，
// 直接 seek 到缓冲区之外重新请求。
const _catchUpReachMs = 20000;
const _catchUpWait = Duration(seconds: 2);
const _catchUpPoll = Duration(milliseconds: 200);
const _maxStartSeeks = 3;
const _maxGain = 1.5;
const _logSource = 'playback';

/// 本设备上当前房间播放的所有者。每次加载都有编号，旧加载的结果和引擎事件一律
/// 丢弃，即使加载的是同一次播放。
final class PlaybackController extends Notifier<LocalPlaybackState> {
  final _reminders = PlayReminderTracker();
  late AudioEngine _engine;
  StreamSubscription<AudioEngineEvent>? _engineEvents;

  NowPlaying? _nowPlaying;
  PlaybackIdentity? _identity;
  int _load = 0;
  PlaybackIdentity? _loaded;
  bool _loading = false;
  bool _reloaded = false;
  bool _failed = false;
  bool _ended = false;
  bool _waiting = false;
  int? _seekingLoad;
  bool _enginePlaying = false;
  // 挂起时仍跟随房间加载曲目，只是不发声；系统停止后，用户恢复前不加载音源。
  bool _userPaused = false;
  bool _interrupted = false;
  bool _stopped = false;
  // 引擎自行暂停（如音频会话无法激活）时按挂起处理，到下一首再试。
  bool _enginePaused = false;
  // 引擎在应用运行期间不会更换，一旦不可用就不再加载音源，也不重试。
  bool _unavailable = false;
  PlaybackIdentity? _checkedEnd;
  Timer? _startTimer;
  Timer? _reloadTimer;
  Timer? _ticker;
  int _ticks = 0;
  DriftCorrection _drift = const DriftCorrection();

  @override
  LocalPlaybackState build() {
    _engine = ref.read(audioEngineProvider);
    final settings = ref.read(settingsControllerProvider).value;
    ref.listen(settingsControllerProvider.select((current) => current.value), (
      previous,
      next,
    ) {
      // 只取变化的字段，避免切换静音时覆盖拖动中尚未保存的音量。
      final volume = next.volume != previous?.volume ? next.volume : null;
      final muted = next.muted != previous?.muted ? next.muted : null;
      if (volume == null && muted == null) return;
      state = state.copyWith(volume: volume, muted: muted);
      unawaited(_applyVolume());
    });
    // 直接监听房间控制器：它的通知总在 Widget 构建之外到达，nowPlayingProvider
    // 这类派生 provider 不保证这一点。
    ref.listen(
      roomControllerProvider.select((room) => room.snapshot?.nowPlaying),
      (_, next) => _onNowPlaying(next),
    );
    ref.listen(roomControllerProvider.select(_inRoom), (_, inRoom) {
      if (!inRoom) _leave();
    });
    ref.listen(roomControllerProvider, (_, next) => _remind(next));
    _engineEvents = _engine.events.listen(_onEngineEvent);
    final engine = _engine;
    ref.onDispose(() {
      // 作废在途加载，避免其完成后访问已销毁的 ref。
      _load++;
      _cancelTimers();
      unawaited(_engineEvents?.cancel());
      unawaited(engine.release());
    });
    if (_roomNowPlaying() != null) {
      scheduleMicrotask(() {
        if (ref.mounted) _onNowPlaying(_roomNowPlaying());
      });
    }
    return LocalPlaybackState(volume: settings.volume, muted: settings.muted);
  }

  /// 只影响本设备，房间继续播放；恢复时按房间位置起播。两首曲目之间不起作用，
  /// 否则下一首会以暂停状态开始；本设备无法播放时也不起作用。
  Future<void> toggleLocalPause() async {
    if (_status
        case LocalPlaybackStatus.ended || LocalPlaybackStatus.unavailable) {
      return;
    }
    return _held || _failed ? _resume() : _pause();
  }

  /// 拖动滑块时传 `persist: false`，松手时才保存。
  Future<void> setVolume(int volume, {required bool persist}) async {
    final normalized = volume.clamp(0, 100);
    state = state.copyWith(volume: normalized);
    await _applyVolume();
    if (persist && ref.mounted) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setVolume(normalized, persist: true);
    }
  }

  Future<void> toggleMute() async {
    final muted = !state.muted;
    state = state.copyWith(muted: muted);
    await _applyVolume();
    if (ref.mounted) {
      await ref.read(settingsControllerProvider.notifier).setMuted(muted);
    }
  }

  /// 逐帧读取，不发布状态：音源就绪前不读引擎，它还在报上一首的位置。
  int get livePositionMs => _loaded != null && _loaded == _identity
      ? _engine.position.inMilliseconds
      : state.positionMs;

  bool get _held => _userPaused || _interrupted || _stopped || _enginePaused;

  NowPlaying? _roomNowPlaying() {
    return ref.read(roomControllerProvider).snapshot?.nowPlaying;
  }

  static bool _inRoom(RoomState room) {
    return room.activeRoomId != null && room.failure == null;
  }

  void _onNowPlaying(NowPlaying? next) {
    _nowPlaying = next;
    if (next == null) {
      final finished = _ended;
      _forget();
      // 被切掉或仍在加载的曲目不得继续发声；只暂停不释放，媒体会话留给下一首。
      if (!finished) unawaited(_engine.pause());
      _publish(positionMs: 0);
      return;
    }
    final identity = PlaybackIdentity(
      entryId: next.entry.id,
      startedAtMs: next.startedAtMs,
    );
    if (identity == _identity) {
      // 时钟校正后，此前判定放完的曲目可能其实还没放完。
      if (_ended && _loaded != identity) _begin();
      return;
    }
    _forget();
    _identity = identity;
    _begin();
  }

  void _forget() {
    _load++;
    _identity = null;
    _loaded = null;
    _loading = false;
    _reloaded = false;
    _failed = false;
    _ended = false;
    _waiting = false;
    _enginePlaying = false;
    _enginePaused = false;
    _drift = const DriftCorrection();
    _cancelTimers();
  }

  void _begin() {
    final nowPlaying = _nowPlaying!;
    final plan = _plan(nowPlaying);
    if (plan?.kind == StartPlanKind.ended) {
      // 引擎中残留的音源不属于这首曲目。
      unawaited(_engine.pause());
      _end();
      return;
    }
    _ended = false;
    if (_stopped || _unavailable) {
      _publish();
      return;
    }
    unawaited(_loadSource(nowPlaying, plan?.positionMs ?? 0));
  }

  Future<void> _loadSource(NowPlaying nowPlaying, int positionMs) async {
    final identity = _identity!;
    final load = ++_load;
    _loaded = null;
    _loading = true;
    _enginePlaying = false;
    _publish(positionMs: positionMs);
    final uri = _mediaUri(nowPlaying.mediaUrl);
    if (uri == null) {
      AppLog.warn(_logSource, 'media url refused');
      _loading = false;
      _failed = true;
      unawaited(_engine.pause());
      _publish();
      return;
    }
    final covers = ref.read(coverCacheProvider);
    final coverUrl = nowPlaying.entry.meta.coverUrl;
    try {
      await _applyVolume();
      if (load != _load) return;
      await _engine.load(
        AudioLoadRequest(
          load: load,
          identity: identity,
          uri: uri,
          meta: nowPlaying.entry.meta,
          durationMs: nowPlaying.durationMs,
          positionMs: positionMs,
          coverFile: () => _coverFile(covers, coverUrl),
        ),
      );
    } on AudioUnavailableException {
      _unavailable = true;
      if (load != _load) return;
      _loading = false;
      _publish();
      return;
    } on Object catch (error) {
      if (load != _load) return;
      AppLog.debug(_logSource, 'load failed', type: '${error.runtimeType}');
      _loading = false;
      _fail();
      return;
    }
    if (load != _load) return;
    _loading = false;
    _loaded = identity;
    _start();
  }

  static Future<Uri?> _coverFile(CoverCache covers, String url) async {
    if (url.isEmpty) return null;
    try {
      return await covers.localFile(url);
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'cover file unavailable',
        type: '${error.runtimeType}',
      );
      return null;
    }
  }

  void _start() {
    _startTimer?.cancel();
    _waiting = false;
    final nowPlaying = _nowPlaying;
    if (nowPlaying == null || _loaded == null || _loaded != _identity) return;
    if (_held) {
      _publish();
      return;
    }
    final plan = _plan(nowPlaying);
    if (plan == null) {
      _wait(_clockRetryDelay);
      return;
    }
    switch (plan.kind) {
      case StartPlanKind.wait:
        _wait(Duration(milliseconds: plan.delayMs!));
      case StartPlanKind.ended:
        unawaited(_engine.pause());
        _end();
      case StartPlanKind.play:
        unawaited(_playFrom(plan.positionMs!));
    }
  }

  void _wait(Duration delay) {
    _waiting = true;
    _stopTicker();
    unawaited(_engine.pause());
    _startTimer = Timer(delay, _start);
    _publish();
  }

  /// seek 要等到能播放才返回，这期间房间已经往前走了，所以出声前按最新的房间
  /// 位置补跳，否则刚开播就落后，随后漂移校正的 seek 听得出来。补跳尽量等到
  /// 落在已缓冲的数据里，不必重新请求。
  Future<void> _playFrom(int positionMs) async {
    final load = _load;
    _publish();
    var target = positionMs;
    for (var seeks = 0; seeks < _maxStartSeeks; seeks++) {
      final offset = _engine.position.inMilliseconds - target;
      if (offset.abs() <= _startToleranceMs) break;
      await _awaitBuffered(load);
      if (load != _load || _held) return;
      final caughtUp = _roomPosition();
      if (caughtUp == null) return _start();
      target = caughtUp;
      _publish(positionMs: target);
      await _engine.seek(Duration(milliseconds: target));
      if (load != _load || _held) return;
      final next = _roomPosition();
      if (next == null) return _start();
      target = next;
    }
    await _engine.play();
  }

  // 返回时缓冲区已越过房间位置，或者等不到。往回跳时缓冲区里没有数据。
  Future<void> _awaitBuffered(int load) async {
    for (
      var waited = Duration.zero;
      waited < _catchUpWait;
      waited += _catchUpPoll
    ) {
      final target = _roomPosition();
      if (target == null || load != _load || _held) return;
      final buffered = _engine.bufferedPosition.inMilliseconds;
      if (target < _engine.position.inMilliseconds ||
          buffered >= target + _bufferedAheadMs ||
          target - buffered > _catchUpReachMs) {
        return;
      }
      await Future<void>.delayed(_catchUpPoll);
    }
  }

  // 房间此刻的播放位置；曲目尚未开始、已经放完或时钟未知时为 null。
  int? _roomPosition() {
    final nowPlaying = _nowPlaying;
    final plan = nowPlaying == null ? null : _plan(nowPlaying);
    return plan?.kind == StartPlanKind.play ? plan!.positionMs : null;
  }

  // 每次播放只请求一次检查，因为检查带回的每个快照都会让这次播放再次结束。
  void _end() {
    _ended = true;
    _waiting = false;
    _startTimer?.cancel();
    _stopTicker();
    _publish();
    final identity = _identity;
    if (identity == null || _checkedEnd == identity) return;
    _checkedEnd = identity;
    unawaited(ref.read(roomControllerProvider.notifier).checkAfterTrackEnd());
  }

  void _fail() {
    _loaded = null;
    _enginePlaying = false;
    _stopTicker();
    if (_reloaded) {
      _failed = true;
      _publish();
      return;
    }
    _reloaded = true;
    final load = _load;
    _reloadTimer?.cancel();
    _reloadTimer = Timer(_reloadDelay, () {
      if (load == _load && _identity != null) _begin();
    });
    _publish();
  }

  Future<void> _pause() async {
    _userPaused = true;
    _startTimer?.cancel();
    _waiting = false;
    _stopTicker();
    _publish();
    await _engine.pause();
  }

  Future<void> _resume() async {
    _userPaused = false;
    _interrupted = false;
    _stopped = false;
    _enginePaused = false;
    if (_failed) {
      _failed = false;
      _reloaded = false;
    }
    _continue();
  }

  void _continue() {
    final identity = _identity;
    if (_held || identity == null) {
      _publish();
      return;
    }
    if (_loaded == identity) {
      _start();
    } else if (!_loading && !(_reloadTimer?.isActive ?? false)) {
      _begin();
    } else {
      _publish();
    }
  }

  void _interrupt() {
    if (_stopped) return;
    _interrupted = true;
    _startTimer?.cancel();
    _waiting = false;
    _stopTicker();
    unawaited(_engine.pause());
    _publish();
  }

  void _endInterruption() {
    if (!_interrupted) return;
    _interrupted = false;
    _continue();
  }

  void _systemStop() {
    _stopped = true;
    _interrupted = false;
    _load++;
    _loaded = null;
    _loading = false;
    _enginePlaying = false;
    _waiting = false;
    _cancelTimers();
    unawaited(_engine.release());
    _publish();
  }

  void _leave() {
    _forget();
    _nowPlaying = null;
    _userPaused = false;
    _interrupted = false;
    _stopped = false;
    _reminders.clear();
    unawaited(_engine.release());
    _publish(positionMs: 0);
  }

  void _onEngineEvent(AudioEngineEvent event) {
    switch (event.kind) {
      case AudioEngineEventKind.playRequested:
        // 已在播放时不再跳转到房间位置，否则会听到卡顿。
        if (_held || _failed || !_enginePlaying) unawaited(_resume());
        return;
      case AudioEngineEventKind.pauseRequested:
        unawaited(_pause());
        return;
      case AudioEngineEventKind.skipRequested:
        unawaited(_voteSkip());
        return;
      case AudioEngineEventKind.systemStop:
        _systemStop();
        return;
      case AudioEngineEventKind.taskRemoved:
        // 仅在本设备仍打算播放（含曲目间隙）时继续后台播放，挂起或失败时结束。
        if (!_inRoom(ref.read(roomControllerProvider))) {
          unawaited(_engine.release());
        } else if (_held || _failed) {
          _systemStop();
        }
        return;
      case AudioEngineEventKind.interrupted:
        _interrupt();
        return;
      case AudioEngineEventKind.resumed:
        _endInterruption();
        return;
      case AudioEngineEventKind.ready ||
          AudioEngineEventKind.buffering ||
          AudioEngineEventKind.playing ||
          AudioEngineEventKind.paused ||
          AudioEngineEventKind.ended ||
          AudioEngineEventKind.error:
        break;
    }
    if (event.load == null || event.load != _load) return;
    switch (event.kind) {
      case AudioEngineEventKind.playing:
        _enginePlaying = true;
        _startTicker();
      case AudioEngineEventKind.ended:
        _enginePlaying = false;
        _end();
        return;
      case AudioEngineEventKind.error:
        _fail();
        return;
      case AudioEngineEventKind.paused when _expectsSound:
        _enginePlaying = false;
        _enginePaused = true;
        _stopTicker();
      case _:
        _enginePlaying = false;
        _stopTicker();
    }
    _publish();
  }

  // 为 true 时，引擎报告的暂停并非本设备发起。
  bool get _expectsSound {
    return !_held && !_waiting && !_ended && _loaded == _identity;
  }

  void _startTicker() {
    if (_ticker != null) return;
    _ticks = 0;
    _ticker = Timer.periodic(_tick, (_) => _onTick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick() {
    final positionMs = _engine.position.inMilliseconds;
    _publish(positionMs: positionMs);
    if (++_ticks % _ticksPerDriftCheck == 0) {
      unawaited(_checkDrift(positionMs));
    }
  }

  Future<void> _checkDrift(int positionMs) async {
    final nowPlaying = _nowPlaying;
    final now = _serverNow();
    if (nowPlaying == null || now == null || _seekingLoad == _load) return;
    if (state.status != LocalPlaybackStatus.playing) return;
    final expected = now - nowPlaying.startedAtMs;
    if (expected < 0 || expected >= nowPlaying.durationMs) return;
    final check = _drift.check(
      positionMs: positionMs,
      expectedMs: expected,
      nowMs: now,
    );
    _drift = check.next;
    final target = check.seekToMs;
    if (target == null) return;
    final load = _seekingLoad = _load;
    try {
      await _engine.seek(Duration(milliseconds: target));
    } finally {
      if (_seekingLoad == load) _seekingLoad = null;
    }
  }

  void _cancelTimers() {
    _startTimer?.cancel();
    _reloadTimer?.cancel();
    _stopTicker();
  }

  void _publish({int? positionMs}) {
    state = LocalPlaybackState(
      status: _status,
      positionMs: positionMs ?? state.positionMs,
      durationMs: _nowPlaying?.durationMs ?? 0,
      volume: state.volume,
      muted: state.muted,
    );
  }

  LocalPlaybackStatus get _status {
    if (_identity == null) return LocalPlaybackStatus.idle;
    if (_unavailable) return LocalPlaybackStatus.unavailable;
    if (_failed) return LocalPlaybackStatus.error;
    if (_ended) return LocalPlaybackStatus.ended;
    if (_held) return LocalPlaybackStatus.paused;
    if (_loaded != _identity) return LocalPlaybackStatus.loading;
    if (_waiting) return LocalPlaybackStatus.waiting;
    if (_enginePlaying) return LocalPlaybackStatus.playing;
    return LocalPlaybackStatus.buffering;
  }

  StartPlan? _plan(NowPlaying nowPlaying) {
    final now = _serverNow();
    if (now == null) return null;
    return startPlan(now - nowPlaying.startedAtMs, nowPlaying.durationMs);
  }

  int? _serverNow() => ref.read(roomControllerProvider.notifier).serverNow;

  Uri? _mediaUri(String mediaUrl) {
    final config = ref.read(appConfigProvider);
    final Uri uri;
    try {
      uri = Uri.parse(config.baseUrl).resolve(mediaUrl);
    } on FormatException {
      return null;
    }
    final secure = uri.scheme == 'https';
    if (!secure && (uri.scheme != 'http' || config.isRelease)) return null;
    return uri;
  }

  Future<void> _applyVolume() {
    final gain = (_nowPlaying?.gain ?? 1).clamp(0.0, _maxGain);
    final volume = state.muted ? 0.0 : state.volume / 100 * gain;
    return _engine.setVolume(math.min(1, volume));
  }

  Future<void> _voteSkip() async {
    final result = await ref.read(queueActionsProvider).voteSkip();
    AppLog.debug(
      _logSource,
      'vote skip from media controls',
      type: '${result.runtimeType}',
    );
  }

  void _remind(RoomState room) {
    final now = _serverNow();
    if (now == null) return;
    final settings = ref.read(settingsControllerProvider);
    final entry = _reminders.observe(
      snapshot: room.snapshot,
      memberId: room.member?.id,
      live: room.liveUpdate,
      enabled: settings.value.reminders,
      nowMs: now,
    );
    final roomId = room.snapshot?.room.id;
    if (entry == null || roomId == null) return;
    final reminder = ref.read(trackStartReminderProvider);
    unawaited(
      reminder
          .notify(
            appVisible: ref.read(appVisibleProvider),
            enabled: settings.value.reminders,
            systemEnabled: settings.value.systemNotifications,
            permissionGranted:
                settings.permission == NotificationPermission.granted,
            roomId: roomId,
            entryId: entry.id,
            title: entry.meta.title,
          )
          .catchError((Object error) {
            AppLog.warn(_logSource, 'reminder failed');
            return false;
          }),
    );
  }
}
