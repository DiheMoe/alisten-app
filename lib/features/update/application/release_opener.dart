import 'package:alisten/domain/release/app_release.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ReleaseOpener {
  /// 交给浏览器打开安装包或发布页；打不开时返回 false。
  Future<bool> open(AppRelease release);
}

final releaseOpenerProvider = Provider<ReleaseOpener>((ref) {
  throw UnimplementedError('releaseOpener 未注入');
});
