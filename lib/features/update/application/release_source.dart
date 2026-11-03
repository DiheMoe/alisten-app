import 'package:alisten/domain/release/app_release.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ReleaseSource {
  /// 最新的正式版，不含草稿和预发布版。取不到时抛出 [ReleaseUnavailable]。
  Future<AppRelease> latest();
}

final class ReleaseUnavailable implements Exception {
  const ReleaseUnavailable();
}

final releaseSourceProvider = Provider<ReleaseSource>((ref) {
  throw UnimplementedError('releaseSource 未注入');
});
