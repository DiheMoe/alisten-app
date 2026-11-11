enum GithubIntent { login, bind, verify }

/// 服务端写死的落地地址 `moe.dihe.alisten:/auth/github` 的 scheme，与原生包名
/// 相同；Lab 包也用这个 scheme。
const githubCallbackScheme = 'moe.dihe.alisten';

const _callbackPath = '/auth/github';

// FinishGithubLoginRequest.code 的上限。
const _maxCodeLength = 128;

sealed class GithubCallback {
  const GithubCallback();
}

final class GithubGranted extends GithubCallback {
  const GithubGranted(this.code);

  final String code;
}

enum GithubRefusal { denied, expired, failed, missing }

final class GithubRefused extends GithubCallback {
  const GithubRefused(this.reason);

  final GithubRefusal reason;
}

GithubCallback readGithubCallback(Uri uri) {
  if (uri.scheme != githubCallbackScheme || uri.path != _callbackPath) {
    return const GithubRefused(GithubRefusal.missing);
  }
  final Map<String, String> fields;
  try {
    fields = Uri.splitQueryString(uri.fragment);
  } on ArgumentError {
    return const GithubRefused(GithubRefusal.missing);
  } on FormatException {
    return const GithubRefused(GithubRefusal.missing);
  }
  final code = fields['code'];
  if (code != null && code.isNotEmpty && code.length <= _maxCodeLength) {
    return GithubGranted(code);
  }
  return switch (fields['error']) {
    'denied' => const GithubRefused(GithubRefusal.denied),
    'expired' => const GithubRefused(GithubRefusal.expired),
    null => const GithubRefused(GithubRefusal.missing),
    _ => const GithubRefused(GithubRefusal.failed),
  };
}
