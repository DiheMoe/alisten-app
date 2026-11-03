import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class UpdateStore {
  DateTime? readLastAutoCheck();

  Future<void> writeLastAutoCheck(DateTime at);

  /// `X.Y.Z` 形式。
  String? readSkippedVersion();

  Future<void> writeSkippedVersion(String version);
}

final updateStoreProvider = Provider<UpdateStore>((ref) {
  throw UnimplementedError('updateStore 未注入');
});
