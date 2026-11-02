import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/pick_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a pick that breaks unexpectedly once sent has an unknown result: it '
      'is logged without the link, the room is synchronised, and nothing is '
      'sent again', () async {
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
      ..requestError = StateError('https://music.163.com/song?id=track-id');
    await pumpEventQueue();
    container.listen(pickControllerProvider, (_, _) {});

    final result = await container
        .read(pickControllerProvider.notifier)
        .pick(testTrack);
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<QueueEntry>>());
    expect(
      container.read(pickControllerProvider).of(testTrack),
      PickStatus.unknown,
    );
    expect(factory.last.requests, hasLength(1));
    expect(factory.last.syncCalls, 1);
    final errors = [
      for (final record in records)
        if (record.$2 >= 1000) record,
    ];
    expect(errors, hasLength(1));
    expect(errors.single.$3, isNot(contains('http')));
    expect(errors.single.$3, isNot(contains('track-id')));
  });
}
