import 'package:alisten/domain/server/invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

InviteLink? _parse(String link) => parseInviteLink(link, allowCleartext: false);

void main() {
  test('a room link names the server, the room and the route', () {
    final invite = _parse('https://example.com:8443/r/listen')!;

    expect(invite.origin, 'https://example.com:8443');
    expect(invite.authority, 'example.com:8443');
    expect(invite.roomRef, 'listen');
    expect(invite.route, '/r/listen');
  });

  test('the host is lowercased; the query and fragment are dropped', () {
    final invite = _parse(
      'https://Example.com/r/01a15778-1911-7a28-8b2e-e08c2a25f388/queue?x=1#y',
    )!;

    expect(invite.origin, 'https://example.com');
    expect(invite.authority, 'example.com');
    expect(invite.roomRef, '01a15778-1911-7a28-8b2e-e08c2a25f388');
    expect(invite.route, '/r/01a15778-1911-7a28-8b2e-e08c2a25f388/queue');
  });

  test('a NetEase playlist in a room is a room link', () {
    expect(
      _parse('https://example.com/r/listen/playlists/netease/123')?.route,
      '/r/listen/playlists/netease/123',
    );
  });

  test('the default port is left out', () {
    final invite = _parse('https://example.com:443/r/listen')!;

    expect(invite.origin, 'https://example.com');
    expect(invite.authority, 'example.com');
  });

  test('a link shaped like a room on any website is a room link: only the '
      'server can tell', () {
    final invite = _parse('https://www.reddit.com/r/flutterdev')!;

    expect(invite.origin, 'https://www.reddit.com');
    expect(invite.route, '/r/flutterdev');
  });

  test('links that cannot be a room are not', () {
    for (final link in [
      'https://www.reddit.com/r/FlutterDev',
      'https://example.com/r/listen/foo',
      'https://example.com/room/listen',
      'https://example.com/',
      'https://user@example.com/r/listen',
      'ftp://example.com/r/listen',
      'example.com/r/listen',
      'not a link',
    ]) {
      expect(_parse(link), isNull, reason: link);
    }
  });

  test('a shared playlist link names its kind and route but no room', () {
    final invite = _parse('https://example.com:8443/s/AbCdEfGhIjKlMnOpQrStUv')!;

    expect(invite.kind, SiteLinkKind.sharedPlaylist);
    expect(invite.route, '/s/AbCdEfGhIjKlMnOpQrStUv');
    expect(invite.roomRef, isNull);
    expect(invite.authority, 'example.com:8443');
    expect(_parse('https://example.com/s/short'), isNull);
    expect(_parse('https://example.com/s/AbCdEfGhIjKlMnOpQrStUv/x'), isNull);
  });

  test('a room link is still a room', () {
    final invite = _parse('https://example.com/r/listen')!;

    expect(invite.kind, SiteLinkKind.room);
    expect(invite.roomRef, 'listen');
  });

  test('a shared playlist link with a trailing slash is not one, as on the '
      'website', () {
    expect(_parse('https://example.com/s/AbCdEfGhIjKlMnOpQrStUv/'), isNull);
  });

  test('an escaped letter in a share id is that letter, but an escaped slash '
      'or percent sign is no share id', () {
    final escaped = _parse('https://example.com/s/%41bCdEfGhIjKlMnOpQrStUv')!;

    expect(escaped.kind, SiteLinkKind.sharedPlaylist);
    expect(escaped.route, '/s/AbCdEfGhIjKlMnOpQrStUv');
    expect(_parse('https://example.com/s/AbCdEfGhIjK%2FMnOpQrStUv'), isNull);
    expect(_parse('https://example.com/s/AbCdEfGhIjKlMnOpQrStU%25'), isNull);
  });

  test('a shared playlist link on any website keeps that website: only the '
      'server can tell', () {
    final invite = _parse('https://www.reddit.com/s/AbCdEfGhIjKlMnOpQrStUv')!;

    expect(invite.origin, 'https://www.reddit.com');
    expect(invite.authority, 'www.reddit.com');
    expect(invite.kind, SiteLinkKind.sharedPlaylist);
  });

  test('HTTP is a room link only where cleartext servers are allowed', () {
    expect(_parse('http://example.com/r/listen'), isNull);
    expect(
      parseInviteLink(
        'http://10.0.2.2:9876/r/listen',
        allowCleartext: true,
      )?.origin,
      'http://10.0.2.2:9876',
    );
  });
}
