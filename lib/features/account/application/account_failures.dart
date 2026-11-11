import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/identity/index.dart';

/// 不等待、不抛出：结果未知或本机状态过时之后，按服务端重新读一次身份。
void refreshIdentity(IdentityController identity) {
  unawaited(
    identity.restore().then<void>(
      (_) {},
      onError: (Object _) {
        AppLog.debug('account', 'profile not refreshed');
      },
    ),
  );
}
