import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _roomNameRequired = '请输入房间名称';
const _createUnknown = '创建请求没有得到回复，房间可能已经创建。正在刷新房间列表，请确认后再决定是否重新创建。';
const _createUnexpected = '没能确认创建结果，房间可能已经创建。正在刷新房间列表，请确认后再决定是否重新创建。';
const _confirmCreateFirst = '房间列表刷新成功之前不能再次创建，请先刷新并确认房间是否已经创建。';
const _busyMessage = '正在进入另一个房间，请稍候';
const _serverChanged = '服务器已经切换，这次操作没有完成。';
const _createdBeforeServerChange = '服务器已经切换，房间可能已在原服务器上创建。';
const _unexpected = '没能确认操作结果，请刷新房间列表后再决定是否重试。';

/// 加入、创建房间的失败只抛给发起方，不放进状态，以免一个面板显示另一次操作的
/// 错误。
final class LobbyState {
  const LobbyState({
    this.rooms = const [],
    this.query = '',
    this.loading = false,
    this.listError,
    this.busy = false,
  });

  final List<RoomListing> rooms;
  final String query;
  final bool loading;

  /// 刷新失败时仍保留上次加载的 [rooms]。
  final String? listError;
  final bool busy;

  List<RoomListing> get filteredRooms {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return rooms;
    return rooms
        .where(
          (room) => '${room.name} ${room.description}'.toLowerCase().contains(
            keyword,
          ),
        )
        .toList(growable: false);
  }

  LobbyState copyWith({
    List<RoomListing>? rooms,
    String? query,
    bool? loading,
    Object? listError = _unchanged,
    bool? busy,
  }) {
    return LobbyState(
      rooms: rooms ?? this.rooms,
      query: query ?? this.query,
      loading: loading ?? this.loading,
      listError: identical(listError, _unchanged)
          ? this.listError
          : listError as String?,
      busy: busy ?? this.busy,
    );
  }
}

const _unchanged = Object();

/// [failure] 为 null 表示请求没有到达房间。
final class LobbyActionException implements Exception {
  const LobbyActionException({
    required this.message,
    this.failure,
    this.unknown = false,
  });

  final String message;
  final RoomFailure? failure;

  /// 请求可能已经生效，不能当作失败。
  final bool unknown;

  @override
  String toString() => 'LobbyActionException($failure)';
}

final lobbyControllerProvider = NotifierProvider<LobbyController, LobbyState>(
  LobbyController.new,
);

base class LobbyController extends Notifier<LobbyState> {
  // 换服务器时递增，用来丢弃旧服务器的请求结果。
  int _scope = 0;
  int _loadSequence = 0;
  ({Object key, Future<RoomListing> result})? _running;
  bool _createUnconfirmed = false;
  // 已创建但没能进入的房间；再次提交相同表单时直接进入，不再新建。
  ({String name, String description, String? password, String id})? _created;

  @override
  LobbyState build() => const LobbyState();

  void resetForServerChange() {
    _scope++;
    _running = null;
    _createUnconfirmed = false;
    _created = null;
    state = LobbyState(query: state.query);
    unawaited(load());
  }

  Future<void> load() async {
    final sequence = ++_loadSequence;
    state = state.copyWith(loading: true, listError: null);
    try {
      final rooms = await ref.read(alistenApiProvider).listRooms();
      if (!ref.mounted || sequence != _loadSequence) return;
      _createUnconfirmed = false;
      state = state.copyWith(rooms: rooms, loading: false);
    } on Object catch (error) {
      if (!ref.mounted || sequence != _loadSequence) return;
      state = state.copyWith(
        loading: false,
        listError: _message(error, '房间加载失败，请重试。'),
      );
    }
  }

  void filter(String query) {
    state = state.copyWith(query: query);
  }

  /// 创建房间并进入，失败时抛出 [LobbyActionException]。结果未知的创建不重发，
  /// 房间列表刷新成功之前拒绝再次创建。
  ///
  /// 同一时间只进行一次加入或创建：相同请求共用进行中的结果，不同请求直接失败。
  Future<RoomListing> createRoom({
    required String name,
    required String description,
    String? password,
  }) {
    final form = (
      name: name.trim(),
      description: description,
      password: password == null || password.isEmpty ? null : password,
    );
    if (form.name.isEmpty) return _rejected(_roomNameRequired);
    if (_createUnconfirmed) {
      return _rejected(_confirmCreateFirst, unknown: true);
    }
    final scope = _scope;
    return _run(('create', form), () async {
      var created = _created;
      var sent = false;
      if (created == null ||
          created.name != form.name ||
          created.description != form.description ||
          created.password != form.password) {
        final String id;
        sent = true;
        try {
          id = await ref
              .read(alistenApiProvider)
              .createRoom(
                name: form.name,
                description: form.description,
                password: form.password,
              );
        } on Object catch (error, stackTrace) {
          if (error is ApiException && !error.answerLost) {
            _ensureScope(scope);
            Error.throwWithStackTrace(
              LobbyActionException(message: error.message),
              stackTrace,
            );
          }
          _ensureScope(scope, createSent: true);
          // 回复解析失败等意外错误也可能发生在房间建好之后。错误文本可能含
          // 房间名或密码，日志只记类型。
          if (error is! ApiException) {
            AppLog.error(
              'lobby',
              'room creation ended unexpectedly',
              type: '${error.runtimeType}',
            );
          }
          _createUnconfirmed = true;
          unawaited(load());
          Error.throwWithStackTrace(
            LobbyActionException(
              message: error is ApiException
                  ? _createUnknown
                  : _createUnexpected,
              unknown: true,
            ),
            stackTrace,
          );
        }
        _ensureScope(scope, createSent: true);
        created = _created = (
          name: form.name,
          description: form.description,
          password: form.password,
          id: id,
        );
      }
      return _enter(created.id, form.password, scope, createSent: sent);
    });
  }

  /// 进入房间但不跳转页面，失败与并发语义同 [createRoom]。[room] 是房间 ID 或
  /// 邀请链接中的房间标识，不接受用户输入。
  Future<RoomListing> join(String room, {String? password}) {
    final secret = password == null || password.isEmpty ? null : password;
    final scope = _scope;
    return _run(('join', room, secret), () => _enter(room, secret, scope));
  }

  Future<bool> needsPassword(RoomListing? room) async {
    if (room == null) return true;
    if (!room.hasPassword) return false;
    try {
      final ticket = await ref
          .read(credentialStoreProvider)
          .readTicket(room.id);
      return ticket == null || ticket.isEmpty;
    } on Object {
      // 读不到票据时进房同样读不到，只能要密码。
      return true;
    }
  }

  Future<RoomListing> _rejected(String message, {bool unknown = false}) {
    return Future.error(
      LobbyActionException(message: message, unknown: unknown),
    );
  }

  Future<RoomListing> _run(
    Object key,
    Future<RoomListing> Function() action,
  ) async {
    final running = _running;
    if (running != null) {
      if (running.key == key) return running.result;
      throw const LobbyActionException(message: _busyMessage);
    }
    final scope = _scope;
    state = state.copyWith(busy: true);
    // 在共享的 future 上转换错误，同一请求的所有调用方都能得到可展示的原因。
    final result = action().catchError((Object error, StackTrace stackTrace) {
      AppLog.error(
        'lobby',
        'room action ended unexpectedly',
        type: '${error.runtimeType}',
      );
      Error.throwWithStackTrace(
        const LobbyActionException(message: _unexpected, unknown: true),
        stackTrace,
      );
    }, test: (error) => error is! LobbyActionException);
    final entry = (key: key, result: result);
    _running = entry;
    try {
      return await result;
    } finally {
      // 换服务器后 [_running] 可能已是新服务器的请求，不能清掉它和忙碌状态。
      if (identical(_running, entry)) _running = null;
      if (ref.mounted && scope == _scope) state = state.copyWith(busy: false);
    }
  }

  // 对已报告不存在或版本过旧的房间，[RoomController.openRoom] 直接返回原来的
  // 失败；这里是用户的明确请求，所以先离开再重新进入。
  Future<RoomListing> _enter(
    String target,
    String? password,
    int scope, {
    bool createSent = false,
  }) async {
    final room = ref.read(roomControllerProvider.notifier);
    final failure = ref.read(roomControllerProvider).failure;
    if (failure == RoomFailure.notFound || failure == RoomFailure.outdated) {
      await room.leaveRoom();
      _ensureScope(scope, createSent: createSent);
    }
    final result = await room.openRoom(target, password: password);
    _ensureScope(scope, createSent: createSent);
    switch (result) {
      case RoomJoined(room: final joined):
        _created = null;
        return joined;
      case RoomJoinFailed(:final failure, :final message):
        if (failure == RoomFailure.notFound) _created = null;
        throw LobbyActionException(message: message, failure: failure);
    }
  }

  void _ensureScope(int scope, {bool createSent = false}) {
    if (scope == _scope) return;
    throw createSent
        ? const LobbyActionException(
            message: _createdBeforeServerChange,
            unknown: true,
          )
        : const LobbyActionException(message: _serverChanged);
  }

  String _message(Object error, String fallback) {
    return error is ApiException ? error.message : fallback;
  }
}
