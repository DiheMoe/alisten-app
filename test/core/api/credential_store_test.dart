import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/lobby/lobby_test_doubles.dart';

final class _LockedStorage extends FlutterSecureStorage {
  const _LockedStorage();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(
      code: '-25308',
      message: 'User interaction is not allowed.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CredentialStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    store = const SecureCredentialStore(
      FlutterSecureStorage(),
      serverId: 'aaaa',
    );
  });

  test('member token can be written read and deleted', () async {
    expect(await store.readMemberToken(), isNull);

    await store.writeMemberToken('member-token');
    expect(await store.readMemberToken(), 'member-token');

    await store.deleteMemberToken();
    expect(await store.readMemberToken(), isNull);
  });

  test(
    'room tickets are isolated and deleted only for their own room',
    () async {
      await store.writeTicket('room-one', 'ticket-one');
      await store.writeTicket('room/two', 'ticket-two');

      expect(await store.readTicket('room-one'), 'ticket-one');
      expect(await store.readTicket('room/two'), 'ticket-two');

      await store.deleteTicket('room-one');
      expect(await store.readTicket('room-one'), isNull);
      expect(await store.readTicket('room/two'), 'ticket-two');
    },
  );

  test('credentials are namespaced by server and invisible to the other '
      'servers', () async {
    const other = SecureCredentialStore(
      FlutterSecureStorage(),
      serverId: 'bbbb',
    );

    await store.writeMemberToken('m');
    await store.writeTicket('room/two', 't');

    expect(await const FlutterSecureStorage().readAll(), {
      'member_token@aaaa': 'm',
      'room_ticket@aaaa.room%2Ftwo': 't',
    });
    expect(await other.readMemberToken(), isNull);
    expect(await other.readTicket('room/two'), isNull);

    await other.writeMemberToken('other-m');
    await other.writeTicket('room/two', 'other-t');
    expect(await store.readMemberToken(), 'm');
    expect(await store.readTicket('room/two'), 't');
  });

  test('clearing removes only the credentials of its own server', () async {
    const other = SecureCredentialStore(
      FlutterSecureStorage(),
      serverId: 'bbbb',
    );
    await store.writeMemberToken('m');
    await store.writeTicket('room-one', 't1');
    await store.writeTicket('room/two', 't2');
    await other.writeMemberToken('other-m');
    await other.writeTicket('room-one', 'other-t');

    await store.clear();

    expect(await const FlutterSecureStorage().readAll(), {
      'member_token@bbbb': 'other-m',
      'room_ticket@bbbb.room-one': 'other-t',
    });
  });

  test('a server no longer listed gets no more credentials written, but '
      'they can still be deleted', () async {
    var listed = true;
    final kept = SecureCredentialStore(
      const FlutterSecureStorage(),
      serverId: 'aaaa',
      serverListed: () => listed,
    );
    await kept.writeMemberToken('m');
    await kept.writeTicket('room-one', 't');

    listed = false;
    await kept.writeMemberToken('late');
    await kept.writeTicket('room/two', 'late');

    expect(await const FlutterSecureStorage().readAll(), {
      'member_token@aaaa': 'm',
      'room_ticket@aaaa.room-one': 't',
    });
    await kept.clear();
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('the server of a key is read back from its name', () {
    expect(SecureCredentialStore.serverIdOf('member_token@aaaa'), 'aaaa');
    expect(
      SecureCredentialStore.serverIdOf(
        SecureCredentialStore.ticketKey('aaaa', 'room/two'),
      ),
      'aaaa',
    );
    expect(SecureCredentialStore.serverIdOf('member_token'), isNull);
    expect(SecureCredentialStore.serverIdOf('room_ticket.room-1'), isNull);
    expect(SecureCredentialStore.serverIdOf('unrelated'), isNull);
  });

  test('deleting while the keychain is locked only logs the failure', () async {
    final logs = <String>[];
    AppLog.onRecord = (name, level, message) {
      if (name == 'alisten.credentials') logs.add(message);
    };
    addTearDown(() => AppLog.onRecord = null);
    const locked = SecureCredentialStore(_LockedStorage(), serverId: 'aaaa');
    await store.writeMemberToken('m');
    await store.writeTicket('room-one', 't');

    await locked.deleteMemberToken();
    await locked.deleteTicket('room-one');
    await locked.clear();

    expect(logs, isNotEmpty);
    expect(logs, everyElement(contains('code=KEYCHAIN')));
    expect(logs, everyElement(isNot(contains('aaaa'))));
  });

  test(
    'deleting the tickets keeps the member token and the login devices',
    () async {
      await store.writeMemberToken('member-token');
      await store.writeTicket('room-one', 'ticket-one');
      await store.writeTicket('room/two', 'ticket-two');
      await store.writeLoginDevice('mao', 'device-one');

      await store.deleteTickets();

      expect(await store.readTicket('room-one'), isNull);
      expect(await store.readTicket('room/two'), isNull);
      expect(await store.readMemberToken(), 'member-token');
      expect(await store.readLoginDevice('mao'), 'device-one');
    },
  );

  test('login devices are kept per server and per username', () async {
    const other = SecureCredentialStore(
      FlutterSecureStorage(),
      serverId: 'bbbb',
    );
    await store.writeLoginDevice('mao', 'device-a');
    await store.writeLoginDevice('gou', 'device-b');
    await other.writeLoginDevice('mao', 'device-c');

    expect(await store.readLoginDevice('mao'), 'device-a');
    expect(await store.readLoginDevice('gou'), 'device-b');
    expect(await other.readLoginDevice('mao'), 'device-c');
  });

  test('clearing a server also forgets its login devices', () async {
    const other = SecureCredentialStore(
      FlutterSecureStorage(),
      serverId: 'bbbb',
    );
    await store.writeLoginDevice('mao', 'device-a');
    await other.writeLoginDevice('mao', 'device-c');

    await store.clear();

    expect(await store.readLoginDevice('mao'), isNull);
    expect(await other.readLoginDevice('mao'), 'device-c');
  });

  test('the server of a login device key is read back from its name', () {
    expect(
      SecureCredentialStore.serverIdOf(
        SecureCredentialStore.loginDeviceKey('aaaa', 'mao'),
      ),
      'aaaa',
    );
    expect(SecureCredentialStore.serverIdOf('login_device@'), isNull);
  });

  group('readMemberTokenOrNull', () {
    test('returns the token as it is read', () async {
      final fake = FakeCredentialStore()..memberToken = 'member-token';

      expect(await fake.readMemberTokenOrNull(), 'member-token');
    });

    test('a token that cannot be read is null, not an error', () async {
      final fake = FakeCredentialStore()
        ..memberToken = 'member-token'
        ..readMemberTokenError = PlatformException(code: '-25308');

      expect(await fake.readMemberTokenOrNull(), isNull);
    });
  });
}
