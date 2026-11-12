import 'package:alisten/features/playback/application/audio_engine.dart';

final class UnavailableAudioEngine implements AudioEngine {
  const UnavailableAudioEngine();

  @override
  Stream<AudioEngineEvent> get events => const Stream.empty();

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  Future<void> load(AudioLoadRequest request) async {
    throw const AudioUnavailableException();
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> release() async {}
}
