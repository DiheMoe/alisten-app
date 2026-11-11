import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class GithubAuthorizer {
  /// 在系统浏览器里打开 [url]，返回跳回 App 的地址。用户关掉浏览器、没有跳回
  /// App 时返回 null；打不开浏览器等其他失败抛 [GithubAuthorizerFailed]。
  Future<Uri?> authorize(Uri url);
}

final class GithubAuthorizerFailed implements Exception {
  const GithubAuthorizerFailed();
}

final githubAuthorizerProvider = Provider<GithubAuthorizer>((ref) {
  throw UnimplementedError('githubAuthorizer 未注入');
});
