import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class MediaLinkOpener {
  /// 用系统浏览器或对应的应用打开；打不开时返回 false。
  Future<bool> open(String link);
}

final mediaLinkOpenerProvider = Provider<MediaLinkOpener>((ref) {
  throw UnimplementedError('mediaLinkOpener 未注入');
});
