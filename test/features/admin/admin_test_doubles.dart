import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/index.dart';

/// 各 `…Gate` 不为 null 时，对应调用记录之后等它完成才回复。变更成功时像服务端
/// 一样更新 [rooms]、[apiKeyStatus]、[youtubeCookie] 和 [githubApp]。[createdDrafts]、
/// [updates]、[deletedRoomIds]、[savedCookies] 和 [savedGithubApps] 也记录失败的调用。
final class FakeAdminApi implements AdminApi {
  final List<String> tokens = [];
  List<RoomListing> rooms = [];
  Object? listRoomsError;
  Completer<void>? listRoomsGate;
  int listRoomsCalls = 0;
  String brandName = 'Alisten';
  Object? getBrandError;
  int getBrandCalls = 0;
  Object? updateBrandError;
  Completer<void>? updateBrandGate;
  String? updatedBrandName;
  String? savedBrandName;

  bool registrationOpen = true;
  Object? getRegistrationError;
  Object? setRegistrationError;
  final List<bool> registrationCalls = [];

  final Map<String, AdminAccountView> accounts = {};
  final List<String> resetUsernames = [];
  String resetPassword = 'reset-secret-password';
  Object? resetPasswordError;
  Completer<void>? resetPasswordGate;

  final List<RoomDraft> createdDrafts = [];
  Object? createRoomError;
  Completer<void>? createRoomGate;
  String createdRoomId = 'r-new';

  final List<({String roomId, RoomPatch patch})> updates = [];
  Object? updateRoomError;

  final List<String> deletedRoomIds = [];
  Object? deleteRoomError;

  ApiKeyStatus apiKeyStatus = const ApiKeyStatus(
    generated: true,
    createdAtMs: 1700000000000,
  );
  Object? getApiKeyStatusError;
  int getApiKeyStatusCalls = 0;
  String newApiKey = 'k-new';
  int resetAtMs = 1800000000000;
  Object? resetApiKeyError;
  Completer<void>? resetApiKeyGate;
  int resetApiKeyCalls = 0;

  final Map<LoginSource, SourceAccountStatus> sourceAccounts = {};
  final Map<LoginSource, Object> sourceAccountErrors = {};
  final List<LoginSource> sourceAccountCalls = [];

  /// 在调用时取值，之后修改不影响已在等待的调用。
  QrLoginTicket qrTicket = const QrLoginTicket(
    key: 'k-1',
    qrImage: 'data:image/png;base64,iVBORw0KGgo=',
    expiresAtMs: 1700000120000,
  );
  Object? startQrError;
  Completer<void>? startQrGate;
  final List<LoginSource> startedSources = [];
  final List<QqLoginType> startedQqTypes = [];

  final List<FakeQrCheck> checkResults = [];
  int checkCalls = 0;
  final List<String> checkedKeys = [];
  final List<QqLoginType> checkedQqTypes = [];

  YoutubeCookieStatus youtubeCookie = const YoutubeCookieStatus(
    saved: false,
    updatedAtMs: 0,
  );
  Object? getYoutubeCookieError;
  Completer<void>? getYoutubeCookieGate;
  int getYoutubeCookieCalls = 0;

  final List<String> savedCookies = [];
  Object? setYoutubeCookieError;
  Completer<void>? setYoutubeCookieGate;
  int youtubeCookieSavedAtMs = 1800000000000;
  Object? deleteYoutubeCookieError;
  Completer<void>? deleteYoutubeCookieGate;
  int deleteYoutubeCookieCalls = 0;

  GithubAppStatus githubApp = const GithubAppStatus(
    clientId: null,
    clientSecretSet: false,
    callbackUrl: 'https://example.com:8443/api/auth/github/callback',
  );
  Object? getGithubAppError;
  Completer<void>? getGithubAppGate;
  int getGithubAppCalls = 0;

  final List<({String clientId, String clientSecret})> savedGithubApps = [];
  Object? setGithubAppError;
  Completer<void>? setGithubAppGate;
  Object? deleteGithubAppError;
  Completer<void>? deleteGithubAppGate;
  int deleteGithubAppCalls = 0;

  @override
  Future<List<RoomListing>> listRooms(String token) async {
    listRoomsCalls++;
    tokens.add(token);
    await listRoomsGate?.future;
    if (listRoomsError case final error?) return Future.error(error);
    return rooms;
  }

  @override
  Future<String> getBrandName() async {
    getBrandCalls++;
    if (getBrandError case final error?) return Future.error(error);
    return brandName;
  }

  @override
  Future<bool> getRegistrationOpen() async {
    if (getRegistrationError case final error?) return Future.error(error);
    return registrationOpen;
  }

  @override
  Future<void> openRegistration(String token) => _setRegistration(token, true);

  @override
  Future<void> closeRegistration(String token) =>
      _setRegistration(token, false);

  Future<void> _setRegistration(String token, bool open) async {
    tokens.add(token);
    registrationCalls.add(open);
    if (setRegistrationError case final error?) return Future.error(error);
    registrationOpen = open;
  }

  @override
  Future<AdminAccountView> findAccount(String token, String username) async {
    tokens.add(token);
    final account = accounts[username];
    if (account == null) {
      return Future.error(
        const ApiException(code: 'NOT_FOUND', message: '账号不存在', status: 404),
      );
    }
    return account;
  }

  @override
  Future<String> resetAccountPassword(String token, String username) async {
    tokens.add(token);
    resetUsernames.add(username);
    await resetPasswordGate?.future;
    if (resetPasswordError case final error?) return Future.error(error);
    return resetPassword;
  }

  @override
  Future<String> updateBrandName(String token, String brandName) async {
    tokens.add(token);
    await updateBrandGate?.future;
    if (updateBrandError case final error?) return Future.error(error);
    updatedBrandName = brandName;
    return this.brandName = savedBrandName ?? brandName;
  }

  @override
  Future<String> createRoom(String token, RoomDraft draft) async {
    tokens.add(token);
    createdDrafts.add(draft);
    await createRoomGate?.future;
    if (createRoomError case final error?) return Future.error(error);
    rooms = [
      ...rooms,
      RoomListing(
        id: createdRoomId,
        slug: draft.slug,
        name: draft.name,
        description: draft.description,
        kind: RoomKind.persistent,
        hasPassword: draft.password != null,
        onlineCount: 0,
      ),
    ];
    return createdRoomId;
  }

  @override
  Future<void> updateRoom(String token, String roomId, RoomPatch patch) async {
    tokens.add(token);
    updates.add((roomId: roomId, patch: patch));
    if (updateRoomError case final error?) return Future.error(error);
    rooms = [
      for (final room in rooms)
        if (room.id != roomId)
          room
        else
          RoomListing(
            id: room.id,
            slug: switch (patch.slug) {
              null => room.slug,
              '' => null,
              final slug => slug,
            },
            name: patch.name ?? room.name,
            description: patch.description ?? room.description,
            kind: room.kind,
            hasPassword: switch (patch.password) {
              null => room.hasPassword,
              final password => password.isNotEmpty,
            },
            onlineCount: room.onlineCount,
          ),
    ];
  }

  @override
  Future<void> deleteRoom(String token, String roomId) async {
    tokens.add(token);
    deletedRoomIds.add(roomId);
    if (deleteRoomError case final error?) return Future.error(error);
    rooms = [
      for (final room in rooms)
        if (room.id != roomId) room,
    ];
  }

  @override
  Future<ApiKeyStatus> getApiKeyStatus(String token, String roomId) async {
    tokens.add(token);
    getApiKeyStatusCalls++;
    if (getApiKeyStatusError case final error?) return Future.error(error);
    return apiKeyStatus;
  }

  @override
  Future<String> resetApiKey(String token, String roomId) async {
    tokens.add(token);
    resetApiKeyCalls++;
    await resetApiKeyGate?.future;
    if (resetApiKeyError case final error?) return Future.error(error);
    apiKeyStatus = ApiKeyStatus(generated: true, createdAtMs: resetAtMs);
    return newApiKey;
  }

  @override
  Future<SourceAccountStatus> getSourceAccount(
    String token,
    LoginSource source,
  ) async {
    tokens.add(token);
    sourceAccountCalls.add(source);
    if (sourceAccountErrors[source] case final error?) {
      return Future.error(error);
    }
    return sourceAccounts[source] ?? const SourceAccountStatus(saved: false);
  }

  @override
  Future<QrLoginTicket> startQrLogin(
    String token,
    LoginSource source, {
    QqLoginType qqType = QqLoginType.qq,
  }) async {
    tokens.add(token);
    startedSources.add(source);
    startedQqTypes.add(qqType);
    final ticket = qrTicket;
    final error = startQrError;
    await startQrGate?.future;
    if (error != null) return Future.error(error);
    return ticket;
  }

  @override
  Future<QrLoginCheck> checkQrLogin(
    String token,
    LoginSource source,
    String key, {
    QqLoginType qqType = QqLoginType.qq,
  }) async {
    tokens.add(token);
    checkCalls++;
    checkedKeys.add(key);
    checkedQqTypes.add(qqType);
    final reply = checkResults.isEmpty
        ? const FakeQrCheck(QrCheckState.waiting)
        : checkResults.removeAt(0);
    if (reply.delay > Duration.zero) await Future<void>.delayed(reply.delay);
    if (reply.error case final error?) return Future.error(error);
    return QrLoginCheck(state: reply.state, message: reply.message);
  }

  @override
  Future<YoutubeCookieStatus> getYoutubeCookie(String token) async {
    tokens.add(token);
    getYoutubeCookieCalls++;
    final status = youtubeCookie;
    final error = getYoutubeCookieError;
    await getYoutubeCookieGate?.future;
    if (error != null) return Future.error(error);
    return status;
  }

  @override
  Future<void> setYoutubeCookie(String token, String cookies) async {
    tokens.add(token);
    savedCookies.add(cookies);
    await setYoutubeCookieGate?.future;
    if (setYoutubeCookieError case final error?) return Future.error(error);
    youtubeCookie = YoutubeCookieStatus(
      saved: true,
      updatedAtMs: youtubeCookieSavedAtMs,
    );
  }

  @override
  Future<void> deleteYoutubeCookie(String token) async {
    tokens.add(token);
    deleteYoutubeCookieCalls++;
    await deleteYoutubeCookieGate?.future;
    if (deleteYoutubeCookieError case final error?) return Future.error(error);
    youtubeCookie = const YoutubeCookieStatus(saved: false, updatedAtMs: 0);
  }

  @override
  Future<GithubAppStatus> getGithubApp(String token) async {
    tokens.add(token);
    getGithubAppCalls++;
    final status = githubApp;
    final error = getGithubAppError;
    await getGithubAppGate?.future;
    if (error != null) return Future.error(error);
    return status;
  }

  @override
  Future<void> setGithubApp(
    String token, {
    required String clientId,
    required String clientSecret,
  }) async {
    tokens.add(token);
    savedGithubApps.add((clientId: clientId, clientSecret: clientSecret));
    await setGithubAppGate?.future;
    if (setGithubAppError case final error?) return Future.error(error);
    githubApp = GithubAppStatus(
      clientId: clientId,
      clientSecretSet: true,
      callbackUrl: githubApp.callbackUrl,
    );
  }

  @override
  Future<void> deleteGithubApp(String token) async {
    tokens.add(token);
    deleteGithubAppCalls++;
    await deleteGithubAppGate?.future;
    if (deleteGithubAppError case final error?) return Future.error(error);
    githubApp = GithubAppStatus(
      clientId: null,
      clientSecretSet: false,
      callbackUrl: githubApp.callbackUrl,
    );
  }
}

final class FakeQrCheck {
  const FakeQrCheck(
    this.state, {
    this.message = '',
    this.delay = Duration.zero,
    this.error,
  });

  const FakeQrCheck.error(Object this.error, {this.delay = Duration.zero})
    : state = QrCheckState.waiting,
      message = '';

  final QrCheckState state;
  final String message;
  final Duration delay;
  final Object? error;
}

final class FakeQrImageLoader implements QrImageLoader {
  Uint8List bytes = Uint8List.fromList(const [1, 2, 3]);
  final Map<String, Uint8List> images = {};
  Object? error;
  final List<String> loaded = [];

  @override
  Future<Uint8List> load(String qrImage) async {
    loaded.add(qrImage);
    if (error case final error?) return Future.error(error);
    return images[qrImage] ?? bytes;
  }
}

final class FakeImageGallery implements ImageGallery {
  final List<({Uint8List bytes, String name})> saved = [];
  bool deny = false;
  Object? error;

  @override
  Future<void> saveImage(Uint8List bytes, String name) async {
    if (deny) throw const GalleryAccessDenied();
    if (error case final error?) return Future.error(error);
    saved.add((bytes: bytes, name: name));
  }
}

final class FakeSensitiveClipboard implements SensitiveClipboard {
  final List<String> copied = [];
  Object? error;

  @override
  Future<void> copy(String text) async {
    if (error case final error?) return Future.error(error);
    copied.add(text);
  }
}
