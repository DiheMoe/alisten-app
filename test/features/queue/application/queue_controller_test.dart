import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (change, send)
      in <(String, Future<MutationResult<Object?>> Function(QueueController))>[
        ('a like', (queue) => queue.like('entry-id')),
        ('a removal', (queue) => queue.remove('entry-id')),
        (
          'a play mode change',
          (queue) => queue.setPlayMode(RoomPlayMode.random),
        ),
      ]) {
    test('$change that breaks unexpectedly once sent has an unknown result: '
        'it is logged, the room is synchronised, nothing is sent again and '
        'the queue is free for the next change', () async {
      final records = <(String, int, String)>[];
      AppLog.onRecord = (name, level, message) =>
          records.add((name, level, message));
      addTearDown(() => AppLog.onRecord = null);
      final factory = FakeRoomTransportFactory();
      final container = ProviderContainer(
        overrides: [
          alistenApiProvider.overrideWithValue(
            FakeAlistenApi()..rooms = [roomListing()],
          ),
          credentialStoreProvider.overrideWithValue(
            FakeCredentialStore()..tickets['room-id'] = 'saved-ticket',
          ),
          roomTransportFactoryProvider.overrideWithValue(factory.call),
          ...roomDeviceOverrides(),
        ],
      );
      addTearDown(container.dispose);
      await container.read(roomControllerProvider.notifier).openRoom('listen');
      factory.last
        ..emitHello()
        ..requestError = StateError('ticket saved-ticket');
      await pumpEventQueue();

      final result = await send(
        container.read(queueControllerProvider.notifier),
      );
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<Object?>>());
      expect(container.read(queueControllerProvider), const QueueBusy());
      expect(factory.last.requests, hasLength(1));
      expect(factory.last.syncCalls, 1);
      final errors = [
        for (final record in records)
          if (record.$2 >= 1000) record,
      ];
      expect(errors, hasLength(1));
      expect(errors.single.$3, isNot(contains('saved-ticket')));
    });
  }
}
