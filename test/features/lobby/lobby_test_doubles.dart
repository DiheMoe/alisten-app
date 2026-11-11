import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/domain/track/track.dart';
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

  /// `getMe` 返回的成员；为 null 时返回 [member]。登录成功后换成账号的成员。
  Member? me;
  Account? account;
  bool recordListens = true;

  int registerCalls = 0;
  Exception? registerError;
  Completer<void>? registerGate;
  Account registeredAccount = const Account(username: 'mao', github: false);

  int loginCalls = 0;
  ({String username, String password, String? device})? lastLogin;
  Exception? loginError;
  Completer<void>? loginGate;
  SignedIn signedIn = const SignedIn(
    memberToken: 'account-token',
    member: accountMember,
    account: Account(username: 'mao', github: false),
    device: issuedDevice,
  );

  int logoutCalls = 0;
  Exception? logoutError;

  int changePasswordCalls = 0;
  Exception? changePasswordError;
  Completer<void>? changePasswordGate;

  int getSiteCalls = 0;
  Exception? getSiteError;
  SiteCapabilities site = const SiteCapabilities(
    registrationOpen: true,
    githubLogin: false,
  );
  PairingCode pairingCode = PairingCode(
    code: 'ABCD2345',
    expiresAtMs: 1700000300000,
    qrPng: Uint8List.fromList(const [1, 2, 3]),
  );
  int createPairingCodeCalls = 0;
  Exception? createPairingCodeError;
  Future<PairingCode> Function()? createPairingCodeHandler;

  int redeemCalls = 0;
  String? redeemedCode;
  Exception? redeemError;
  Completer<void>? redeemGate;
  SignedIn paired = const SignedIn(
    memberToken: 'paired-token',
    member: accountMember,
    account: Account(username: 'mao', github: false),
  );

  final List<({GithubIntent intent, String nonce, String? currentPassword})>
  githubStarts = [];
  Exception? startGithubError;
  Completer<void>? startGithubGate;
  Uri githubUrl = Uri.parse('https://github.com/login/oauth/authorize?state=s');

  final List<({String code, String nonce})> githubFinishes = [];
  Exception? finishGithubError;
  Completer<void>? finishGithubGate;
  GithubExchange githubExchange = const GithubExchange(
    member: member,
    account: Account(github: true),
  );

  int unbindCalls = 0;
  String? unbindPassword;
  Exception? unbindError;
  Completer<void>? unbindGate;

  Completer<Member>? updateMeResult;

  Completer<void>? createMemberGate;

  Completer<void>? getRoomGate;

  Completer<void>? createRoomGate;

  Member Function(String? name, String? email)? updateMeHandler;

  Future<List<RoomListing>> Function()? listRoomsHandler;

  void Function()? onCreateTicket;

  List<Listen> listens = [];
  int listMyListensCalls = 0;
  Exception? listMyListensError;

  /// 有剩余时，每次读取按顺序取出一个并以它的结果为准，不读 [listens]。
  final List<Completer<List<Listen>>> listMyListensResults = [];

  /// 历史请求按到达的顺序记下：`list`、`remove`、`clear`。
  final List<String> listenRequests = [];

  final List<Track> removedListens = [];
  Exception? removeMyListenError;
  Completer<void>? removeMyListenGate;

  int clearMyListensCalls = 0;
  Exception? clearMyListensError;

  final List<bool> listenRecordingWrites = [];
  Exception? setListenRecordingError;
  Completer<void>? setListenRecordingGate;

  @override
  Future<({Member member, String memberToken})> createMember() async {
    createMemberCalls++;
    final error = createMemberError;
    if (error != null) throw error;
    await createMemberGate?.future;
    return (member: createdMember, memberToken: 'new-member-token');
  }

  @override
  Future<MemberProfile> getMe() async {
    getMeCalls++;
    final error = getMeError;
    if (error != null) throw error;
    final pending = getMeResult;
    final current = pending != null ? await pending.future : (me ?? member);
    return MemberProfile(
      member: current,
      account: account,
      recordListens: recordListens,
    );
  }

  @override
  Future<Account> register({
    required String username,
    required String password,
  }) async {
    registerCalls++;
    await registerGate?.future;
    final error = registerError;
    if (error != null) throw error;
    account = registeredAccount;
    return registeredAccount;
  }

  @override
  Future<SignedIn> login({
    required String username,
    required String password,
    String? device,
  }) async {
    loginCalls++;
    lastLogin = (username: username, password: password, device: device);
    await loginGate?.future;
    final error = loginError;
    if (error != null) throw error;
    me = signedIn.member;
    account = signedIn.account;
    return signedIn;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    final error = logoutError;
    if (error != null) throw error;
    me = null;
    account = null;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
    await changePasswordGate?.future;
    final error = changePasswordError;
    if (error != null) throw error;
  }

  @override
  Future<SiteCapabilities> getSite() async {
    getSiteCalls++;
    final error = getSiteError;
    if (error != null) throw error;
    return site;
  }

  @override
  Future<PairingCode> createPairingCode() async {
    createPairingCodeCalls++;
    final error = createPairingCodeError;
    if (error != null) throw error;
    final handler = createPairingCodeHandler;
    if (handler != null) return handler();
    return pairingCode;
  }

  @override
  Future<SignedIn> redeemPairingCode(String code) async {
    redeemCalls++;
    redeemedCode = code;
    await redeemGate?.future;
    final error = redeemError;
    if (error != null) throw error;
    me = paired.member;
    account = paired.account;
    return paired;
  }

  @override
  Future<Uri> startGithubLogin({
    required GithubIntent intent,
    required String nonce,
    String? currentPassword,
  }) async {
    githubStarts.add((
      intent: intent,
      nonce: nonce,
      currentPassword: currentPassword,
    ));
    await startGithubGate?.future;
    final error = startGithubError;
    if (error != null) throw error;
    return githubUrl;
  }

  @override
  Future<GithubExchange> finishGithubLogin({
    required String code,
    required String nonce,
  }) async {
    githubFinishes.add((code: code, nonce: nonce));
    await finishGithubGate?.future;
    final error = finishGithubError;
    if (error != null) throw error;
    final exchange = githubExchange;
    if (exchange.signedIn != null) me = exchange.member;
    account = exchange.account;
    return exchange;
  }

  @override
  Future<void> unbindGithub({required String currentPassword}) async {
    unbindCalls++;
    unbindPassword = currentPassword;
    await unbindGate?.future;
    final error = unbindError;
    if (error != null) throw error;
    final current = account;
    if (current != null) {
      account = Account(
        username: current.username,
        email: current.email,
        github: false,
      );
    }
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

  @override
  Future<List<Listen>> listMyListens() async {
    listMyListensCalls++;
    listenRequests.add('list');
    final error = listMyListensError;
    if (error != null) throw error;
    if (listMyListensResults.isNotEmpty) {
      return listMyListensResults.removeAt(0).future;
    }
    return List.of(listens);
  }

  @override
  Future<void> removeMyListen(Track track) async {
    listenRequests.add('remove');
    removedListens.add(track);
    await removeMyListenGate?.future;
    final error = removeMyListenError;
    if (error != null) throw error;
    listens = [
      for (final listen in listens)
        if (trackKey(listen.track) != trackKey(track)) listen,
    ];
  }

  @override
  Future<void> clearMyListens() async {
    clearMyListensCalls++;
    listenRequests.add('clear');
    final error = clearMyListensError;
    if (error != null) throw error;
    listens = [];
  }

  @override
  Future<void> setListenRecording(bool on) async {
    listenRecordingWrites.add(on);
    await setListenRecordingGate?.future;
    final error = setListenRecordingError;
    if (error != null) throw error;
    recordListens = on;
  }
}

final class FakeCredentialStore implements CredentialStore {
  String? memberToken;
  final Map<String, String> tickets = {};
  final List<String> writtenTickets = [];
  int deleteMemberCalls = 0;
  final Map<String, String> loginDevices = {};
  int writeLoginDeviceCalls = 0;
  Completer<void>? readLoginDeviceGate;
  int deleteTicketsCalls = 0;
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

  @override
  Future<void> deleteTickets() async {
    deleteTicketsCalls++;
    tickets.clear();
  }

  @override
  Future<String?> readLoginDevice(String username) async {
    await readLoginDeviceGate?.future;
    return loginDevices[username];
  }

  @override
  Future<void> writeLoginDevice(String username, String device) async {
    writeLoginDeviceCalls++;
    loginDevices[username] = device;
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
    loginDevices.clear();
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

const deviceCredential = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM-_01';
const issuedDevice = 'zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONML-_9';
const accountMember = Member(
  id: 'account-member',
  name: '账号听众',
  avatarHash: '',
);
