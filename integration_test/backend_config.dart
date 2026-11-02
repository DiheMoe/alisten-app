import 'dart:io';

import 'package:alisten/core/api/app_config.dart';

/// 后端地址不设默认值：测试会创建房间和成员，漏传 `ALISTEN_API_URL` 时不能
/// 落到公用部署上。
AppConfig backendConfig() {
  const apiUrl = String.fromEnvironment('ALISTEN_API_URL');
  if (apiUrl.isEmpty) {
    stderr.writeln(
      'ALISTEN_API_URL is required, for example: '
      'dart run -DALISTEN_API_URL=http://127.0.0.1:9876 '
      'integration_test/<script>.dart',
    );
    exit(2);
  }
  return AppConfig(baseUrl: apiUrl, isRelease: false, allowCleartext: true);
}
