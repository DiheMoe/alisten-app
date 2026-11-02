import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/http.gen.dart' as http;
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/application/admin_api.dart';
import 'package:alisten/features/admin/application/admin_models.dart';

// 扫码发起与查询、网易云和 B 站的账号读取要等服务端调用音源，服务端对音源的
// 超时是 30 秒。客户端先断开会让服务端中途放弃，扫码查询可能因此丢失已确认但
// 尚未保存的登录。
const adminUpstreamTimeout = Duration(seconds: 45);

final class RestAdminApi implements AdminApi {
  const RestAdminApi(this._transport);

  final ApiTransport _transport;

  @override
  Future<List<RoomListing>> listRooms(String token) {
    return _request(
      http.RestEndpoints.adminListRooms,
      token: token,
      decode: (json) =>
          protocol.AdminListRoomsResponse.fromJson(json).items
              .map(toDomainRoomListing)
              .toList(growable: false),
    );
  }

  @override
  Future<String> getBrandName() {
    return _request(
      http.RestEndpoints.getSite,
      decode: (json) => protocol.GetSiteResponse.fromJson(json).brandName,
    );
  }

  @override
  Future<String> updateBrandName(String token, String brandName) {
    return _request(
      http.RestEndpoints.adminUpdateSite,
      token: token,
      body: protocol.AdminUpdateSiteRequest(brandName: brandName).toJson(),
      decode: (json) =>
          protocol.AdminUpdateSiteResponse.fromJson(json).brandName,
    );
  }

  @override
  Future<String> createRoom(String token, RoomDraft draft) {
    return _request(
      http.RestEndpoints.adminCreateRoom,
      token: token,
      body: protocol.AdminCreateRoomRequest(
        name: draft.name,
        description: draft.description,
        slug: draft.slug,
        password: draft.password,
      ).toJson(),
      decode: (json) => protocol.AdminCreateRoomResponse.fromJson(json).id,
    );
  }

  @override
  Future<void> updateRoom(String token, String roomId, RoomPatch patch) async {
    await _transport.execute(
      http.RestEndpoints.adminUpdateRoom,
      pathParameters: {'id': roomId},
      token: token,
      body: protocol.AdminUpdateRoomRequest(
        name: patch.name,
        description: patch.description,
        slug: patch.slug,
        password: patch.password,
      ).toJson(),
    );
  }

  @override
  Future<void> deleteRoom(String token, String roomId) async {
    await _transport.execute(
      http.RestEndpoints.adminDeleteRoom,
      pathParameters: {'id': roomId},
      token: token,
    );
  }

  @override
  Future<ApiKeyStatus> getApiKeyStatus(String token, String roomId) {
    return _request(
      http.RestEndpoints.adminGetRoomApiKey,
      pathParameters: {'id': roomId},
      token: token,
      decode: (json) {
        final response = protocol.AdminGetRoomApiKeyResponse.fromJson(json);
        return ApiKeyStatus(
          generated: response.set,
          createdAtMs: response.createdAtMs,
        );
      },
    );
  }

  @override
  Future<String> resetApiKey(String token, String roomId) {
    return _request(
      http.RestEndpoints.adminResetRoomApiKey,
      pathParameters: {'id': roomId},
      token: token,
      body: const protocol.AdminResetRoomApiKeyRequest().toJson(),
      decode: (json) => protocol.APIKey.fromJson(json).key,
    );
  }

  @override
  Future<SourceAccountStatus> getSourceAccount(
    String token,
    LoginSource source,
  ) {
    return _request(
      switch (source) {
        LoginSource.netease => http.RestEndpoints.adminGetNeteaseCredential,
        LoginSource.qq => http.RestEndpoints.adminGetQqCredential,
        LoginSource.bilibili => http.RestEndpoints.adminGetBilibiliCredential,
      },
      token: token,
      timeout: switch (source) {
        LoginSource.netease || LoginSource.bilibili => adminUpstreamTimeout,
        // 服务端只从保存的 Cookie 解析 QQ 号，不调用 QQ 音乐。
        LoginSource.qq => null,
      },
      decode: switch (source) {
        LoginSource.netease => (json) {
          final response = protocol.AdminGetNeteaseCredentialResponse.fromJson(
            json,
          );
          return _accountStatus(response.set, response.account);
        },
        LoginSource.qq => (json) {
          final response = protocol.AdminGetQqCredentialResponse.fromJson(json);
          return _accountStatus(response.set, response.account);
        },
        LoginSource.bilibili => (json) {
          final response = protocol.AdminGetBilibiliCredentialResponse.fromJson(
            json,
          );
          return _accountStatus(response.set, response.account);
        },
      },
    );
  }

  @override
  Future<QrLoginTicket> startQrLogin(
    String token,
    LoginSource source, {
    QqLoginType qqType = QqLoginType.qq,
  }) {
    final (endpoint, body) = switch (source) {
      LoginSource.netease => (
        http.RestEndpoints.adminStartNeteaseLogin,
        const protocol.AdminStartNeteaseLoginRequest().toJson(),
      ),
      LoginSource.qq => (
        http.RestEndpoints.adminStartQqLogin,
        protocol.AdminStartQqLoginRequest(type: _qqType(qqType)).toJson(),
      ),
      LoginSource.bilibili => (
        http.RestEndpoints.adminStartBilibiliLogin,
        const protocol.AdminStartBilibiliLoginRequest().toJson(),
      ),
    };
    return _request(
      endpoint,
      token: token,
      body: body,
      timeout: adminUpstreamTimeout,
      decode: (json) {
        final login = protocol.QRLogin.fromJson(json);
        return QrLoginTicket(
          key: login.key,
          qrImage: login.qrImage,
          expiresAtMs: login.expiresAtMs,
        );
      },
    );
  }

  @override
  Future<QrLoginCheck> checkQrLogin(
    String token,
    LoginSource source,
    String key, {
    QqLoginType qqType = QqLoginType.qq,
  }) {
    final (endpoint, body) = switch (source) {
      LoginSource.netease => (
        http.RestEndpoints.adminCheckNeteaseLogin,
        protocol.AdminCheckNeteaseLoginRequest(key: key).toJson(),
      ),
      LoginSource.qq => (
        http.RestEndpoints.adminCheckQqLogin,
        protocol.AdminCheckQqLoginRequest(
          key: key,
          type: _qqType(qqType),
        ).toJson(),
      ),
      LoginSource.bilibili => (
        http.RestEndpoints.adminCheckBilibiliLogin,
        protocol.AdminCheckBilibiliLoginRequest(key: key).toJson(),
      ),
    };
    return _request(
      endpoint,
      token: token,
      body: body,
      timeout: adminUpstreamTimeout,
      decode: (json) {
        final result = protocol.QRLoginResult.fromJson(json);
        return QrLoginCheck(
          state: switch (result.status) {
            protocol.QRLoginStatus.waiting => QrCheckState.waiting,
            protocol.QRLoginStatus.scanned => QrCheckState.scanned,
            protocol.QRLoginStatus.success => QrCheckState.success,
            protocol.QRLoginStatus.expired => QrCheckState.expired,
            protocol.QRLoginStatus.failed => QrCheckState.failed,
          },
          message: result.message,
        );
      },
    );
  }

  @override
  Future<YoutubeCookieStatus> getYoutubeCookie(String token) {
    return _request(
      http.RestEndpoints.adminGetYoutubeCredential,
      token: token,
      decode: (json) {
        final response = protocol.AdminGetYoutubeCredentialResponse.fromJson(
          json,
        );
        return YoutubeCookieStatus(
          saved: response.set,
          updatedAtMs: response.updatedAtMs,
        );
      },
    );
  }

  @override
  Future<void> setYoutubeCookie(String token, String cookies) async {
    await _transport.execute(
      http.RestEndpoints.adminSetYoutubeCredential,
      token: token,
      body: protocol.AdminSetYoutubeCredentialRequest(cookies: cookies)
          .toJson(),
    );
  }

  @override
  Future<void> deleteYoutubeCookie(String token) async {
    await _transport.execute(
      http.RestEndpoints.adminDeleteYoutubeCredential,
      token: token,
    );
  }

  static SourceAccountStatus _accountStatus(
    bool saved,
    protocol.SourceAccount? account,
  ) {
    return SourceAccountStatus(
      saved: saved,
      account: account == null
          ? null
          : SourceAccount(
              id: account.id,
              name: account.name,
              vip: account.vip,
              verified: account.verified,
            ),
    );
  }

  static protocol.QQLoginType _qqType(QqLoginType type) => switch (type) {
    QqLoginType.qq => protocol.QQLoginType.qq,
    QqLoginType.wx => protocol.QQLoginType.wx,
  };

  Future<T> _request<T>(
    http.RestEndpoint endpoint, {
    required T Function(Map<String, Object?> json) decode,
    String? token,
    Map<String, String> pathParameters = const {},
    Map<String, Object?> body = const {},
    Duration? timeout,
  }) async {
    final response = await _transport.execute(
      endpoint,
      pathParameters: pathParameters,
      body: body,
      token: token,
      timeout: timeout,
    );
    try {
      if (response is! Map<String, Object?>) {
        throw const FormatException('Response must be an object');
      }
      return decode(response);
    } on FormatException {
      AppLog.debug(
        'admin',
        'response not understood',
        type: endpoint.name,
        code: LocalErrorCodes.protocolMismatch,
      );
      throw ApiException.protocolMismatch(endpoint.successStatus);
    }
  }
}
