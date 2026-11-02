import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> loadPreferences([
  Map<String, Object> values = const {},
]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<Override> preferencesOverride([
  Map<String, Object> values = const {},
]) async {
  return sharedPreferencesProvider.overrideWithValue(
    await loadPreferences(values),
  );
}

final class FakeAlistenApi implements AlistenApi {
  List<RoomListing> rooms = [];
  Exception? listError;
  Exception? createRoomError;
  Exception? ticketError;
  Exception? getMeError;
  Exception? getRoomError;
  Exception? updateMeError;
  Exception? createMemberError;
  int updateMeCalls = 0;
  String? updatedName;
  String? updatedEmail;
  int createMemberCalls = 0;
  int createRoomCalls = 0;
  int listRoomsCalls = 0;
  int createTicketCalls = 0;
  int getMeCalls = 0;
  int getRoomCalls = 0;
  String? lastGetRoomRef;

  static const member = Member(id: 'member-id', name: '听众', avatarHash: '');

  Member createdMember = member;
  Completer<Member>? getMeResult;
  Completer<Member>? updateMeResult;

  Completer<void>? createMemberGate;

  Completer<void>? getRoomGate;

  Completer<void>? createRoomGate;

  Member Function(String? name, String? email)? updateMeHandler;

  Future<List<RoomListing>> Function()? listRoomsHandler;

  void Function()? onCreateTicket;

  @override
  Future<({Member member, String memberToken})> createMember() async {
    createMemberCalls++;
    final error = createMemberError;
    if (error != null) throw error;
    await createMemberGate?.future;
    return (member: createdMember, memberToken: 'new-member-token');
  }

  @override
  Future<Member> getMe() async {
    getMeCalls++;
    final error = getMeError;
    if (error != null) throw error;
    final pending = getMeResult;
    if (pending != null) return pending.future;
    return member;
  }

  @override
  Future<Member> updateMe({String? name, String? email}) async {
    updateMeCalls++;
    updatedName = name;
    updatedEmail = email;
    final error = updateMeError;
    if (error != null) throw error;
    final pending = updateMeResult;
    if (pending != null) return pending.future;
    final handler = updateMeHandler;
    if (handler != null) return handler(name, email);
    return Member(
      id: member.id,
      name: name ?? member.name,
      avatarHash: email == null ? member.avatarHash : 'avatar-hash',
    );
  }

  @override
  Future<List<RoomListing>> listRooms() async {
    listRoomsCalls++;
    final handler = listRoomsHandler;
    if (handler != null) return handler();
    final error = listError;
    if (error != null) throw error;
    return rooms;
  }

  @override
  Future<RoomListing> getRoom(String ref) async {
    getRoomCalls++;
    lastGetRoomRef = ref;
    await getRoomGate?.future;
    final error = getRoomError;
    if (error != null) throw error;
    for (final room in rooms) {
      if (room.id == ref || room.slug == ref) return room;
    }
    return RoomListing(
      id: ref,
      slug: null,
      name: '新房间',
      description: '',
      kind: RoomKind.ephemeral,
      hasPassword: false,
      onlineCount: 0,
    );
  }

  @override
  Future<String> createRoom({
    required String name,
    required String description,
    String? password,
  }) async {
    createRoomCalls++;
    final gate = createRoomGate;
    if (gate != null) await gate.future;
    final error = createRoomError;
    if (error != null) throw error;
    return 'created-room-id';
  }

  @override
  Future<String> createTicket(String id, {String? password}) async {
    createTicketCalls++;
    onCreateTicket?.call();
    final error = ticketError;
    if (error != null) throw error;
    return 'ticket-for-$id';
  }
}

final class FakeCredentialStore implements CredentialStore {
  String? memberToken;
  final Map<String, String> tickets = {};
  final List<String> writtenTickets = [];
  int deleteMemberCalls = 0;
  Exception? readMemberTokenError;

  @override
  Future<String?> readMemberToken() async {
    final error = readMemberTokenError;
    if (error != null) throw error;
    return memberToken;
  }

  @override
  Future<void> writeMemberToken(String token) async {
    memberToken = token;
  }

  @override
  Future<void> deleteMemberToken() async {
    deleteMemberCalls++;
    memberToken = null;
  }

  Completer<void>? readTicketGate;

  @override
  Future<String?> readTicket(String roomId) async {
    await readTicketGate?.future;
    return tickets[roomId];
  }

  @override
  Future<void> writeTicket(String roomId, String ticket) async {
    tickets[roomId] = ticket;
    writtenTickets.add(roomId);
  }

  @override
  Future<void> deleteTicket(String roomId) async {
    tickets.remove(roomId);
  }

  int clearCalls = 0;

  Exception? clearError;

  @override
  Future<void> clear() async {
    clearCalls++;
    final error = clearError;
    if (error != null) throw error;
    memberToken = null;
    tickets.clear();
  }
}

final class FakeLocalEmail {
  int clearCalls = 0;

  Future<void> clear() async {
    clearCalls++;
  }
}

RoomListing roomListing({
  String id = 'room-id',
  String? slug = 'listen',
  String name = '一起听',
  String description = '每晚八点',
  bool hasPassword = false,
  int onlineCount = 3,
}) {
  return RoomListing(
    id: id,
    slug: slug,
    name: name,
    description: description,
    kind: RoomKind.ephemeral,
    hasPassword: hasPassword,
    onlineCount: onlineCount,
  );
}

const unauthorized = ApiException(
  code: 'UNAUTHORIZED',
  message: '身份已失效',
  status: 401,
);
