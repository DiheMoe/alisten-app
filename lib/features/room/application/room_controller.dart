import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/room/room_replica.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/application/last_room_store.dart';
import 'package:alisten/features/room/application/room_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final roomControllerProvider = NotifierProvider<RoomController, RoomState>(
  RoomController.new,
);

final roomNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

typedef RoomTransportFactory = RoomTransport Function(
  String roomId,
  String ticket,
);

final roomTransportFactoryProvider = Provider<RoomTransportFactory>((ref) {
  throw UnimplementedError('roomTransportFactory 未注入');
});

/// 本地曲目放完后等待下一条 `NowPlaying` 的时长，超时才同步房间。过早同步会
/// 丢掉这条实时事件，变化改由快照带来，不再算作实时更新。
const trackEndSyncGrace = Duration(milliseconds: 2500);

const _maxNotices = 200;
const _probeDeadline = Duration(seconds: 5);
const _unauthorized = 'UNAUTHORIZED';
const _notConnected = '还没有连上房间，操作未发送。';
const _enterFailed = '无法进入房间，请检查网络后重试。';
const _leftRoom = '已离开房间，操作没有在当前房间生效。';
const _outdatedMessage = '客户端协议版本过旧，请升级 Alisten。';
const _logSource = 'room';
const _replaced = RoomJoinFailed(
  RoomFailure.unavailable,
  '进入房间的请求已被新的操作取代，请重试。',
);
const _changingServer = RoomJoinFailed(RoomFailure.unavailable, '正在切换服务器，请稍候。');
const _changingSession = RoomJoinFailed(RoomFailure.unavailable, '正在切换身份，请稍候。');

/// 当前房间的唯一所有者，独占连接、副本和生命周期；页面和路由只决定显示哪个
/// 房间。
final class RoomController extends Notifier<RoomState> {
  RoomTransport? _transport;
  StreamSubscription<RoomTransportEvent>? _subscription;
  RoomReplica? _replica;
  String? _ref;
  RoomListing? _listing;
  // 当前房间所属的服务器。删除票据、读写上次房间都用它，不能用切换后的服务器。
  _RoomServer? _server;
  // 递增即作废仍在解析房间和票据的 openRoom。
  int _attempt = 0;
  int? _resolving;
  int _serverChanges = 0;
  int _sessionChanges = 0;
  // 换身份期间暂存的停止事件：服务端在登录成功时就让旧 token 失效，它引起的
  // 4401 可能比登录的回复先到。换成功后会以新身份重新进入，没换成就照常处理。
  ({int code, int generation})? _heldStop;
  bool _reenterAfterChange = false;
  // 重新进入时当前房间已没有连接，只靠一次可被取代的进房尝试接上，直到它进入
  // 或失败；期间再进入同一个房间要接手这次尝试，不能当作已在房间里。
  bool _reentering = false;
  // 连接代号：递增即丢弃旧连接的事件和结果。
  int _generation = 0;
  bool _syncing = false;
  bool _restoring = false;
  Timer? _trackEndSync;
  PlaybackIdentity? _ended;
  // 因连不上服务端而未能恢复上次房间的尝试编号，此后进出过房间即失效。
  int? _unrestored;

  int? get serverNow => _transport?.clock.serverNow();

  @override
  RoomState build() {
    listenSelf((_, next) {
      if (_trackEndSync != null && _playback(next) != _ended) {
        _cancelTrackEndSync();
      }
    });
    ref.listen<AsyncValue<List<ConnectivityResult>>>(
      connectivityStatusProvider,
      (previous, next) {
        final online =
            next.value?.any((result) => result != ConnectivityResult.none) ??
            false;
        if (!online) return;
        state = state.copyWith(mayReconnectNow: true);
        if (_unrestored == _attempt && _transport == null) {
          unawaited(_restore());
          return;
        }
        unawaited(checkConnection());
      },
    );
    ref.listen<int>(
      identityControllerProvider.select((identity) => identity.session),
      (_, _) {
        if (_sessionChanges > 0) {
          _reenterAfterChange = true;
          return;
        }
        unawaited(_reenter());
      },
    );
    ref.onDispose(() {
      _attempt++;
      _generation++;
      unawaited(_release());
    });
    return const RoomState();
  }

  /// [ref] 是房间 id 或别名。它已是当前房间时不做任何事，除非当前房间因授权或
  /// 暂不可用而失败，或正以新身份重新进入。[password] 只在申请票据时使用。
  ///
  /// 拿到新房间的票据后才释放当前房间；此前失败时当前房间保持不变，失败只体现
  /// 在返回结果中。没有运行中的房间时，失败成为房间状态。
  Future<RoomJoin> openRoom(String ref, {String? password}) =>
      beginOpen(ref, password: password).result;

  ({int attempt, Future<RoomJoin> result}) beginOpen(
    String ref, {
    String? password,
  }) {
    if (_serverChanges > 0) {
      return (attempt: _attempt, result: Future.value(_changingServer));
    }
    if (_sessionChanges > 0) {
      return (attempt: _attempt, result: Future.value(_changingSession));
    }
    final attempt = ++_attempt;
    return (attempt: attempt, result: _open(ref.trim(), password, attempt));
  }

  /// 先离开房间再执行切换服务器的 [change]。期间拒绝进房和恢复上次房间，否则
  /// 票据会向旧服务器申请，播放地址却按新服务器拼接。
  Future<T> leaveForServerChange<T>(Future<T> Function() change) async {
    _serverChanges++;
    try {
      await leaveRoom();
      return await change();
    } finally {
      _serverChanges--;
    }
  }

  /// 登录、退出等会更换 memberToken 的 [change] 经它执行：期间拒绝进房，当前
  /// 连接的停止事件先暂存。结束时，会话代号变了且能重新进入，就以新身份重新
  /// 进入当前房间，暂存的事件作废；代号没变或不能重新进入，就补处理仍属于当前
  /// 连接的暂存事件。
  Future<T> changeSession<T>(Future<T> Function() change) async {
    _sessionChanges++;
    try {
      return await change();
    } finally {
      _sessionChanges--;
      if (_sessionChanges == 0) {
        final held = _heldStop;
        final reenter = _reenterAfterChange;
        _heldStop = null;
        _reenterAfterChange = false;
        if (reenter && _canReenter) {
          unawaited(_reenter());
        } else if (held != null && held.generation == _generation) {
          _onStopped(held.code);
        }
      }
    }
  }

  Future<RoomJoin> _open(String target, String? password, int attempt) async {
    if (_names(target) && !_retryable) return _settled();
    // 整个进房过程固定使用发起时的服务器，票据不得发给其他服务器。
    final api = ref.read(alistenApiProvider);
    final credentials = ref.read(credentialStoreProvider);
    final connect = ref.read(roomTransportFactoryProvider);
    final server = (
      credentials: credentials,
      lastRoom: ref.read(lastRoomStoreProvider),
    );
    _resolving = attempt;
    final RoomListing listing;
    final String ticket;
    try {
      try {
        listing = await api.getRoom(target);
      } on Object catch (error) {
        if (attempt != _attempt) return _replaced;
        return _refuse(target, null, error, server);
      }
      if (attempt != _attempt) return _replaced;
      if (_isActive(listing.id) && !_retryable) {
        _listing = listing;
        return _settled();
      }
      try {
        ticket = await _ticket(
          listing,
          password,
          attempt,
          api: api,
          credentials: credentials,
        );
      } on Object catch (error) {
        if (attempt != _attempt) return _replaced;
        return _refuse(target, listing, error, server);
      }
      if (attempt != _attempt) return _replaced;
    } finally {
      if (_resolving == attempt) _resolving = null;
    }
    final released = _enter(target, listing, server);
    final generation = _generation;
    await released;
    if (generation != _generation) return _replaced;
    final transport = connect(listing.id, ticket);
    _transport = transport;
    _subscription = transport.events.listen(
      (event) => _onEvent(event, generation),
    );
    await transport.start();
    if (generation != _generation) return _replaced;
    return RoomJoined(listing);
  }

  // 正在换票据的进房尝试自己报告结果，否则它触发的身份替换会让这里一再重进。
  bool get _canReenter =>
      _ref != null &&
      ref.mounted &&
      _serverChanges == 0 &&
      _resolving == null &&
      (state.failure == null || _retryable);

  // 旧会话的票据和连接都已作废，以新身份重新进入同一个房间。
  Future<void> _reenter() async {
    final target = _ref;
    if (target == null || !_canReenter) return;
    final attempt = ++_attempt;
    _generation++;
    _reentering = true;
    final released = _release();
    state = RoomState(
      status: RoomConnectionStatus.connecting,
      activeRoomId: state.activeRoomId,
      roomName: state.snapshot?.room.name ?? state.roomName,
      roomSlug: state.roomSlug,
      notices: state.notices,
    );
    await released;
    if (attempt != _attempt) return;
    await _open(target, null, attempt);
  }

  /// 放弃 [beginOpen] 返回的尝试，例如发起页面已关闭。仅在仍解析房间和票据时
  /// 生效，该尝试以“被取代”结束，当前房间不受影响；离开房间用 [leaveRoom]。
  void cancelOpen(int attempt) {
    if (_resolving != attempt || attempt != _attempt) return;
    _resolving = null;
    _attempt++;
    if (_reentering) unawaited(_reenter());
  }

  /// [ref]（id 或别名）是否指向当前房间。
  bool names(String ref) => _names(ref.trim());

  /// 同时清除上次的房间，下次启动不再自动进入。
  Future<void> leaveRoom() async {
    final server = _server;
    _attempt++;
    _generation++;
    _reentering = false;
    _ref = null;
    _listing = null;
    _server = null;
    final released = _release();
    state = const RoomState();
    await released;
    try {
      final LastRoomStore lastRoom =
          server?.lastRoom ?? ref.read(lastRoomStoreProvider);
      await lastRoom.clear();
    } on Object {
      AppLog.warn(_logSource, 'last room not forgotten');
    }
  }

  /// 已打开的连接立即探测；等待重连的连接立即重连，但每次断线只允许一次，网络
  /// 恢复或回到前台后才再次允许，其余按退避等待。不同步房间，也不重启连接。
  Future<void> checkConnection() async {
    final transport = _transport;
    if (transport == null || state.failure != null) return;
    switch (state.status) {
      case RoomConnectionStatus.open:
        transport.probe(_probeDeadline);
      case RoomConnectionStatus.connecting || RoomConnectionStatus.reconnecting:
        if (state.nextRetryAt == null || !state.mayReconnectNow) return;
        state = state.copyWith(mayReconnectNow: false);
        transport.check();
      case RoomConnectionStatus.stopped:
        return;
    }
  }

  /// 本地曲目放完时调用。连接已打开时立即探测，[trackEndSyncGrace] 内没有出现
  /// 新的播放就同步一次，因为对应事件可能已随之前失败的同步丢失；连接未打开时
  /// 同 [checkConnection]。
  Future<void> checkAfterTrackEnd() async {
    final transport = _transport;
    if (transport == null || state.failure != null) return;
    if (state.status != RoomConnectionStatus.open) return checkConnection();
    transport.probe(_probeDeadline);
    if (_trackEndSync != null) return;
    _ended = _playback(state);
    _trackEndSync = Timer(trackEndSyncGrace, () {
      _cancelTrackEndSync();
      unawaited(_sync());
    });
  }

  Future<void> handleLifecycle(AppLifecycleState lifecycle) async {
    if (lifecycle != AppLifecycleState.resumed) return;
    final transport = _transport;
    if (transport == null || state.failure != null) return;
    // 设备休眠时单调时钟停止计时，时钟估计须重新开始。
    transport.clock.reset();
    state = state.copyWith(mayReconnectNow: true);
    await checkConnection();
  }

  /// 发送变更请求，从不重发，也不抛异常。结果未知（含意外错误）或服务端返回
  /// `UNAVAILABLE` 时同步一次房间，由快照确认是否生效。离开或换房间后才到达的
  /// 结果按未发送报告，因为当前显示的房间没有收到该请求。
  Future<MutationResult<T>> mutate<T>(
    Future<T> Function(RoomCommands c) run,
  ) async {
    final transport = _transport;
    if (transport == null) return MutationNotSent(_notConnected);
    final generation = _generation;
    try {
      final value = await run(RoomCommands(transport));
      if (generation != _generation) return MutationNotSent(_leftRoom);
      return MutationSucceeded(value);
    } on RoomRequestException catch (error) {
      if (generation != _generation) return MutationNotSent(_leftRoom);
      final unsettled =
          error.outcome == RoomRequestOutcome.unknown ||
          (error.outcome == RoomRequestOutcome.failed &&
              error.code == 'UNAVAILABLE');
      if (unsettled) unawaited(_sync());
      return switch (error.outcome) {
        RoomRequestOutcome.notSent => MutationNotSent(error.message),
        RoomRequestOutcome.failed => MutationFailed(error.code, error.message),
        RoomRequestOutcome.unknown => MutationUnknown(),
      };
    } on Object catch (error) {
      // 未归类的错误可能发生在请求发出后；错误文本可能含链接或凭据，只记类型。
      AppLog.error(
        _logSource,
        'mutation ended unexpectedly',
        type: '${error.runtimeType}',
      );
      if (generation != _generation) return MutationNotSent(_leftRoom);
      unawaited(_sync());
      return MutationUnknown();
    }
  }

  /// 失败时抛出 [RoomRequestException]。
  Future<T> query<T>(Future<T> Function(RoomCommands c) run) async {
    final transport = _transport;
    if (transport == null) {
      throw const RoomRequestException(
        message: _notConnected,
        outcome: RoomRequestOutcome.notSent,
      );
    }
    return run(RoomCommands(transport));
  }

  /// 连不上服务端时，网络恢复后再试一次。
  Future<void> restoreLastRoom() async {
    if (_transport != null || state.activeRoomId != null) return;
    await _restore();
  }

  Future<void> _restore() async {
    if (_restoring || _serverChanges > 0) return;
    _restoring = true;
    _unrestored = null;
    try {
      final room = ref.read(lastRoomStoreProvider).read()?.trim();
      if (room == null || room.isEmpty) return;
      final joining = openRoom(room);
      // openRoom 在首次 await 之前已同步递增尝试编号。
      final attempt = _attempt;
      final result = await joining;
      if (result case RoomJoinFailed(failure: RoomFailure.unavailable)
          when attempt == _attempt && _transport == null) {
        _unrestored = attempt;
      }
    } finally {
      _restoring = false;
    }
  }

  // 无需新建连接的进房请求的结果。
  RoomJoin _settled() {
    final failure = state.failure;
    final listing = _listing;
    if (failure != null) {
      return RoomJoinFailed(
        failure,
        state.errorMessage ?? _enterFailed,
        room: listing,
      );
    }
    return listing == null ? _replaced : RoomJoined(listing);
  }

  bool get _retryable =>
      _reentering ||
      state.failure == RoomFailure.authorization ||
      state.failure == RoomFailure.unavailable;

  bool _names(String ref) {
    if (ref == _ref) return true;
    final listing = _listing;
    return listing != null && (_sameId(ref, listing.id) || ref == listing.slug);
  }

  bool _isActive(String roomId) {
    final active = state.activeRoomId;
    return active != null && _sameId(roomId, active);
  }

  // 房间 id 是 UUID，服务端匹配时不区分大小写。
  bool _sameId(String a, String b) => a.toLowerCase() == b.toLowerCase();

  // 状态在返回前已同步更新，只有释放旧连接是异步的：并发的 openRoom 已能看到
  // 新房间。
  Future<void> _enter(String target, RoomListing? listing, _RoomServer server) {
    final sameRoom = listing != null && _isActive(listing.id);
    _generation++;
    _reentering = false;
    _ref = target;
    _listing = listing;
    _server = server;
    final released = _release();
    state = RoomState(
      status: RoomConnectionStatus.connecting,
      activeRoomId: listing?.id,
      roomName: listing?.name,
      roomSlug: listing?.slug,
      notices: sameRoom ? state.notices : const [],
    );
    return released;
  }

  Future<void> _release() async {
    _cancelTrackEndSync();
    final cancelled = _subscription?.cancel();
    final transport = _transport;
    _subscription = null;
    _transport = null;
    _replica = null;
    _syncing = false;
    await cancelled;
    await transport?.stop();
  }

  Future<String> _ticket(
    RoomListing listing,
    String? password,
    int attempt, {
    required AlistenApi api,
    required CredentialStore credentials,
  }) async {
    final saved = await credentials.readTicket(listing.id);
    if (saved != null && saved.isNotEmpty) return saved;
    if (attempt != _attempt) throw const _Superseded();
    final identity = ref.read(identityControllerProvider.notifier);
    await identity.ensureMember();
    if (attempt != _attempt) throw const _Superseded();
    final token = await credentials.readMemberToken();
    try {
      final ticket = await api.createTicket(listing.id, password: password);
      await credentials.writeTicket(listing.id, ticket);
      return ticket;
    } on ApiException catch (error) {
      if (error.code != _unauthorized) rethrow;
      // 尝试作废时不得替换身份：可能已切换服务器，替换的会是新服务器的身份。
      if (attempt != _attempt) throw const _Superseded();
      final memberRejected = await _memberRejected(api);
      if (attempt != _attempt) throw const _Superseded();
      if (!memberRejected) rethrow;
      // 被拒的票据请求不以新身份重发。
      try {
        await identity.replaceAfterUnauthorized(rejectedToken: token);
      } on Object {
        throw const _IdentityReplaced(renewed: false);
      }
      throw const _IdentityReplaced(renewed: true);
    }
  }

  // 密码错误和 memberToken 被拒时票据请求都返回 UNAUTHORIZED，只有成员接口能
  // 区分；密码输错不得导致身份被替换。
  Future<bool> _memberRejected(AlistenApi api) async {
    try {
      await api.getMe();
      return false;
    } on ApiException catch (error) {
      return error.code == _unauthorized;
    } on Object {
      return false;
    }
  }

  RoomJoin _refuse(
    String target,
    RoomListing? listing,
    Object error,
    _RoomServer server,
  ) {
    final (failure, message) = _describe(error);
    if (_transport == null || state.failure != null) {
      unawaited(_enter(target, listing, server));
      _stopWith(failure, message);
    }
    return RoomJoinFailed(failure, message, room: listing);
  }

  (RoomFailure, String) _describe(Object error) {
    final failure = switch (error) {
      _IdentityReplaced() ||
      ApiException(code: _unauthorized) => RoomFailure.authorization,
      ApiException(code: 'NOT_FOUND') => RoomFailure.notFound,
      ApiException(code: 'CLIENT_OUTDATED') => RoomFailure.outdated,
      // 无法解析的 REST 响应可能来自强制门户（Wi-Fi 登录页），仍按可重试处理；
      // 其错误消息已提示升级。
      _ => RoomFailure.unavailable,
    };
    return (
      failure,
      switch (error) {
        _IdentityReplaced(renewed: true) => '身份已更新，没有进入房间，请再进入一次。',
        _IdentityReplaced() => identityLostNotice,
        _ when failure == RoomFailure.outdated => _outdatedMessage,
        ApiException(:final message) => message,
        _ => _enterFailed,
      },
    );
  }

  void _onEvent(RoomTransportEvent event, int generation) {
    if (generation != _generation) return;
    switch (event) {
      case RoomConnectionChanged(:final status, :final retryIn):
        state = state.copyWith(
          status: status,
          nextRetryAt: retryIn == null
              ? null
              : ref.read(roomNowProvider)().add(retryIn),
        );
      case RoomHelloReceived(:final hello):
        final roomId = state.activeRoomId ?? hello.room.room.id;
        _replica = RoomReplica(hello.room);
        _syncing = false;
        state = state.copyWith(
          status: RoomConnectionStatus.open,
          nextRetryAt: null,
          mayReconnectNow: true,
          activeRoomId: roomId,
          snapshot: hello.room,
          member: hello.member,
          failure: null,
          errorMessage: null,
          liveUpdate: false,
        );
        unawaited(_saveLastRoom(roomId));
      case RoomEventReceived(event: final roomEvent):
        _receive(roomEvent);
      case RoomErrorReceived(:final code):
        // 握手被拒后紧接着会停止或重连，原因由它们报告；其余错误事件只回应本
        // 客户端从不发送的帧。
        AppLog.debug(_logSource, 'error event', code: code);
      case RoomStopped(:final code):
        if (_sessionChanges > 0) {
          _heldStop = (code: code, generation: generation);
          return;
        }
        _onStopped(code);
    }
  }

  void _receive(RoomEvent event) {
    final replica = _replica;
    if (replica == null) return;
    final result = replica.receive(event);
    final notice = result.notice;
    if (result.changed || notice != null) {
      state = state.copyWith(
        snapshot: replica.state,
        notices: notice == null ? null : _appendNotice(state.notices, notice),
        liveUpdate: result.changed ? true : null,
      );
    }
    if (result.syncRequired) unawaited(_sync());
  }

  void _onStopped(int code) {
    final roomId = state.activeRoomId;
    final credentials = _server?.credentials;
    if (code == 4401 && roomId != null && credentials != null) {
      unawaited(credentials.deleteTicket(roomId));
    }
    if (code == 4401) unawaited(_verifyIdentity());
    final failure = switch (code) {
      4401 => RoomFailure.authorization,
      4404 => RoomFailure.notFound,
      4426 => RoomFailure.outdated,
      _ => RoomFailure.unavailable,
    };
    _stopWith(failure, switch (failure) {
      RoomFailure.authorization => '房间票据已失效，请重新验证后进入。',
      RoomFailure.notFound => '房间不存在或已经关闭。',
      RoomFailure.outdated => _outdatedMessage,
      RoomFailure.unavailable => '与房间的连接已经停止。',
    });
  }

  // 4401 可能表示票据所属的会话被删除了，例如在别处修改了密码。身份被拒时
  // restore 会丢弃它，会话代号随之变化，由监听重新进入。
  Future<void> _verifyIdentity() async {
    try {
      await ref.read(identityControllerProvider.notifier).restore();
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'identity not verified after 4401',
        code: error is ApiException ? error.code : null,
      );
    }
  }

  // 清空快照会同时停止播放。
  void _stopWith(RoomFailure failure, String message) {
    _cancelTrackEndSync();
    _replica = null;
    _syncing = false;
    state = state.copyWith(
      status: RoomConnectionStatus.stopped,
      nextRetryAt: null,
      roomName: state.snapshot?.room.name ?? state.roomName,
      snapshot: null,
      member: null,
      failure: failure,
      errorMessage: message,
      liveUpdate: false,
    );
    if (failure == RoomFailure.notFound || failure == RoomFailure.outdated) {
      unawaited(_forgetLastRoom());
    }
  }

  void _cancelTrackEndSync() {
    _trackEndSync?.cancel();
    _trackEndSync = null;
    _ended = null;
  }

  static PlaybackIdentity? _playback(RoomState room) {
    final nowPlaying = room.snapshot?.nowPlaying;
    if (nowPlaying == null) return null;
    return PlaybackIdentity(
      entryId: nowPlaying.entry.id,
      startedAtMs: nowPlaying.startedAtMs,
    );
  }

  Future<void> _sync() async {
    final transport = _transport;
    final replica = _replica;
    if (_syncing || transport == null || replica == null) return;
    if (state.status != RoomConnectionStatus.open) return;
    _syncing = true;
    final commands = RoomCommands(transport);
    try {
      do {
        await replica.sync(commands.sync);
        if (!identical(replica, _replica)) return;
        state = state.copyWith(snapshot: replica.state, liveUpdate: false);
        // 快照到达后、此处恢复执行前出现的跳号会让副本停在待同步状态，它触发的
        // 同步又因 [_syncing] 被忽略，所以要再同步一次。
      } while (replica.behind || replica.syncing);
    } on RoomRequestException catch (error) {
      if (!identical(replica, _replica)) return;
      if (error.code == LocalErrorCodes.protocolMismatch) {
        _stopWith(RoomFailure.outdated, _outdatedMessage);
        unawaited(transport.stop());
        return;
      }
      // 不重试：下次跳号会再次请求同步，重连也会从新快照开始。
      AppLog.debug(
        _logSource,
        'sync failed',
        code: error.code,
        outcome: error.outcome,
      );
    } on Object catch (error) {
      // 例如协议漂移导致快照映射失败，同样不重试。错误文本可能含链接或凭据，
      // 日志只记类型。
      AppLog.error(
        _logSource,
        'sync ended unexpectedly',
        type: '${error.runtimeType}',
      );
    } finally {
      if (identical(replica, _replica)) _syncing = false;
    }
  }

  Future<void> _saveLastRoom(String roomId) async {
    final lastRoom = _server?.lastRoom;
    if (lastRoom == null) return;
    try {
      await lastRoom.write(roomId);
    } on Object {
      AppLog.warn(_logSource, 'last room not saved');
    }
  }

  Future<void> _forgetLastRoom() async {
    final names = {?_ref, ?state.activeRoomId};
    final lastRoom = _server?.lastRoom;
    if (lastRoom == null) return;
    try {
      final saved = lastRoom.read();
      if (saved != null && names.contains(saved)) {
        await lastRoom.clear();
      }
    } on Object {
      AppLog.warn(_logSource, 'last room not forgotten');
    }
  }
}

typedef _RoomServer = ({CredentialStore credentials, LastRoomStore lastRoom});

final class _IdentityReplaced implements Exception {
  const _IdentityReplaced({required this.renewed});

  /// 为 false 时被拒的身份已丢弃，但未能创建新身份。
  final bool renewed;
}

final class _Superseded implements Exception {
  const _Superseded();
}

List<RoomEvent> _appendNotice(List<RoomEvent> notices, RoomEvent notice) {
  final kept = notices.length < _maxNotices
      ? notices
      : notices.sublist(notices.length - _maxNotices + 1);
  return [...kept, notice];
}
