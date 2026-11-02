import 'dart:async';
import 'dart:io';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/core/realtime/websocket_room_transport.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:dio/dio.dart';

import 'backend_config.dart';

Future<void> main() async {
  final config = backendConfig();
  final dio = Dio();
  RoomTransport? transport;
  try {
    final api = RestAlistenApi(
      ApiTransport(dio, config),
      () async => (await _identity).memberToken,
    );
    _identity = api.createMember();
    await _identity;
    final roomId = await api.createRoom(
      name: 'Mobile smoke ${DateTime.now().millisecondsSinceEpoch}',
      description: 'Temporary protocol verification room',
    );
    final ticket = await api.createTicket(roomId);
    transport = WebSocketRoomTransport(
      baseUri: Uri.parse(config.baseUrl),
      roomId: roomId,
      ticket: ticket,
    );
    final hello = Completer<RoomHello>();
    final subscription = transport.events.listen((event) {
      if (event is RoomHelloReceived && !hello.isCompleted) {
        hello.complete(event.hello);
      }
      if (event is RoomStopped && !hello.isCompleted) {
        hello.completeError(
          StateError('Room connection stopped: ${event.code}'),
        );
      }
    });
    await transport.start();
    final snapshot = (await hello.future.timeout(const Duration(seconds: 15)))
        .room;
    if (snapshot.room.id != roomId) {
      throw StateError('Hello snapshot belongs to a different room');
    }
    final synced = await RoomCommands(transport).sync();
    if (synced.room.id != roomId || synced.term != snapshot.term) {
      throw StateError('Room sync did not calibrate the current room');
    }
    await subscription.cancel();
    await transport.stop();
    transport = null;
    stdout.writeln('Backend REST and WebSocket smoke passed');
  } finally {
    await transport?.stop();
    dio.close(force: true);
  }
}

late final Future<({Member member, String memberToken})> _identity;
