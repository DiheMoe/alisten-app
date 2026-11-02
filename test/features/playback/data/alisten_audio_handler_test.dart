import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/features/playback/application/audio_engine.dart';
import 'package:alisten/features/playback/data/alisten_audio_handler.dart';
import 'package:alisten/features/playback/data/audio_stream_factory.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../playback_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMediaPlayer player;
  late AlistenAudioHandler handler;
  late RoomAudioEngine engine;
  late List<AudioEngineEventKind> events;
  late List<AudioProcessingState> published;

  setUp(() {
    player = FakeMediaPlayer();
    handler = AlistenAudioHandler(
      player,
      AudioStreamFactory(Dio()),
      interruptions: const Stream.empty(),
      becomingNoisy: const Stream.empty(),
    );
    engine = RoomAudioEngine(handler);
    events = [];
    published = [];
    engine.events.listen((event) => events.add(event.kind));
    handler.playbackState.listen(
      (state) => published.add(state.processingState),
    );
  });

  tearDown(() => handler.dispose());

  AudioLoadRequest request(
    int load, {
    PlaybackIdentity? identity,
    Future<Uri?> Function()? coverFile,
  }) {
    return AudioLoadRequest(
      load: load,
      identity:
          identity ??
          PlaybackIdentity(entryId: 'entry-$load', startedAtMs: load),
      uri: Uri.parse('https://media.test/$load'),
      meta: testTrackMeta,
      durationMs: 180000,
      positionMs: 0,
      coverFile: coverFile ?? () async => null,
    );
  }

  test('playing is published as soon as playback starts, and a media '
      'button click while playing pauses', () async {
    await engine.load(request(1));
    var returned = false;
    unawaited(engine.play().then((_) => returned = true));
    await pumpEventQueue();

    expect(returned, isTrue, reason: "just_audio's play() is still pending");
    expect(handler.playbackState.value.playing, isTrue);

    await handler.click();
    await pumpEventQueue();

    expect(events, contains(AudioEngineEventKind.pauseRequested));
    expect(events, isNot(contains(AudioEngineEventKind.playRequested)));
  });

  test('the next track publishes loading and never idle, keeps playing, '
      'and only a stop ends the session', () async {
    await engine.load(request(1));
    unawaited(engine.play());
    await pumpEventQueue();
    player.complete();
    await pumpEventQueue();
    published.clear();

    await engine.load(request(2));
    await pumpEventQueue();

    expect(published, contains(AudioProcessingState.loading));
    expect(published, isNot(contains(AudioProcessingState.idle)));
    expect(handler.playbackState.value.playing, isTrue);

    await handler.stop();
    await pumpEventQueue();

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    expect(events, contains(AudioEngineEventKind.systemStop));
  });

  test('the media controls are never given the web address of a cover, '
      'which audio_service would download into a cache of its own', () async {
    await engine.load(request(1));
    await pumpEventQueue();

    expect(handler.mediaItem.value?.title, testTrackMeta.title);
    expect(
      handler.mediaItem.value?.artUri?.scheme,
      isNot(anyOf('http', 'https')),
    );
  });

  test('the cover is shown from its file on this device once the source has '
      'loaded and the file is there', () async {
    final file = Uri.file('/cache/covers/1');
    final cover = Completer<Uri?>();
    var asked = 0;
    await engine.load(
      request(
        1,
        coverFile: () {
          asked++;
          return cover.future;
        },
      ),
    );
    await pumpEventQueue();
    expect(asked, 1);
    expect(handler.mediaItem.value?.artUri, isNull);

    cover.complete(file);
    await pumpEventQueue();
    expect(handler.mediaItem.value?.artUri, file);
    expect(handler.mediaItem.value?.title, testTrackMeta.title);
  });

  test('a cover file that arrives after the next track was loaded is not '
      'shown with it, and a track without a file shows no cover', () async {
    final late = Completer<Uri?>();
    await engine.load(request(1, coverFile: () => late.future));
    await engine.load(request(2));
    late.complete(Uri.file('/cache/covers/1'));
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, 'entry-2@2');
    expect(handler.mediaItem.value?.artUri, isNull);
  });

  test('loading the same playback again keeps its cover meanwhile', () async {
    const identity = PlaybackIdentity(entryId: 'entry', startedAtMs: 1);
    final file = Uri.file('/cache/covers/1');
    await engine.load(
      request(1, identity: identity, coverFile: () async => file),
    );
    await pumpEventQueue();
    final shown = <Uri?>[];
    final watching = handler.mediaItem.listen(
      (item) => shown.add(item?.artUri),
    );

    await engine.load(
      request(2, identity: identity, coverFile: () async => file),
    );
    await pumpEventQueue();
    await watching.cancel();

    expect(shown, everyElement(file));
  });

  test('removing the app from recent tasks is left to the playback owner, '
      'which knows whether the room plays on', () async {
    await engine.load(request(1));
    await handler.onTaskRemoved();
    await pumpEventQueue();

    expect(events, contains(AudioEngineEventKind.taskRemoved));
    expect(
      handler.playbackState.value.processingState,
      isNot(AudioProcessingState.idle),
    );
  });

  test('a handler created with a Dio streams through it and closes it '
      'with itself', () async {
    final adapter = _ClosingAdapter();

    final created = await AlistenAudioHandler.create(
      Dio()..httpClientAdapter = adapter,
    );
    expect(adapter.closed, isFalse);
    await created.dispose();

    expect(adapter.closed, isTrue);
  });
}

final class _ClosingAdapter implements HttpClientAdapter {
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw UnimplementedError();

  @override
  void close({bool force = false}) => closed = true;
}
