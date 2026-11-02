import 'package:alisten/domain/room/room.dart';

final class RoomReplicaResult {
  const RoomReplicaResult({
    required this.changed,
    required this.notice,
    required this.syncRequired,
  });

  const RoomReplicaResult.ignored()
    : this(changed: false, notice: null, syncRequired: false);

  final bool changed;
  final RoomEvent? notice;
  final bool syncRequired;
}

/// 游标与 [state] 分开保存：聊天和动态通知推进游标，但不产生新快照，
/// 所以只有房间状态真正变化时 [state] 才会换成新的对象。
final class RoomReplica {
  RoomReplica(RoomSnapshot snapshot)
    : _state = snapshot,
      _term = snapshot.term,
      _seq = snapshot.seq;

  RoomSnapshot _state;
  int _term;
  int _seq;
  bool _waiting = false;
  bool _behind = false;
  int _noticeTerm = 0;
  int _noticeSeq = 0;
  int _droppedTerm = 0;
  int _droppedSeq = 0;

  RoomSnapshot get state => _state;

  bool get syncing => _waiting;

  /// 最近一次快照是否早于等待它期间丢弃的事件；只有再取一次快照才能补上。
  bool get behind => _behind;

  RoomReplicaResult receive(RoomEvent event) {
    if (event.term < _term) return const RoomReplicaResult.ignored();
    if (!_waiting) {
      if (event.term == _term && event.seq <= _seq) {
        return const RoomReplicaResult.ignored();
      }
      if (event.term == _term &&
          event.seq == _seq + 1 &&
          event is! UnreadableRoomEvent) {
        _seq = event.seq;
        if (_isNotice(event)) {
          return RoomReplicaResult(
            changed: false,
            notice: _notice(event),
            syncRequired: false,
          );
        }
        _state = _apply(event);
        return const RoomReplicaResult(
          changed: true,
          notice: null,
          syncRequired: false,
        );
      }
      _waiting = true;
      return RoomReplicaResult(
        changed: false,
        notice: _isNotice(event) ? _notice(event) : null,
        syncRequired: true,
      );
    }
    _dropped(event);
    return RoomReplicaResult(
      changed: false,
      notice: _isNotice(event) ? _notice(event) : null,
      syncRequired: false,
    );
  }

  Future<void> sync(Future<RoomSnapshot> Function() fetchSnapshot) async {
    _waiting = true;
    try {
      applySnapshot(await fetchSnapshot());
    } finally {
      _waiting = false;
    }
  }

  void applySnapshot(RoomSnapshot snapshot) {
    _state = snapshot;
    _term = snapshot.term;
    _seq = snapshot.seq;
    _waiting = false;
    _behind = _after(_droppedTerm, _droppedSeq, snapshot.term, snapshot.seq);
    _droppedTerm = 0;
    _droppedSeq = 0;
    if (_after(snapshot.term, snapshot.seq, _noticeTerm, _noticeSeq)) {
      _noticeTerm = snapshot.term;
      _noticeSeq = snapshot.seq;
    }
  }

  void _dropped(RoomEvent event) {
    if (_after(event.term, event.seq, _droppedTerm, _droppedSeq)) {
      _droppedTerm = event.term;
      _droppedSeq = event.seq;
    }
  }

  RoomSnapshot _apply(RoomEvent event) {
    final term = event.term;
    final seq = event.seq;
    return switch (event) {
      PlaybackUpdatedEvent() => _state.copyWith(
        term: term,
        seq: seq,
        nowPlaying: event.nowPlaying,
      ),
      QueueUpdatedEvent() => _state.copyWith(
        term: term,
        seq: seq,
        pending: event.pending,
        items: event.items,
      ),
      MembersUpdatedEvent() => _state.copyWith(
        term: term,
        seq: seq,
        members: event.members,
        onlineCount: event.onlineCount,
      ),
      SettingsUpdatedEvent() => _state.copyWith(
        term: term,
        seq: seq,
        playMode: event.playMode,
      ),
      RoomUpdatedEvent() => _state.copyWith(
        term: term,
        seq: seq,
        room: RoomInfo(
          id: _state.room.id,
          name: event.name,
          description: event.description,
          kind: _state.room.kind,
        ),
      ),
      ChatMessageEvent() ||
      RoomActivityEvent() ||
      UnreadableRoomEvent() => _state,
    };
  }

  RoomEvent? _notice(RoomEvent event) {
    if (!_after(event.term, event.seq, _noticeTerm, _noticeSeq)) return null;
    _noticeTerm = event.term;
    _noticeSeq = event.seq;
    return event;
  }

  bool _isNotice(RoomEvent event) {
    return event is ChatMessageEvent || event is RoomActivityEvent;
  }

  bool _after(int term, int seq, int otherTerm, int otherSeq) {
    return term > otherTerm || (term == otherTerm && seq > otherSeq);
  }
}
