import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 带敏感标记复制，系统剪贴板预览不显示内容；平台不支持该标记时按普通文本
/// 复制。失败时抛出。
abstract interface class SensitiveClipboard {
  Future<void> copy(String text);
}

final sensitiveClipboardProvider = Provider<SensitiveClipboard>((ref) {
  throw UnimplementedError('sensitiveClipboard 未注入');
});
