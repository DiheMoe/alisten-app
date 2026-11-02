import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final nowPlayingProvider = Provider<NowPlaying?>(
  (ref) => ref.watch(
    roomControllerProvider.select((state) => state.snapshot?.nowPlaying),
  ),
);
