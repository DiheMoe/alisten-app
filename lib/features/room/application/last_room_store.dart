import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class LastRoomStore {
  String? read();

  Future<void> write(String room);

  Future<void> clear();
}

final lastRoomStoreProvider = Provider<LastRoomStore>((ref) {
  throw UnimplementedError('lastRoomStore 未注入');
});
