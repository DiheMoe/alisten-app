import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 没点过或请求没有发出的歌没有状态。
enum PickStatus {
  sending,
  added,
  failed,

  /// 请求已发出但没有收到回复，房间可能已经加上，也可能没有。
  unknown,
}

/// [added] 是房间已确认添加的首数。
@immutable
final class Picks {
  const Picks({this.statuses = const {}, this.added = 0});

  final Map<String, PickStatus> statuses;
  final int added;

  PickStatus? of(Track track) => statuses[_keyOf(track)];

  Picks _with(String key, PickStatus? status, {int added = 0}) {
    final statuses = {...this.statuses};
    if (status == null) {
      statuses.remove(key);
    } else {
      statuses[key] = status;
    }
    return Picks(statuses: statuses, added: this.added + added);
  }

  @override
  bool operator ==(Object other) {
    return other is Picks &&
        other.added == added &&
        mapEquals(other.statuses, statuses);
  }

  @override
  int get hashCode => Object.hash(
    added,
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in statuses.entries)
        Object.hash(key, value),
    ]),
  );
}

String _keyOf(Track track) => '${track.source.name}:${track.id}';

// 搜索结果和歌单页共用点歌状态，一处点的歌在另一处也显示为已点。进行中的请求
// 记在这里而不是行组件里：列表滚动时行会重建和复用，请求却仍在进行。状态只在
// 点歌页显示期间保留，换房间时重新开始。
final pickControllerProvider =
    NotifierProvider.autoDispose<PickController, Picks>(PickController.new);

final class PickController extends Notifier<Picks> {
  @override
  Picks build() {
    ref.watch(roomControllerProvider.select((room) => room.activeRoomId));
    return const Picks();
  }

  /// 这首歌的请求仍在进行时不再发送，返回 null。
  Future<MutationResult<QueueEntry>?> pick(Track track) async {
    final key = _keyOf(track);
    if (state.statuses[key] == PickStatus.sending) return null;
    final actions = ref.read(queueActionsProvider);
    state = state._with(key, PickStatus.sending);
    final result = await actions.addTrack(track);
    if (ref.mounted && state.statuses[key] == PickStatus.sending) {
      state = switch (result) {
        MutationSucceeded() => state._with(key, PickStatus.added, added: 1),
        MutationFailed() => state._with(key, PickStatus.failed),
        MutationUnknown() => state._with(key, PickStatus.unknown),
        MutationNotSent() => state._with(key, null),
      };
    }
    return result;
  }
}
