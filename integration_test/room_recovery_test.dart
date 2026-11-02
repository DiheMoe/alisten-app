import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/core/realtime/websocket_room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'backend_config.dart';

Future<void> main() async {
  final config = backendConfig();
  await _runProtocolRecoveries(config);
  stdout.writeln('Protocol recovery checks passed');
}

Future<void> _runProtocolRecoveries(AppConfig config) async {
  final dio = Dio();
  late String memberToken;
  late String roomId;
  late String ticket;
  final api = RestAlistenApi(
    ApiTransport(dio, config),
    () async => memberToken,
  );
  try {
    memberToken = (await api.createMember()).memberToken;
    roomId = await api.createRoom(
      name: 'Recovery ${DateTime.now().millisecondsSinceEpoch}',
      description: 'Temporary recovery verification room',
    );
    ticket = await api.createTicket(roomId);

    final invalid = WebSocketRoomTransport(
      baseUri: Uri.parse(config.baseUrl),
      roomId: roomId,
      ticket: 'invalid-ticket',
    );
    _check(
      await _stoppedCode(invalid) == 4401,
      'Invalid ticket must stop at 4401',
    );

    final missing = WebSocketRoomTransport(
      baseUri: Uri.parse(config.baseUrl),
      roomId: '00000000-0000-0000-0000-000000000000',
      ticket: ticket,
    );
    _check(
      await _stoppedCode(missing) == 4404,
      'Missing room must stop at 4404',
    );

    final baseUri = Uri.parse(config.baseUrl);
    final outdated = WebSocketChannel.connect(
      baseUri.replace(
        scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
      ),
    );
    await outdated.ready;
    outdated.sink.add(
      jsonEncode({
        'kind': 'request',
        'type': 'hello',
        'id': 'outdated',
        'data': {
          'roomId': roomId,
          'ticket': ticket,
          'protocolVersion': 'outdated-version',
        },
      }),
    );
    await outdated.stream.drain<void>();
    _check(outdated.closeCode == 4426, 'Outdated protocol must stop at 4426');

    final first = WebSocketRoomTransport(
      baseUri: Uri.parse(config.baseUrl),
      roomId: roomId,
      ticket: ticket,
    );
    await _hello(first);
    await first.stop();

    final recovered = WebSocketRoomTransport(
      baseUri: Uri.parse(config.baseUrl),
      roomId: roomId,
      ticket: ticket,
    );
    final snapshot = await _hello(recovered);
    _check(snapshot.room.id == roomId, 'Recovered snapshot has the wrong room');
    final synced = await RoomCommands(recovered).sync();
    _check(synced.term == snapshot.term, 'Recovered snapshot term changed');
    await recovered.stop();
  } finally {
    dio.close(force: true);
  }
}

Future<int> _stoppedCode(RoomTransport transport) async {
  final stopped = transport.events
      .firstWhere((event) => event is RoomStopped)
      .timeout(const Duration(seconds: 15));
  await transport.start();
  final event = await stopped;
  return (event as RoomStopped).code;
}

Future<RoomSnapshot> _hello(RoomTransport transport) async {
  final hello = transport.events
      .firstWhere((event) => event is RoomHelloReceived)
      .timeout(const Duration(seconds: 15));
  await transport.start();
  final event = await hello;
  return (event as RoomHelloReceived).hello.room;
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
