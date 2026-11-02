import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final class QrImageUnavailable implements Exception {
  const QrImageUnavailable();
}

/// 失败时一律抛 [QrImageUnavailable]。
abstract interface class QrImageLoader {
  Future<Uint8List> load(String qrImage);
}

final qrImageLoaderProvider = Provider<QrImageLoader>((ref) {
  throw UnimplementedError('qrImageLoader 未注入');
});
