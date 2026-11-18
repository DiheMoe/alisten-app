import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/application/admin_api.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/room_form.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const slugTakenText = '这个别名已被占用';

const _conflict = 'CONFLICT';
const _invalidArgument = 'INVALID_ARGUMENT';
const _notFound = 'NOT_FOUND';
// 服务端的说明带字段路径，面向接口调用方，不适合展示。
const _invalidText = '提交的内容不符合要求，请检查后再试。';
const _noChangesText = '没有需要保存的修改。';
const _notLoadedText = '没能读取常驻房间，请稍后重试。';

final class AdminRoomsState {
  const AdminRoomsState({
    this.rooms = const [],
    this.loaded = false,
    this.defaultCapacity,
    this.loading = false,
    this.error,
  });

  final List<RoomListing> rooms;

  /// 读到过一次列表（包括空列表）。
  final bool loaded;

  /// 新建房间的表单从它开始，读到房间列表之前为 null。默认值由服务端给出，
  /// 不在 App 里另存一份。
  final int? defaultCapacity;
  final bool loading;
  final String? error;

  AdminRoomsState _with({bool loading = false, String? error}) {
    return AdminRoomsState(
      rooms: rooms,
      loaded: loaded,
      defaultCapacity: defaultCapacity,
      loading: loading,
      error: error,
    );
  }
}

final adminRoomsControllerProvider =
    NotifierProvider.autoDispose<AdminRoomsController, AdminRoomsState>(
      AdminRoomsController.new,
    );

final class AdminRoomsController extends Notifier<AdminRoomsState> {
  int _loads = 0;

  @override
  AdminRoomsState build() => const AdminRoomsState();

  Future<void> load() async {
    final attempt = ++_loads;
    bool latest() => ref.mounted && attempt == _loads;
    state = state._with(loading: true);
    try {
      final list = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.listRooms(token));
      if (latest()) {
        state = AdminRoomsState(
          rooms: list.rooms,
          loaded: true,
          defaultCapacity: list.defaultCapacity,
        );
      }
    } on AdminSessionEnded {
      if (latest()) state = state._with();
    } on ApiException catch (error) {
      if (latest()) state = state._with(error: error.message);
    } on Object catch (error) {
      AppLog.warn('admin', 'rooms not loaded', type: '${error.runtimeType}');
      if (latest()) state = state._with(error: _notLoadedText);
    }
  }

  Future<MutationResult<String>> create(RoomForm form) async {
    if (roomFormProblem(form) case final problem?) {
      return MutationNotSent(problem);
    }
    final draft = roomDraft(form);
    return _change((api, token) => api.createRoom(token, draft));
  }

  Future<MutationResult<void>> update(
    RoomListing original,
    RoomForm form,
  ) async {
    if (roomFormProblem(form) case final problem?) {
      return MutationNotSent(problem);
    }
    final patch = roomPatch(original, form);
    if (patch.isEmpty) return const MutationNotSent(_noChangesText);
    return _change((api, token) => api.updateRoom(token, original.id, patch));
  }

  /// 房间已不存在也算删除成功：多半是上次结果未知的删除已经生效。
  Future<MutationResult<void>> delete(String roomId) async {
    final result = await _change((api, token) => api.deleteRoom(token, roomId));
    if (result case MutationFailed(code: _notFound)) {
      return const MutationSucceeded<void>(null);
    }
    return result;
  }

  Future<MutationResult<T>> _change<T>(
    Future<T> Function(AdminApi api, String token) operation,
  ) {
    return ref
        .read(adminSessionProvider.notifier)
        .change(
          operation,
          unexpected: 'room change ended unexpectedly',
          refusals: const {
            _conflict: slugTakenText,
            _invalidArgument: _invalidText,
          },
          reread: (_) async {
            if (ref.mounted) unawaited(load());
          },
        );
  }
}
