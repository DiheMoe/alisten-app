import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('covers on hosts known to serve HTTPS are upgraded to HTTPS, '
      'other covers are kept', () {
    String cover(String url) {
      return toDomainTrackMeta(
        protocol.TrackMeta(
          album: '',
          artist: '',
          coverUrl: url,
          durationMs: 1,
          pageUrl: '',
          title: '',
        ),
      ).coverUrl;
    }

    expect(
      cover('http://p1.music.126.net/a/1.jpg'),
      'https://p1.music.126.net/a/1.jpg',
    );
    expect(
      cover('http://p4.music.126.net/a/1.jpg?param=300y300'),
      'https://p4.music.126.net/a/1.jpg?param=300y300',
    );
    expect(
      cover('http://y.gtimg.cn/music/1.jpg'),
      'https://y.gtimg.cn/music/1.jpg',
    );
    expect(
      cover('http://i0.hdslb.com/bfs/1.jpg'),
      'https://i0.hdslb.com/bfs/1.jpg',
    );
    expect(
      cover('http://p5.music.126.net/1.jpg'),
      'http://p5.music.126.net/1.jpg',
    );
    expect(cover('http://evilhdslb.com/1.jpg'), 'http://evilhdslb.com/1.jpg');
    expect(cover('http://example.com/1.jpg'), 'http://example.com/1.jpg');
    expect(cover('https://example.com/1.jpg'), 'https://example.com/1.jpg');
    expect(cover(''), '');
  });
}
