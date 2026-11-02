import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef RoomMutate = Future<MutationResult<T>> Function<T>(
  Future<T> Function(RoomCommands c) run,
);

final queueActionsProvider = Provider<QueueActions>((ref) {
  return QueueActions(ref.read(roomControllerProvider.notifier).mutate);
});

final class QueueActions {
  const QueueActions(this._mutate);

  final RoomMutate _mutate;

  Future<MutationResult<QueueEntry>> addTrack(Track track) {
    return _mutate((c) => c.addTrack(track));
  }

  Future<MutationResult<int>> like(String entryId) {
    return _mutate((c) => c.likeEntry(entryId));
  }

  Future<MutationResult<void>> remove(String entryId) {
    return _mutate((c) => c.removeEntry(entryId));
  }

  Future<MutationResult<VoteSkipResult>> voteSkip() {
    return _mutate((c) => c.voteSkip());
  }

  Future<MutationResult<void>> setPlayMode(RoomPlayMode mode) {
    return _mutate((c) => c.setPlayMode(mode));
  }
}
