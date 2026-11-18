import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/room_form.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _invalidArgument = 'INVALID_ARGUMENT';
const _notLoadedText = '没能读取临时房间的最多人数，请稍后重试。';
const _sessionEndedText = '后台已退出，最多人数没有保存。';

final class EphemeralRoomCapacityState {
  const EphemeralRoomCapacityState({
    this.capacity,
    this.loading = false,
    this.error,
  });

  final int? capacity;
  final bool loading;
  final String? error;
}

final ephemeralRoomCapacityControllerProvider =
    NotifierProvider.autoDispose<
      EphemeralRoomCapacityController,
      EphemeralRoomCapacityState
    >(EphemeralRoomCapacityController.new);

/// 新建临时房间时的人数上限，只影响之后新建的临时房间。
final class EphemeralRoomCapacityController
    extends Notifier<EphemeralRoomCapacityState> {
  @override
  EphemeralRoomCapacityState build() => const EphemeralRoomCapacityState();

  Future<void> load() async {
    final known = state.capacity;
    state = EphemeralRoomCapacityState(capacity: known, loading: true);
    try {
      final capacity = await ref
          .read(adminSessionProvider.notifier)
          .run((api, _) => api.getEphemeralRoomCapacity());
      if (ref.mounted) {
        state = EphemeralRoomCapacityState(capacity: capacity);
      }
    } on AdminSessionEnded {
      if (ref.mounted) state = EphemeralRoomCapacityState(capacity: known);
    } on ApiException catch (error) {
      if (ref.mounted) {
        state = EphemeralRoomCapacityState(
          capacity: known,
          error: error.message,
        );
      }
    } on Object catch (error) {
      AppLog.warn(
        'admin',
        'ephemeral room capacity not loaded',
        type: '${error.runtimeType}',
      );
      if (ref.mounted) {
        state = EphemeralRoomCapacityState(
          capacity: known,
          error: _notLoadedText,
        );
      }
    }
  }

  Future<MutationResult<int>> save(String input) async {
    final capacity = roomCapacity(input);
    if (capacity == null) return const MutationNotSent(roomCapacityRuleText);
    final result = await ref
        .read(adminSessionProvider.notifier)
        .change(
          (api, token) async {
            await api.setEphemeralRoomCapacity(token, capacity);
            return capacity;
          },
          unexpected: 'ephemeral room capacity save ended unexpectedly',
          refusals: const {_invalidArgument: roomCapacityRuleText},
          sessionEnded: _sessionEndedText,
          reread: (result) async {
            if (result is MutationUnknown<int> && ref.mounted) {
              unawaited(load());
            }
          },
        );
    if (result case MutationSucceeded(value: final saved) when ref.mounted) {
      state = EphemeralRoomCapacityState(capacity: saved);
    }
    return result;
  }
}
