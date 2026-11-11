import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 只经 `AdminSession.run` 调用，由会话保证 token 只发给它所属的服务器。
abstract interface class AdminApi {
  Future<List<RoomListing>> listRooms(String token);

  Future<String> getBrandName();

  Future<String> updateBrandName(String token, String brandName);

  Future<bool> getRegistrationOpen();

  Future<void> openRegistration(String token);

  Future<void> closeRegistration(String token);

  Future<AdminAccountView> findAccount(String token, String username);

  /// 服务端只在这次回复中返回新密码，账号在所有设备上随即退出登录。
  Future<String> resetAccountPassword(String token, String username);

  Future<String> createRoom(String token, RoomDraft draft);

  Future<void> updateRoom(String token, String roomId, RoomPatch patch);

  Future<void> deleteRoom(String token, String roomId);

  Future<ApiKeyStatus> getApiKeyStatus(String token, String roomId);

  /// 服务端只在这次回复中返回新 Key。
  Future<String> resetApiKey(String token, String roomId);

  Future<SourceAccountStatus> getSourceAccount(
    String token,
    LoginSource source,
  );

  Future<QrLoginTicket> startQrLogin(
    String token,
    LoginSource source, {
    QqLoginType qqType = QqLoginType.qq,
  });

  /// [qqType] 须与 [startQrLogin] 时相同。
  Future<QrLoginCheck> checkQrLogin(
    String token,
    LoginSource source,
    String key, {
    QqLoginType qqType = QqLoginType.qq,
  });

  Future<YoutubeCookieStatus> getYoutubeCookie(String token);

  Future<void> setYoutubeCookie(String token, String cookies);

  Future<void> deleteYoutubeCookie(String token);

  Future<GithubAppStatus> getGithubApp(String token);

  /// 两项都必填：服务端没有读取 Client Secret 的接口，修改时要一起重新填写。
  Future<void> setGithubApp(
    String token, {
    required String clientId,
    required String clientSecret,
  });

  Future<void> deleteGithubApp(String token);
}

final adminApiProvider = Provider<AdminApi>((ref) {
  throw UnimplementedError('adminApi 未注入');
});
