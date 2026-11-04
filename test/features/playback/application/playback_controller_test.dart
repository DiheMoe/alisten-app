import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playback/application/audio_engine.dart';
import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:alisten/features/playback/data/alisten_audio_handler.dart';
import 'package:alisten/features/playback/data/audio_stream_factory.dart';
import 'package:alisten/features/playback/data/unavailable_audio_engine.dart';
import 'package:alisten/features/room/index.dart' show trackEndSyncGrace;
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/cache/cover_cache_test_doubles.dart';
import '../../../domain/room/room_fixtures.dart';
import '../playback_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void run(void Function(PlaybackHarness h) body) {
    fakeAsync((async) {
      final harness = PlaybackHarness(async);
      body(harness);
      harness.dispose();
    });
  }

  test('the same playback named twice while it loads is loaded once, '
      'and its end is handled with one connection check', () {
    run((h) {
      h.engine.loadDuration = const Duration(milliseconds: 500);
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      // 加载完成前，同步或事件再次送来同一次播放。
      h.play(nowPlayingWith());
      h.async.elapse(const Duration(seconds: 1));

      expect(h.engine.loadCalls, 1);
      expect(h.engine.requests.single.identity, playbackIdentity);
      expect(h.state.status, LocalPlaybackStatus.playing);

      final probes = h.transport.probeCalls;
      h.engine.end();
      h.async.flushMicrotasks();

      expect(h.state.status, LocalPlaybackStatus.ended);
      expect(h.transport.probeCalls, probes + 1);
      expect(h.engine.loadCalls, 1, reason: 'no local next track');
    });
  });

  test('a track that ends after a failed sync waits the grace, then '
      'synchronises the room once and plays the track that sync brings; '
      'later changes while ended do not synchronise again', () {
    run((h) {
      h.hello(nowPlayingWith(durationMs: 60000), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      expect(h.state.status, LocalPlaybackStatus.playing);

      // 下一首的事件跳过了一个序号，由此触发的同步又失败，本设备因而不知道这首
      // 曲目。
      final next = nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow);
      h.transport.syncError = const RoomRequestException(
        message: '请求超时',
        outcome: RoomRequestOutcome.failed,
      );
      h.transport.emit(
        RoomEventReceived(
          PlaybackUpdatedEvent(term: 1, seq: 3, nowPlaying: next),
        ),
      );
      h.async.flushMicrotasks();
      expect(h.room.state.snapshot?.nowPlaying?.entry.id, 'entry-id');

      h.transport
        ..syncError = null
        ..nextSnapshot = snapshotWith(next).copyWith(term: 1, seq: 3);
      final syncs = h.transport.syncCalls;
      final probes = h.transport.probeCalls;
      h.engine.end();
      h.async.flushMicrotasks();
      expect(h.transport.probeCalls, probes + 1, reason: 'probed at once');

      h.async.elapse(trackEndSyncGrace - const Duration(milliseconds: 100));
      expect(h.transport.syncCalls, syncs);
      h.async.elapse(const Duration(milliseconds: 100));
      expect(h.transport.syncCalls, syncs + 1);
      expect(h.room.state.snapshot?.nowPlaying?.entry.id, 'next');
      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.requests.last.identity.entryId, 'next');
      expect(h.state.status, LocalPlaybackStatus.playing);

      // 下一首放完时，房间里还没有再下一首。
      h.engine.end();
      h.async.elapse(trackEndSyncGrace);
      expect(h.transport.syncCalls, syncs + 2);
      expect(h.state.status, LocalPlaybackStatus.ended);

      h.engine.end();
      for (var seq = 4; seq < 8; seq++) {
        h.transport.emit(
          RoomEventReceived(
            seq.isEven
                ? PlaybackUpdatedEvent(term: 1, seq: seq, nowPlaying: next)
                : SettingsUpdatedEvent(
                    term: 1,
                    seq: seq,
                    playMode:
                        RoomPlayMode.values[seq % RoomPlayMode.values.length],
                  ),
          ),
        );
        h.async.flushMicrotasks();
      }
      h.async.elapse(trackEndSyncGrace * 2);

      expect(h.transport.syncCalls, syncs + 2);
      expect(h.room.state.snapshot?.seq, 7);
      expect(h.state.status, LocalPlaybackStatus.ended);
      expect(h.engine.loadCalls, 2);
    });
  });

  test('a track end followed within the grace by the next track, live, '
      'synchronises nothing and still reminds of an own track', () {
    run((h) {
      final next = nowPlayingWith(
        entryId: 'next',
        startedAtMs: trackStart + 60000,
      );
      h.transport.emitHello(
        snapshotWith(nowPlayingWith(durationMs: 60000))
            .copyWith(term: 1, seq: 1, items: [next.entry]),
        trackStart + 20000,
      );
      h.async.elapse(const Duration(seconds: 40));
      expect(h.state.status, LocalPlaybackStatus.playing);

      // 同步要一个往返之后才有回复，期间的实时事件会被丢弃。
      h.transport.holdSyncs = true;
      final syncs = h.transport.syncCalls;
      final probes = h.transport.probeCalls;
      h.engine.end();
      h.async.elapse(const Duration(seconds: 1));
      expect(h.transport.probeCalls, probes + 1);

      h.play(next);
      h.async.elapse(trackEndSyncGrace * 2);

      expect(h.transport.syncCalls, syncs);
      expect(h.room.state.snapshot?.nowPlaying?.entry.id, 'next');
      expect(h.reminder.entryIds, ['next']);
      expect(h.engine.requests.last.identity.entryId, 'next');
      expect(h.state.status, LocalPlaybackStatus.playing);
    });
  });

  test('leaving the room while a track end waits for the next track '
      'synchronises nothing, also once the room is entered again', () {
    run((h) {
      h.hello(nowPlayingWith(durationMs: 60000), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      final left = h.transport;
      final syncs = left.syncCalls;
      h.engine.end();
      h.async.elapse(const Duration(seconds: 1));

      unawaited(h.room.leaveRoom());
      h.async.flushMicrotasks();
      unawaited(h.room.openRoom('listen'));
      h.async.flushMicrotasks();
      expect(h.transport, isNot(same(left)));
      h.hello(nowPlayingWith(durationMs: 60000), serverNow: trackStart + 32000);
      h.async.elapse(trackEndSyncGrace * 2);

      expect(left.syncCalls, syncs);
      expect(h.transport.syncCalls, 0);
    });
  });

  test('a slow load starts at the room position of when it is loaded', () {
    run((h) {
      h.engine.loadDuration = const Duration(milliseconds: 1500);
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 2));

      expect(h.engine.requests.single.positionMs, 30000);
      expect(h.engine.seeks.single.inMilliseconds, closeTo(31500, 50));
      expect(h.engine.calls.last, 'play');
      expect(h.engine.calls.indexOf('play'), greaterThan(1));
    });
  });

  test('the start timer plans again when it fires', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart - 2000);
      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.loadCalls, 1, reason: 'loaded at once, before start');
      expect(h.state.status, LocalPlaybackStatus.waiting);
      expect(h.engine.playCalls, 0);

      // 时钟原先慢了 5 秒，例如设备休眠之后。
      h.shiftClock(5000);
      h.async.elapse(const Duration(seconds: 1));

      expect(h.engine.seeks.single.inMilliseconds, closeTo(5000, 50));
      expect(h.engine.playCalls, 1);
    });
  });

  test('a track found over when the start timer fires is not played '
      'from zero', () {
    run((h) {
      h.hello(nowPlayingWith(durationMs: 3000), serverNow: trackStart - 2000);
      h.async.elapse(const Duration(seconds: 1));
      h.shiftClock(10000);
      h.async.elapse(const Duration(seconds: 1));

      expect(h.engine.playCalls, 0);
      expect(h.state.status, LocalPlaybackStatus.ended);
    });
  });

  test('an error while playing reloads the original media once and '
      'plans the position after the reload; a second error stops', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 10));
      expect(h.state.status, LocalPlaybackStatus.playing);

      h.engine.loadDuration = const Duration(milliseconds: 800);
      h.engine.fail();
      h.async.elapse(const Duration(seconds: 3));

      expect(h.engine.loadCalls, 2);
      expect(h.engine.requests.last.uri, h.engine.requests.first.uri);
      final reloadFrom = h.engine.requests.last.positionMs;
      expect(reloadFrom, greaterThan(40000));
      expect(h.engine.seeks.last.inMilliseconds, closeTo(reloadFrom + 800, 50));
      expect(h.state.status, LocalPlaybackStatus.playing);

      h.engine.fail();
      h.async.elapse(const Duration(seconds: 5));

      expect(h.engine.loadCalls, 2);
      expect(h.state.status, LocalPlaybackStatus.error);
    });
  });

  test('an interruption pauses without drift seeks, its end plays from '
      'the room position, and a system stop keeps the next track silent '
      'until the user resumes', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));

      h.engine.emit(AudioEngineEventKind.interrupted);
      h.async.flushMicrotasks();
      expect(h.state.status, LocalPlaybackStatus.paused);
      expect(h.engine.playing, isFalse);
      final seeks = h.engine.seeks.length;
      h.async.elapse(const Duration(seconds: 10));
      expect(h.engine.seeks.length, seeks, reason: 'no drift seeks');

      h.engine.calls.clear();
      h.engine.emit(AudioEngineEventKind.resumed);
      h.async.flushMicrotasks();
      expect(h.engine.calls, ['seek 41000', 'play']);
      expect(h.state.status, LocalPlaybackStatus.playing);

      h.engine.emit(AudioEngineEventKind.systemStop);
      h.async.flushMicrotasks();
      expect(h.engine.releaseCalls, 1);
      expect(h.state.status, LocalPlaybackStatus.paused);

      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow));
      h.async.elapse(const Duration(seconds: 5));
      expect(h.engine.loadCalls, 1);
      expect(h.engine.playing, isFalse);

      unawaited(h.playback.toggleLocalPause());
      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.loadCalls, 2);
      expect(h.engine.requests.last.identity.entryId, 'next');
      expect(h.state.status, LocalPlaybackStatus.playing);
    });
  });

  test('a pause while loading holds after the load, and resuming '
      'while the next track waits for its start plays only that track', () {
    run((h) {
      h.engine.loadDuration = const Duration(milliseconds: 1500);
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(milliseconds: 500));
      unawaited(h.playback.toggleLocalPause());
      h.async.elapse(const Duration(seconds: 2));
      expect(h.engine.playCalls, 0);
      expect(h.state.status, LocalPlaybackStatus.paused);

      h.engine.loadDuration = Duration.zero;
      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow + 3000));
      unawaited(h.playback.toggleLocalPause());
      h.async.elapse(const Duration(seconds: 2));
      expect(h.engine.playCalls, 0, reason: 'nothing before the start');
      expect(h.state.status, LocalPlaybackStatus.waiting);

      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.playCalls, 1);
      expect(h.engine.requests.last.identity.entryId, 'next');
      expect(h.state.status, LocalPlaybackStatus.playing);
    });
  });

  test('the media session lasts across a gap without a track and ends '
      'when leaving the room', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));

      h.play(null);
      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.releaseCalls, 0);
      expect(h.state.status, LocalPlaybackStatus.idle);

      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow));
      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.releaseCalls, 0);
      expect(h.state.status, LocalPlaybackStatus.playing);

      unawaited(h.room.leaveRoom());
      h.async.flushMicrotasks();
      expect(h.engine.releaseCalls, 1);
      expect(h.state.status, LocalPlaybackStatus.idle);
    });
  });

  test('a track over before it was loaded checks an unreachable room once '
      'instead of reconnecting in a loop', () {
    run((h) {
      h.transport.failAttempts = true;
      h.transport.emitHello(
        snapshotWith(nowPlayingWith(durationMs: 60000)),
        trackStart + 120000,
      );
      h.transport.disconnect();
      h.async.elapse(const Duration(seconds: 1));

      expect(h.transport.connectAttempts, lessThanOrEqualTo(2));
      expect(h.engine.loadCalls, 0);
      expect(h.state.status, LocalPlaybackStatus.ended);
    });
  });

  for (final leave in [true, false]) {
    final how = leave ? 'leaving the room' : 'a system stop';
    test('a load still waiting for the volume is dropped after $how, and '
        'the media session ends idle', () {
      fakeAsync((async) {
        final player = FakeMediaPlayer();
        final handler = AlistenAudioHandler(
          player,
          AudioStreamFactory(Dio()),
          interruptions: const Stream.empty(),
          becomingNoisy: const Stream.empty(),
        );
        final h = PlaybackHarness(async, audioEngine: RoomAudioEngine(handler));
        // 加载要先等音量设置完成，这是一次平台往返。
        h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
        if (leave) {
          unawaited(h.room.leaveRoom());
        } else {
          unawaited(handler.stop());
        }
        async.elapse(const Duration(seconds: 2));

        expect(player.sourceLoads, 0);
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        h.dispose();
        unawaited(handler.dispose());
        async.flushMicrotasks();
      });
    });
  }

  test('a pause the engine made by itself is a local pause that the lock '
      'screen play button resumes at the room position', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      h.engine.pauseItself();
      h.async.elapse(const Duration(seconds: 5));
      expect(h.state.status, LocalPlaybackStatus.paused);

      h.engine.calls.clear();
      h.engine.emit(AudioEngineEventKind.playRequested);
      h.async.flushMicrotasks();
      expect(h.engine.calls, ['seek 36000', 'play']);
      expect(h.state.status, LocalPlaybackStatus.playing);
    });
  });

  test('removing the app from recent tasks ends the session only when it '
      'was paused on this device', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      h.engine.emit(AudioEngineEventKind.taskRemoved);
      h.async.flushMicrotasks();
      expect(h.engine.releaseCalls, 0);

      unawaited(h.playback.toggleLocalPause());
      h.engine.emit(AudioEngineEventKind.taskRemoved);
      h.async.flushMicrotasks();
      expect(h.engine.releaseCalls, 1);
    });
  });

  test('removing the app from recent tasks keeps the room playing '
      'while it waits for the next track, and ends it when interrupted', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow + 3000));
      h.async.elapse(const Duration(milliseconds: 100));
      expect(h.state.status, LocalPlaybackStatus.waiting);
      h.engine.emit(AudioEngineEventKind.taskRemoved);
      h.async.flushMicrotasks();
      expect(h.engine.releaseCalls, 0);

      h.async.elapse(const Duration(seconds: 4));
      expect(h.state.status, LocalPlaybackStatus.playing);
      h.engine
        ..emit(AudioEngineEventKind.interrupted)
        ..emit(AudioEngineEventKind.taskRemoved);
      h.async.flushMicrotasks();
      expect(h.engine.releaseCalls, 1);

      // 播放被停止而不只是被中断，通话结束后不会恢复声音。
      h.engine.emit(AudioEngineEventKind.resumed);
      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.playing, isFalse);
      expect(h.state.status, LocalPlaybackStatus.paused);
    });
  });

  test('gain is capped, and local volume and mute stay on this device', () {
    run((h) {
      h.hello(nowPlayingWith(gain: 2), serverNow: trackStart + 30000);
      unawaited(h.playback.setVolume(50, persist: false));
      h.async.flushMicrotasks();
      expect(h.engine.volumes.last, 0.75);

      unawaited(h.playback.toggleMute());
      h.async.flushMicrotasks();
      expect(h.engine.volumes.last, 0);
      expect(h.state.volume, 50);
      expect(h.state.muted, isTrue);
      expect(h.transport.requests, isEmpty);
    });
  });

  test('toggling the local pause between two tracks does nothing, so the '
      'next track plays', () {
    run((h) {
      h.hello(nowPlayingWith(durationMs: 60000), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      h.engine.end();
      h.async.flushMicrotasks();
      expect(h.state.status, LocalPlaybackStatus.ended);

      unawaited(h.playback.toggleLocalPause());
      h.async.flushMicrotasks();
      expect(h.state.status, LocalPlaybackStatus.ended);

      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow));
      h.async.elapse(const Duration(seconds: 1));
      expect(h.engine.requests.last.identity.entryId, 'next');
      expect(h.state.status, LocalPlaybackStatus.playing);
    });
  });

  // 有意如此：两首之间拔掉耳机或在锁屏上暂停，下一首不能从外放响起。
  test('a pause from the lock screen or headset between two tracks keeps the '
      'next track paused', () {
    run((h) {
      h.hello(nowPlayingWith(durationMs: 60000), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      h.engine.end();
      h.async.flushMicrotasks();
      expect(h.state.status, LocalPlaybackStatus.ended);

      h.engine.emit(AudioEngineEventKind.pauseRequested);
      h.async.flushMicrotasks();

      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow));
      h.async.elapse(const Duration(seconds: 1));
      expect(h.state.status, LocalPlaybackStatus.paused);
      expect(h.engine.playCalls, 1, reason: 'only the first track played');
    });
  });

  test('an engine that cannot play on this device makes playback unavailable '
      'at once: no retry, no load on resume, none for the next track', () {
    run((h) {
      h.engine
        ..loadFailures = 100
        ..loadError = const AudioUnavailableException();
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 5));
      expect(h.state.status, LocalPlaybackStatus.unavailable);
      expect(h.engine.loadCalls, 1);

      unawaited(h.playback.toggleLocalPause());
      h.async.elapse(const Duration(seconds: 5));
      expect(h.state.status, LocalPlaybackStatus.unavailable);
      expect(h.engine.loadCalls, 1);

      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow));
      h.async.elapse(const Duration(seconds: 5));
      expect(h.state.status, LocalPlaybackStatus.unavailable);
      expect(h.engine.loadCalls, 1);

      h.play(null);
      expect(h.state.status, LocalPlaybackStatus.idle);
    });
  });

  test('the stand-in engine of a device whose audio service did not start '
      'leaves playback unavailable', () {
    fakeAsync((async) {
      final h = PlaybackHarness(
        async,
        audioEngine: const UnavailableAudioEngine(),
      );
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      async.elapse(const Duration(seconds: 5));
      expect(h.state.status, LocalPlaybackStatus.unavailable);
      h.dispose();
    });
  });

  test('the cover for the lock screen is the file the cover cache keeps, and '
      'none when the cache cannot fetch it', () {
    fakeAsync((async) {
      const cover = 'https://covers.example.com/next.jpg';
      final covers = FakeCoverCache(covers: {cover: Uint8List(1)});
      final h = PlaybackHarness(async, covers: covers);
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      async.elapse(const Duration(seconds: 1));
      Uri? fileOf(AudioLoadRequest request) {
        Uri? file;
        unawaited(request.coverFile().then((value) => file = value));
        async.flushMicrotasks();
        return file;
      }

      expect(testTrackMeta.coverUrl, isNot(cover));
      expect(fileOf(h.engine.requests.last), isNull);

      final next = nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow);
      h.play(
        NowPlaying(
          entry: QueueEntry(
            id: next.entry.id,
            track: next.entry.track,
            meta: TrackMeta(
              title: testTrackMeta.title,
              artist: testTrackMeta.artist,
              album: testTrackMeta.album,
              coverUrl: cover,
              pageUrl: testTrackMeta.pageUrl,
              durationMs: testTrackMeta.durationMs,
            ),
            requestedBy: next.entry.requestedBy,
            auto: false,
            likes: 0,
            status: QueueEntryStatus.ready,
          ),
          mediaUrl: next.mediaUrl,
          startedAtMs: next.startedAtMs,
          durationMs: next.durationMs,
          gain: next.gain,
          lyric: next.lyric,
        ),
      );
      async.elapse(const Duration(seconds: 1));

      expect(h.engine.requests.last.identity.entryId, 'next');
      expect(fileOf(h.engine.requests.last), FakeCoverCache.fileOf(cover));
      expect(covers.fileRequests, [testTrackMeta.coverUrl, cover]);
      h.dispose();
    });
  });

  test('a load still in flight when the container is disposed is dropped '
      'without an error', () {
    fakeAsync((async) {
      final h = PlaybackHarness(async);
      h.engine.loadDuration = const Duration(milliseconds: 500);
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      async.elapse(const Duration(milliseconds: 100));
      expect(h.engine.loadCalls, 1);

      h.dispose();
      async.elapse(const Duration(seconds: 1));

      expect(h.engine.playCalls, 0);
    });
  });

  test('the live position follows the engine between published ticks', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      h.async.elapse(const Duration(milliseconds: 100));

      expect(h.livePosition(), h.engine.position.inMilliseconds);
      expect(h.livePosition(), isNot(h.state.positionMs));
    });
  });

  test('the live position stands still with a paused engine', () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      unawaited(h.playback.toggleLocalPause());
      h.async.flushMicrotasks();
      final paused = h.livePosition();

      h.async.elapse(const Duration(seconds: 1));

      expect(h.livePosition(), paused);
    });
  });

  test('while the next track loads the live position is not the last '
      "track's", () {
    run((h) {
      h.hello(nowPlayingWith(), serverNow: trackStart + 30000);
      h.async.elapse(const Duration(seconds: 1));
      h.engine.loadDuration = const Duration(seconds: 2);

      h.play(nowPlayingWith(entryId: 'next', startedAtMs: h.serverNow));
      h.async.flushMicrotasks();

      expect(h.state.status, LocalPlaybackStatus.loading);
      expect(h.livePosition(), h.state.positionMs);
      expect(h.livePosition(), lessThan(1000));
    });
  });
}
