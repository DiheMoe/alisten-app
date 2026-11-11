import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/features/account/application/github_authorizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

const _logSource = 'account';

/// 回调由系统浏览器会话直接交回，App 接触不到 GitHub 的密码。返回的地址里有
/// 一次性兑换码，不写日志。不传 `options`：保持 `preferEphemeral` 为 false，
/// 沿用浏览器里已经登录的 GitHub。
final class WebAuthGithubAuthorizer implements GithubAuthorizer {
  const WebAuthGithubAuthorizer({
    this._authenticate = FlutterWebAuth2.authenticate,
  });

  final Future<String> Function({
    required String url,
    required String callbackUrlScheme,
    FlutterWebAuth2Options options,
  })
  _authenticate;

  @override
  Future<Uri?> authorize(Uri url) async {
    final String callback;
    try {
      callback = await _authenticate(
        url: '$url',
        callbackUrlScheme: githubCallbackScheme,
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') return null;
      AppLog.debug(_logSource, 'github authorization failed', code: error.code);
      throw const GithubAuthorizerFailed();
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'github authorization failed',
        type: '${error.runtimeType}',
      );
      throw const GithubAuthorizerFailed();
    }
    return Uri.tryParse(callback);
  }
}
