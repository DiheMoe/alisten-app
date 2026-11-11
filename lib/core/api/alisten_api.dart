import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/http.gen.dart' as http;
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logSource = 'api';

final apiTransportProvider = Provider<ApiTransport>((ref) {
  throw UnimplementedError('apiTransport 未注入');
});

final class ApiTransport {
  ApiTransport(this._dio, this._config) {
    _dio.options.baseUrl = _config.baseUrl;
  }

  final Dio _dio;
  final AppConfig _config;

  /// [timeout] 为 null 时用 [AppConfig.requestTimeout]，到时断开连接。
  Future<Object?> execute(
    http.RestEndpoint endpoint, {
    Map<String, String> pathParameters = const {},
    Map<String, Object?> body = const {},
    String? token,
    Duration? timeout,
  }) async {
    try {
      return await _execute(
        endpoint,
        pathParameters,
        body,
        token,
        timeout ?? _config.requestTimeout,
      );
    } on ApiException catch (error) {
      AppLog.debug(
        _logSource,
        'request failed',
        type: endpoint.name,
        code: error.code,
      );
      rethrow;
    }
  }

  Future<Object?> _execute(
    http.RestEndpoint endpoint,
    Map<String, String> pathParameters,
    Map<String, Object?> body,
    String? token,
    Duration timeout,
  ) async {
    if (endpoint.auth != http.HttpAuth.none &&
        (token == null || token.isEmpty)) {
      throw const ApiException(
        code: LocalErrorCodes.noToken,
        message: '缺少身份凭据，请重新进入后再试。',
        status: null,
      );
    }

    final cancelToken = CancelToken();
    final Response<String> response;
    try {
      response = await _dio
          .request<String>(
            endpoint.buildPath(pathParameters),
            data: endpoint.method == 'GET' ? null : body,
            cancelToken: cancelToken,
            options: Options(
              method: endpoint.method,
              contentType: Headers.jsonContentType,
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
              headers: {
                if (endpoint.auth != http.HttpAuth.none)
                  'authorization': 'Bearer $token',
              },
            ),
          )
          .timeout(
            timeout,
            onTimeout: () {
              cancelToken.cancel();
              throw const ApiException(
                code: LocalErrorCodes.network,
                message: '请求超时，请检查网络后重试。',
                status: null,
              );
            },
          );
    } on DioException catch (error) {
      throw ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: error.response?.statusCode,
      );
    }
    return _decodeResponse(endpoint, response);
  }

  Object? _decodeResponse(
    http.RestEndpoint endpoint,
    Response<String> response,
  ) {
    final status = response.statusCode ?? 0;
    final body = response.data ?? '';
    if (status != endpoint.successStatus) {
      throw status == 429
          ? _rateLimited(response.headers)
          : _decodeError(status, body);
    }
    if (status == 204) {
      return null;
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiException.protocolMismatch(status);
    }
  }

  ApiException _decodeError(int status, String body) {
    final Object? errorJson;
    try {
      final decoded = jsonDecode(body);
      errorJson = decoded is Map<String, Object?> ? decoded['error'] : null;
    } on FormatException {
      return _unreachable(status);
    }
    // 不符合协议错误格式的回复来自代理或网关，而不是 Alisten 接口。
    if (errorJson is! Map<String, Object?>) return _unreachable(status);
    try {
      final error = protocol.ErrorInfo.fromJson(errorJson);
      return ApiException(
        code: error.code.wireValue,
        message: error.message,
        status: status,
      );
    } on FormatException {
      return ApiException.protocolMismatch(status);
    }
  }

  // 429 无论正文是什么都表示请求被限流、未执行：协议的 `RATE_LIMITED` 就是
  // 429，而代理限流时（生产环境的 Traefik 对 `/api/admin/` 限流）返回纯文本。
  ApiException _rateLimited(Headers headers) {
    final seconds = int.tryParse(
      headers['retry-after']?.firstOrNull?.trim() ?? '',
    );
    return ApiException(
      code: protocol.ErrorCode.rateLimited.wireValue,
      message: '请求太频繁，请稍后再试。',
      status: 429,
      retryAfter: seconds == null || seconds < 0
          ? null
          : Duration(seconds: seconds),
    );
  }

  ApiException _unreachable(int status) {
    return ApiException(
      code: LocalErrorCodes.network,
      message: '服务器暂时无法访问（HTTP $status），请稍后重试。',
      status: status,
    );
  }
}

final class SignedIn {
  const SignedIn({
    required this.memberToken,
    required this.member,
    required this.account,
    this.device,
  });

  final String memberToken;
  final Member member;
  final Account account;

  /// 只有密码登录会返回：本机以后登录这个账号时要带上的凭证。
  final String? device;
}

abstract interface class AlistenApi {
  Future<({Member member, String memberToken})> createMember();

  Future<MemberProfile> getMe();

  Future<Account> register({
    required String username,
    required String password,
  });

  Future<SignedIn> login({
    required String username,
    required String password,
    String? device,
  });

  Future<void> logout();

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<SiteCapabilities> getSite();

  Future<Member> updateMe({String? name, String? email});

  Future<List<RoomListing>> listRooms();

  Future<RoomListing> getRoom(String ref);

  Future<String> createRoom({
    required String name,
    required String description,
    String? password,
  });

  Future<String> createTicket(String id, {String? password});
}

final alistenApiProvider = Provider<AlistenApi>((ref) {
  throw UnimplementedError('alistenApi 未注入');
});

final class RestAlistenApi implements AlistenApi {
  const RestAlistenApi(this._transport, this._memberTokenReader);

  final ApiTransport _transport;
  final Future<String?> Function() _memberTokenReader;

  @override
  Future<({Member member, String memberToken})> createMember() {
    return _request(
      http.RestEndpoints.createMember,
      body: const protocol.CreateMemberRequest().toJson(),
      decode: (json) {
        final response = protocol.CreateMemberResponse.fromJson(json);
        return (
          member: toDomainMember(response.member),
          memberToken: response.memberToken,
        );
      },
    );
  }

  @override
  Future<MemberProfile> getMe() {
    return _request(
      http.RestEndpoints.getMe,
      decode: (json) {
        final response = protocol.GetMeResponse.fromJson(json);
        final account = response.account;
        return MemberProfile(
          member: toDomainMember(response.member),
          account: account == null ? null : toDomainAccount(account),
          recordListens: response.recordListens,
        );
      },
    );
  }

  @override
  Future<Account> register({
    required String username,
    required String password,
  }) {
    return _request(
      http.RestEndpoints.register,
      body: protocol.RegisterRequest(
        username: username,
        password: password,
      ).toJson(),
      decode: (json) =>
          toDomainAccount(protocol.RegisterResponse.fromJson(json).account),
    );
  }

  @override
  Future<SignedIn> login({
    required String username,
    required String password,
    String? device,
  }) {
    return _request(
      http.RestEndpoints.login,
      body: protocol.LoginRequest(
        username: username,
        password: password,
        device: device,
      ).toJson(),
      decode: (json) {
        final response = protocol.LoginResponse.fromJson(json);
        return SignedIn(
          memberToken: response.memberToken,
          member: toDomainMember(response.member),
          account: toDomainAccount(response.account),
          device: response.device,
        );
      },
    );
  }

  @override
  Future<void> logout() => _send(http.RestEndpoints.logout);

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _send(
      http.RestEndpoints.changePassword,
      body: protocol.ChangePasswordRequest(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ).toJson(),
    );
  }

  @override
  Future<SiteCapabilities> getSite() {
    return _request(
      http.RestEndpoints.getSite,
      decode: (json) {
        final response = protocol.GetSiteResponse.fromJson(json);
        return SiteCapabilities(
          registrationOpen: response.registrationOpen,
          githubLogin: response.githubLogin,
        );
      },
    );
  }

  // 成功时没有回复体（204）的接口。
  Future<void> _send(
    http.RestEndpoint endpoint, {
    Map<String, Object?> body = const {},
  }) async {
    final token = endpoint.auth == http.HttpAuth.member
        ? await _memberTokenReader()
        : null;
    await _transport.execute(endpoint, body: body, token: token);
  }

  @override
  Future<Member> updateMe({String? name, String? email}) {
    return _request(
      http.RestEndpoints.updateMe,
      body: protocol.UpdateMeRequest(name: name, email: email).toJson(),
      decode: (json) =>
          toDomainMember(protocol.UpdateMeResponse.fromJson(json).member),
    );
  }

  @override
  Future<List<RoomListing>> listRooms() {
    return _request(
      http.RestEndpoints.listRooms,
      decode: (json) =>
          protocol.ListRoomsResponse.fromJson(json).items
              .map(toDomainRoomListing)
              .toList(growable: false),
    );
  }

  @override
  Future<RoomListing> getRoom(String ref) {
    return _request(
      http.RestEndpoints.getRoom,
      pathParameters: {'ref': ref},
      decode: (json) =>
          toDomainRoomListing(protocol.RoomListing.fromJson(json)),
    );
  }

  @override
  Future<String> createRoom({
    required String name,
    required String description,
    String? password,
  }) {
    return _request(
      http.RestEndpoints.createRoom,
      body: protocol.CreateRoomRequest(
        name: name,
        description: description,
        password: password,
      ).toJson(),
      decode: (json) => protocol.CreateRoomResponse.fromJson(json).id,
    );
  }

  @override
  Future<String> createTicket(String id, {String? password}) {
    return _request(
      http.RestEndpoints.createTicket,
      pathParameters: {'id': id},
      body: protocol.CreateTicketRequest(password: password).toJson(),
      decode: (json) => protocol.CreateTicketResponse.fromJson(json).ticket,
    );
  }

  Future<T> _request<T>(
    http.RestEndpoint endpoint, {
    required T Function(Map<String, Object?> json) decode,
    Map<String, String> pathParameters = const {},
    Map<String, Object?> body = const {},
  }) async {
    final token = endpoint.auth == http.HttpAuth.member
        ? await _memberTokenReader()
        : null;
    final response = await _transport.execute(
      endpoint,
      pathParameters: pathParameters,
      body: body,
      token: token,
    );
    try {
      if (response is! Map<String, Object?>) {
        throw const FormatException('Response must be an object');
      }
      return decode(response);
    } on FormatException {
      AppLog.debug(
        _logSource,
        'response not understood',
        type: endpoint.name,
        code: LocalErrorCodes.protocolMismatch,
      );
      throw ApiException.protocolMismatch(endpoint.successStatus);
    }
  }
}
