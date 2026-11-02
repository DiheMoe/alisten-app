import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/queue/application/queue_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
final class QueueBusy {
  const QueueBusy({this.entries = const {}, this.changingMode = false});

  /// 点赞或移除已发出、尚未得到答复的条目。
  final Set<String> entries;
  final bool changingMode;

  QueueBusy copyWith({Set<String>? entries, bool? changingMode}) {
    return QueueBusy(
      entries: entries ?? this.entries,
      changingMode: changingMode ?? this.changingMode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is QueueBusy &&
        other.changingMode == changingMode &&
        setEquals(other.entries, entries);
  }

  @override
  int get hashCode =>
      Object.hash(changingMode, Object.hashAllUnordered(entries));
}

/// 每次点赞都会多计一票，所以同一变更在房间答复前只发送一次。状态放在这里
/// 而非视图中，因为切换房间模式时视图会重建，请求却仍在进行。
final queueControllerProvider = NotifierProvider<QueueController, QueueBusy>(
  QueueController.new,
);

final class QueueController extends Notifier<QueueBusy> {
  static const _unanswered = '上一次操作还没有结果';

  @override
  QueueBusy build() => const QueueBusy();

  Future<MutationResult<int>> like(String entryId) {
    return _sendFor(entryId, (actions) => actions.like(entryId));
  }

  Future<MutationResult<void>> remove(String entryId) {
    return _sendFor(entryId, (actions) => actions.remove(entryId));
  }

  Future<MutationResult<void>> setPlayMode(RoomPlayMode mode) async {
    if (state.changingMode) return const MutationNotSent(_unanswered);
    final actions = ref.read(queueActionsProvider);
    state = state.copyWith(changingMode: true);
    try {
      return await actions.setPlayMode(mode);
    } finally {
      if (ref.mounted) state = state.copyWith(changingMode: false);
    }
  }

  Future<MutationResult<T>> _sendFor<T>(
    String entryId,
    Future<MutationResult<T>> Function(QueueActions actions) send,
  ) async {
    if (state.entries.contains(entryId)) {
      return MutationNotSent<T>(_unanswered);
    }
    final actions = ref.read(queueActionsProvider);
    state = state.copyWith(entries: {...state.entries, entryId});
    try {
      return await send(actions);
    } finally {
      if (ref.mounted) {
        state = state.copyWith(entries: {...state.entries}..remove(entryId));
      }
    }
  }
}
