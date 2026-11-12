import 'package:alisten/domain/room/room_route.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _segments(String path) => Uri.parse(path).pathSegments;

String? _route(String path, {Set<String> sections = linkRoomSections}) =>
    roomRoute(_segments(path), sections: sections);

void main() {
  test('a room reference is a UUID in either case, or an alias of lowercase '
      'letters, digits and hyphens up to 32 long', () {
    expect(isRoomRef('01A15778-1911-7A28-8B2E-E08C2A25F388'), isTrue);
    expect(isRoomRef('01a15778-1911-7a28-8b2e-e08c2a25f388'), isTrue);
    expect(isRoomRef('listen'), isTrue);
    expect(isRoomRef('night-owls-2'), isTrue);
    expect(isRoomRef('a' * 32), isTrue);
    expect(isRoomRef('FlutterDev'), isFalse);
    expect(isRoomRef('a' * 33), isFalse);
    expect(isRoomRef(''), isFalse);
    for (final ref in ['bad_slug', 'bad/slug', 'bad slug', '..']) {
      expect(isRoomRef(ref), isFalse, reason: ref);
    }
  });

  test('a room, a section of it, or a NetEase or QQ Music playlist in it '
      'has a route', () {
    expect(_route('/r/room-id'), '/r/room-id');
    expect(_route('/r/alias/queue'), '/r/alias/queue');
    expect(_route('/r/alias/chat'), '/r/alias/chat');
    expect(_route('/r/alias/search'), '/r/alias/search');
    expect(
      _route('/r/alias/playlists/netease/123'),
      '/r/alias/playlists/netease/123',
    );
    expect(_route('/r/alias/playlists/qq/123'), '/r/alias/playlists/qq/123');
    const uuid = '123e4567-e89b-42d3-a456-426614174000';
    expect(_route('/r/$uuid'), '/r/$uuid');
  });

  test('only the sections given are routes', () {
    expect(_route('/r/alias/lyrics'), isNull);
    expect(_route('/r/alias/lyrics', sections: {'lyrics'}), '/r/alias/lyrics');
    expect(_route('/r/alias/queue', sections: const {}), isNull);
  });

  test('anything else has no route', () {
    for (final path in [
      '/',
      '/admin',
      '/r',
      '/room/listen',
      '/x/listen',
      '/r/listen/foo',
      '/r/listen/queue/more',
      '/r/listen/',
      '/r/alias/playlists/bilibili/123',
      '/r/alias/playlists/qq/12a',
      '/r/alias/playlists/netease/12a',
      '/r/alias/playlists/netease',
      '/r/FlutterDev',
      '/r/bad_slug',
      '/r/bad%2Fslug',
      '/r/bad%20slug',
    ]) {
      expect(_route(path), isNull, reason: path);
    }
  });
}
