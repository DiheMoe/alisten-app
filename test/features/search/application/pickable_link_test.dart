import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/search/application/pickable_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persistent rooms accept any valid HTTP or HTTPS link', () {
    expect(
      pickableLink(' HTTPS://Example.COM/path ', RoomKind.persistent),
      'https://example.com/path',
    );
    expect(pickableLink('not-a-link', RoomKind.persistent), isNull);
    expect(pickableLink('https://example.com', null), isNull);
  });

  test('ephemeral rooms allow only exact Bilibili hosts and subdomains', () {
    for (final link in [
      'https://b23.tv/video',
      'https://bilibili.com/video',
      'https://www.bilibili.com/video',
    ]) {
      expect(pickableLink(link, RoomKind.ephemeral), isNotNull);
    }
    for (final link in [
      'https://notbilibili.com/video',
      'https://bilibili.com.example/video',
      'https://example.com/video',
    ]) {
      expect(pickableLink(link, RoomKind.ephemeral), isNull);
    }
  });
}
