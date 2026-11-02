import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../room_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRoomTransportFactory factory;
  late ProviderContainer container;
  late RoomController controller;

  setUp(() async {
    factory = FakeRoomTransportFactory();
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(
          FakeAlistenApi()
            ..rooms = [roomListing(), roomListing(id: 'room-two', slug: 'two')],
        ),
        credentialStoreProvider.overrideWithValue(
          FakeCredentialStore()
            ..tickets['room-id'] = 'saved-ticket'
            ..tickets['room-two'] = 'ticket-two',
        ),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(),
      ],
    );
    controller = container.read(roomControllerProvider.notifier);
    await controller.openRoom('listen');
  });

  tearDown(() {
    container.dispose();
  });

  test('a refused mutation returns the server code and message', () async {
    factory.last
      ..emitHello()
      ..requestError = const RoomRequestException(
        code: 'RATE_LIMITED',
        message: '太快了',
        outcome: RoomRequestOutcome.failed,
      );

    final result = await controller.mutate((c) => c.likeEntry('e'));

    expect(
      result,
      isA<MutationFailed<int>>()
          .having((r) => r.code, 'code', 'RATE_LIMITED')
          .having((r) => r.message, 'message', '太快了'),
    );
    await pumpEventQueue();
    expect(factory.last.syncCalls, 0);
  });

  test('an unknown mutation syncs once and is never resent', () async {
    factory.last
      ..emitHello()
      ..requestError = const RoomRequestException(
        message: '连接断开',
        outcome: RoomRequestOutcome.unknown,
      );
    await pumpEventQueue();

    final result = await controller.mutate((c) => c.likeEntry('e'));
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<int>>());
    expect(factory.last.syncCalls, 1);
    expect(factory.last.requests, hasLength(1));
  });

  test('a result from a room that was left is not reported to it', () async {
    final oldTransport = factory.last..emitHello();
    await pumpEventQueue();
    oldTransport.requestCompleter = Completer();

    final pending = controller.mutate((c) => c.likeEntry('e'));
    await controller.openRoom('two');
    factory.last.emitHello();
    await pumpEventQueue();
    final result = await pending;
    await pumpEventQueue();

    expect(result, isA<MutationNotSent<int>>());
    expect(oldTransport.requests, hasLength(1));
    expect(oldTransport.syncCalls, 0);
    expect(factory.last.syncCalls, 0);
  });

  test('a mutation without a connection is reported as not sent', () async {
    final result = await controller.mutate((c) => c.likeEntry('e'));

    expect(result, isA<MutationNotSent<int>>());
    expect(factory.last.requests, isEmpty);
  });

  test('a mutation that breaks unexpectedly after its room was left is not '
      'reported to the room now shown', () async {
    final oldTransport = factory.last..emitHello();
    await pumpEventQueue();
    final breaks = Completer<void>();

    final pending = controller.mutate<int>((c) async {
      await breaks.future;
      throw StateError('broken');
    });
    await controller.openRoom('two');
    factory.last.emitHello();
    await pumpEventQueue();
    breaks.complete();
    final result = await pending;
    await pumpEventQueue();

    expect(result, isA<MutationNotSent<int>>());
    expect(oldTransport.syncCalls, 0);
    expect(factory.last.syncCalls, 0);
  });

  test('a sync that breaks unexpectedly after a mutation is logged by its '
      'type alone, is not retried, and leaves later syncs possible', () async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    final transport = factory.last..emitHello();
    await pumpEventQueue();
    // 非 `RoomRequestException` 的错误，例如协议漂移时把回复映射成快照抛出的
    // 错误。
    transport
      ..requestError = StateError('https://example.com/media?sig=secret')
      ..syncError = StateError('https://example.com/media?sig=secret');

    final result = await controller.mutate((c) => c.likeEntry('e'));
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<int>>());
    expect(transport.syncCalls, 1);
    final errors = [
      for (final record in records)
        if (record.$2 >= 1000) record,
    ];
    expect(errors.map((record) => record.$1), ['alisten.room', 'alisten.room']);
    expect(errors.where((record) => record.$3.contains('secret')), isEmpty);

    transport
      ..requestError = null
      ..syncError = null;
    await controller.mutate<int>((c) => throw StateError('broken'));
    await pumpEventQueue();
    expect(transport.syncCalls, 2);
  });
}
