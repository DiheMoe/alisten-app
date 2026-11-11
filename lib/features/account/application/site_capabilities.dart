import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 不缓存：设置页每次打开都重新读取，管理员随时可能开关注册。
final siteCapabilitiesProvider = FutureProvider.autoDispose<SiteCapabilities>((
  ref,
) async {
  try {
    return await ref.watch(alistenApiProvider).getSite();
  } on Object catch (error) {
    AppLog.debug(
      'account',
      'site capabilities not read',
      code: error is ApiException ? error.code : null,
    );
    return SiteCapabilities.unknown;
  }
});
