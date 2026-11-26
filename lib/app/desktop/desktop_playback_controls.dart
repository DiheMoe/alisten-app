import 'dart:async';

import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/room/room_actions.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _SkipVote = ({
  (PlaybackIdentity, VoteSkipResult)? cast,
  PlaybackIdentity? sending,
});

// 每次播放只能投一票，换了歌才能再投。房间页和迷你播放条共用这一份：在一处投
// 的票，另一处也显示已投。
final _skipVoteProvider = NotifierProvider<_SkipVoteController, _SkipVote>(
  _SkipVoteController.new,
);

final class _SkipVoteController extends Notifier<_SkipVote> {
  @override
  _SkipVote build() {
    ref.watch(roomControllerProvider.select((room) => room.activeRoomId));
    return (cast: null, sending: null);
  }

  Future<MutationResult<VoteSkipResult>> vote(PlaybackIdentity playback) async {
    state = (cast: state.cast, sending: playback);
    final result = await ref.read(queueActionsProvider).voteSkip();
    if (!ref.mounted) return result;
    state = (
      cast: switch (result) {
        MutationSucceeded(:final value) when !value.skipped => (
          playback,
          value,
        ),
        _ => state.cast,
      },
      sending: state.sending == playback ? null : state.sending,
    );
    return result;
  }
}

/// 桌面窗口里的暂停和投票切歌，[gap] 是两个按钮之间的间距。
class DesktopPlaybackControls extends ConsumerWidget {
  const DesktopPlaybackControls({required this.gap, super.key});

  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (nowPlaying, connected) = ref.watch(
      roomControllerProvider.select(
        (room) => (
          room.snapshot?.nowPlaying,
          room.status == RoomConnectionStatus.open,
        ),
      ),
    );
    final votes = ref.watch(_skipVoteProvider);
    final playback = nowPlaying == null
        ? null
        : PlaybackIdentity(
            entryId: nowPlaying.entry.id,
            startedAtMs: nowPlaying.startedAtMs,
          );
    final toasts = ref.read(toastControllerProvider);
    final controller = ref.read(_skipVoteProvider.notifier);
    return PlayerControls(
      compact: true,
      compactGap: gap,
      vote: switch (votes.cast) {
        (final votedOn, final result) when votedOn == playback => result,
        _ => null,
      },
      voting: playback != null && votes.sending == playback,
      onVoteSkip: playback != null && connected
          ? () => unawaited(
              controller.vote(playback).then((result) {
                reportVote(toasts, result);
              }),
            )
          : null,
    );
  }
}
