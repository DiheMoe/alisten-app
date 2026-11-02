import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/clipboard_link_controller.dart';
import 'package:alisten/features/search/application/invite_link.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/search/data/link_resolver.dart';
import 'package:alisten/features/server/index.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';
import '../share_test_doubles.dart';

const _party = 'https://new.example.org/r/party';

void main() {
  late FakeClipboardSource clipboard;
  late FakeServerProbe probe;
  late FakeRoomTransportFactory rooms;
  late ProviderContainer container;

  Future<void> enterListen(RoomKind kind) async {
    clipboard = FakeClipboardSource();
    probe = FakeServerProbe()
      ..siteResults['https://new.example.org'] = const ProbeSucceeded(
        origin: 'https://new.example.org',
        brandName: '新站',
      );
    rooms = FakeRoomTransportFactory();
    final credentials = FakeCredentialStores();
    credentials(testEnvironment.defaultServerId).tickets['room-id'] = 't';
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: credentials,
      api: FakeAlistenApi()..rooms = [roomListing()],
      rooms: rooms,
      extra: [
        serverProbeProvider.overrideWithValue(probe),
        clipboardSourceProvider.overrideWithValue(clipboard),
        linkResolverProvider.overrideWithValue(
          DioLinkResolver(Dio()..httpClientAdapter = FakeUrlHttpAdapter()),
        ),
      ],
    );
    await container.read(roomControllerProvider.notifier).openRoom('listen');
    rooms.last.emitHello(
      testRoomSnapshot().copyWith(
        term: 1,
        seq: 1,
        room: RoomInfo(
          id: 'room-id',
          name: 'listen',
          description: '',
          kind: kind,
        ),
      ),
    );
    await pumpEventQueue();
  }

  Future<ProviderSubscription<ResolvedShare?>> check() async {
    final page = container.listen(clipboardLinkControllerProvider, (_, _) {});
    await container.read(clipboardLinkControllerProvider.notifier).check();
    return page;
  }

  InviteOffer? offer() => container.read(inviteOfferControllerProvider);

  test('a room on a server not saved is offered as an invite once, not as '
      'a song', () async {
    await enterListen(RoomKind.persistent);
    clipboard.copy(_party);

    var page = await check();

    final first = offer();
    expect(
      first?.target,
      isA<InviteToNew>()
          .having((t) => t.server.brandName, 'brandName', '新站')
          .having((t) => t.route, 'route', '/r/party'),
    );
    expect(page.read(), isNull);
    expect(clipboard.reads, 1);

    page.close();
    await container.pump();
    page = await check();
    expect(offer()?.id, first!.id, reason: 'the clipboard is the same');
    expect(clipboard.reads, 1);
    expect(page.read(), isNull);

    container.read(inviteOfferControllerProvider.notifier).dismiss(first.id);
    clipboard.copy(_party);
    page.close();
    await container.pump();
    page = await check();
    expect(clipboard.reads, 2);
    expect(offer(), isNull, reason: 'the same text was offered');
    expect(page.read(), isNull);
    expect(probe.siteProbed, hasLength(2));
  });

  test('the link of the room already entered is offered as nothing', () async {
    await enterListen(RoomKind.persistent);
    clipboard.copy('https://livehouse.dihe.moe/r/listen');

    final page = await check();

    expect(offer(), isNull);
    expect(page.read(), isNull);
    expect(probe.siteProbed, isEmpty);
  });

  test('another room of the current server is held for the user to enter, '
      'not entered', () async {
    await enterListen(RoomKind.ephemeral);
    clipboard.copy('https://livehouse.dihe.moe/r/other');

    var page = await check();

    expect(offer(), isNull);
    expect(page.read()?.link, 'https://livehouse.dihe.moe/r/other');
    expect(page.read()?.problem, LinkProblem.roomLink);
    expect(page.read()?.otherRoom, '/r/other');
    expect(probe.siteProbed, isEmpty);

    page.close();
    await container.pump();
    page = await check();
    expect(page.read(), isNull, reason: 'held once');
  });

  test('a room link on a website that is not Alisten is a song link like '
      'any other', () async {
    await enterListen(RoomKind.persistent);
    probe.siteResults['https://www.reddit.com'] = const ProbeFailed(
      ProbeFailure.notAlisten,
    );
    clipboard.copy('https://www.reddit.com/r/flutterdev');

    final page = await check();

    expect(offer(), isNull);
    expect(page.read()?.link, 'https://www.reddit.com/r/flutterdev');
  });
}
