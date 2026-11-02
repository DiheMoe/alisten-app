import 'package:alisten/features/playback/data/reminder_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeGateway gateway;
  late ReminderNotifier notifier;
  late String? openedServer;
  late String? openedRoom;
  late String serverId;

  void open(String? server, String room) {
    openedServer = server;
    openedRoom = room;
  }

  setUp(() {
    gateway = _FakeGateway();
    openedServer = null;
    openedRoom = null;
    serverId = 'f475765b53c3272e';
    notifier = ReminderNotifier(gateway, serverId: () => serverId);
  });

  test(
    'system reminder is sent only when invisible enabled and permitted',
    () async {
      expect(
        await notifier.notify(
          appVisible: true,
          enabled: true,
          systemEnabled: true,
          permissionGranted: true,
          roomId: 'room',
          entryId: 'entry',
          title: '歌曲',
        ),
        isFalse,
      );
      expect(
        await notifier.notify(
          appVisible: false,
          enabled: true,
          systemEnabled: false,
          permissionGranted: true,
          roomId: 'room',
          entryId: 'entry',
          title: '歌曲',
        ),
        isFalse,
      );
      expect(
        await notifier.notify(
          appVisible: false,
          enabled: true,
          systemEnabled: true,
          permissionGranted: false,
          roomId: 'room',
          entryId: 'entry',
          title: '歌曲',
        ),
        isFalse,
      );

      expect(
        await notifier.notify(
          appVisible: false,
          enabled: true,
          systemEnabled: true,
          permissionGranted: true,
          roomId: 'room',
          entryId: 'entry',
          title: '歌曲',
        ),
        isTrue,
      );
      expect(gateway.payloads, ['f475765b53c3272e:room:entry']);
    },
  );

  test('the reminder carries the server that is current when it is '
      'sent', () async {
    Future<void> notify(String roomId, String entryId) async {
      await notifier.notify(
        appVisible: false,
        enabled: true,
        systemEnabled: true,
        permissionGranted: true,
        roomId: roomId,
        entryId: entryId,
        title: '歌曲',
      );
    }

    await notify('room-1', 'entry-1');
    serverId = 'fcd7a878032db68b';
    await notify('room-1', 'entry-1');

    expect(gateway.payloads, [
      'f475765b53c3272e:room-1:entry-1',
      'fcd7a878032db68b:room-1:entry-1',
    ]);
  });

  test('notification taps open only the corresponding room on its '
      'server', () async {
    await notifier.initialize(onOpenRoom: open);
    gateway.onPayload?.call('f475765b53c3272e:room-1:entry-1');

    expect(openedServer, 'f475765b53c3272e');
    expect(openedRoom, 'room-1');
  });

  test('a reminder sent before servers were kept names no server', () async {
    await notifier.initialize(onOpenRoom: open);
    gateway.onPayload?.call('01a15778-1911-7a28-8b2e-e08c2a25f388:entry-1');

    expect(openedServer, isNull);
    expect(openedRoom, '01a15778-1911-7a28-8b2e-e08c2a25f388');
  });

  test('a payload is read as the old format unless it starts with a server '
      'id and has two more parts', () async {
    final opened = <(String?, String)>[];
    await notifier.initialize(
      onOpenRoom: (server, room) => opened.add((server, room)),
    );

    for (final payload in [
      // 只有两段：第一段即使像服务器 id 也是房间。
      'f475765b53c3272e:entry-1',
      // 第一段不是 16 位小写十六进制。
      'F475765B53C3272E:room-1:entry-1',
      'f475765b53c3272:room-1:entry-1',
      'f475765b53c3272e0:room-1:entry-1',
      'room-1:entry-1:more',
    ]) {
      gateway.onPayload?.call(payload);
    }

    expect(opened, [
      (null, 'f475765b53c3272e'),
      (null, 'F475765B53C3272E'),
      (null, 'f475765b53c3272'),
      (null, 'f475765b53c3272e0'),
      (null, 'room-1'),
    ]);
  });

  test('a payload without a room opens nothing', () async {
    final opened = <(String?, String)>[];
    await notifier.initialize(
      onOpenRoom: (server, room) => opened.add((server, room)),
    );

    for (final payload in [
      '',
      'entry-only',
      ':entry-1',
      'f475765b53c3272e::entry-1',
    ]) {
      gateway.onPayload?.call(payload);
    }

    expect(opened, isEmpty);
  });

  test('startup checks the actual notification permission', () async {
    expect(await notifier.checkPermission(), isTrue);
  });

  test('a notification that launches the app opens its room', () async {
    gateway.launchPayload = 'f475765b53c3272e:cold-room:entry';
    await notifier.initialize(onOpenRoom: open);

    expect(openedServer, 'f475765b53c3272e');
    expect(openedRoom, 'cold-room');
  });
}

final class _FakeGateway implements NotificationGateway {
  final List<String> payloads = [];
  void Function(String payload)? onPayload;
  String? launchPayload;

  @override
  Future<void> initialize(void Function(String payload) onPayload) async {
    this.onPayload = onPayload;
    final payload = launchPayload;
    if (payload != null) onPayload(payload);
  }

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    payloads.add(payload);
  }
}
