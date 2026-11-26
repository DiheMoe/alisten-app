import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/github.dart';
import 'package:alisten/features/account/application/github_authorizer.dart';

const _logSource = 'account';

/// Linux 和 Windows 没有能把回调交回 App 的浏览器会话：授权页在系统浏览器里
/// 打开，沿用那里已经登录的 GitHub；跳回 App 的地址由系统按登记的协议交给 App，
/// 再从 [_links] 里取回。浏览器被关掉时 App 无从得知，等到 [_timeout] 为止。
final class BrowserGithubAuthorizer implements GithubAuthorizer {
  const BrowserGithubAuthorizer({
    required this._links,
    required this._register,
    required this._open,
    this._timeout = const Duration(minutes: 5),
  });

  final Stream<Uri> _links;
  final Future<void> Function() _register;

  /// 返回 false 表示没有能打开网址的程序。
  final Future<bool> Function(Uri url) _open;
  final Duration _timeout;

  @override
  Future<Uri?> authorize(Uri url) async {
    final callback = Completer<Uri?>();
    final links = _links.listen((uri) {
      if (uri.scheme == githubCallbackScheme && !callback.isCompleted) {
        callback.complete(uri);
      }
    });
    try {
      final bool opened;
      try {
        await _register();
        opened = await _open(url);
      } on Object catch (error) {
        AppLog.debug(
          _logSource,
          'github authorization failed',
          type: '${error.runtimeType}',
        );
        throw const GithubAuthorizerFailed();
      }
      if (!opened) throw const GithubAuthorizerFailed();
      return await callback.future.timeout(_timeout, onTimeout: () => null);
    } finally {
      unawaited(links.cancel());
    }
  }
}
