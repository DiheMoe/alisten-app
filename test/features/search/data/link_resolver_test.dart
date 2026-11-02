import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/search/data/link_resolver.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../share_test_doubles.dart';

void main() {
  late FakeUrlHttpAdapter http;
  late DioLinkResolver resolver;

  setUp(() {
    http = FakeUrlHttpAdapter();
    resolver = DioLinkResolver(Dio()..httpClientAdapter = http);
  });

  void expectSong(
    ResolvedShare? share,
    TrackSource source,
    String id, {
    LinkPlatform? platform,
  }) {
    expect(share, isNotNull);
    expect(share!.problem, isNull);
    expect(share.track?.source, source);
    expect(share.track?.id, id);
    if (platform != null) expect(share.platform, platform);
  }

  test('a NetEase song shared by its app is the NetEase song, named by the '
      'text, without a request', () async {
    final share = await resolver.resolve(neteaseShareText);

    expectSong(share, TrackSource.netease, '186016');
    expect(share!.platform, LinkPlatform.netease);
    expect(share.title, '晴天');
    expect(share.link, 'https://music.163.com/song?id=186016&userid=1');
    expect(http.requests, isEmpty);
  });

  test('NetEase song pages in their other forms', () async {
    for (final link in [
      'https://music.163.com/#/song?id=186016',
      'https://y.music.163.com/m/song?id=186016&uct2=x',
      'https://m.music.163.com/m/song?id=186016',
      'https://music.163.com/song/186016/?userid=1',
    ]) {
      expectSong(await resolver.resolve(link), TrackSource.netease, '186016');
    }
  });

  test('a NetEase page that is not one song cannot be picked', () async {
    for (final link in [
      'https://music.163.com/#/playlist?id=123',
      'https://music.163.com/album?id=18905',
      'https://y.music.163.com/m/artist?id=6452',
    ]) {
      final share = await resolver.resolve(link);
      expect(share?.platform, LinkPlatform.netease, reason: link);
      expect(share?.track, isNull, reason: link);
      expect(share?.problem, LinkProblem.notSong, reason: link);
    }
    final song = await resolver.resolve('https://music.163.com/#/song?id=');
    expect(song?.problem, LinkProblem.unrecognized);
  });

  test('a NetEase short link is followed one redirect at a time and stays '
      'the link shown', () async {
    http.answers['https://163cn.tv/abcd'] = () =>
        redirectTo('https://y.music.163.com/m/song?id=186016&userid=1');

    final share = await resolver.resolve(
      '分享周杰伦的单曲《晴天》: https://163cn.tv/abcd (来自@网易云音乐)',
    );

    expectSong(share, TrackSource.netease, '186016');
    expect(share!.platform, LinkPlatform.netease);
    expect(share.title, '晴天');
    expect(share.link, 'https://163cn.tv/abcd');
    expect(http.requests, hasLength(1));
    expect(http.requests.single.followRedirects, isFalse);
  });

  test('a short link is followed through relative redirects, three at '
      'most', () async {
    http.answers['https://163cn.tv/one'] = () => redirectTo('/two');
    http.answers['https://163cn.tv/two'] = () =>
        redirectTo('https://music.163.com/#/song?id=5');
    expectSong(
      await resolver.resolve('https://163cn.tv/one'),
      TrackSource.netease,
      '5',
    );

    http.requests.clear();
    for (var hop = 0; hop < 4; hop++) {
      http.answers['https://163cn.tv/loop$hop'] = () =>
          redirectTo('https://163cn.tv/loop${hop + 1}');
    }
    http.answers['https://163cn.tv/loop4'] = () =>
        redirectTo('https://music.163.com/#/song?id=5');
    final share = await resolver.resolve('https://163cn.tv/loop0');
    expect(share?.track, isNull);
    expect(share?.problem, LinkProblem.unrecognized);
    expect(http.requests, hasLength(3));
  });

  test('a short link whose redirect never comes is given up after 3 seconds '
      'and is not picked as a link', () {
    fakeAsync((async) {
      http.hang = true;
      ResolvedShare? share;
      var done = false;
      unawaited(
        resolver.resolve('https://163cn.tv/slow').then((value) {
          share = value;
          done = true;
        }),
      );

      async.elapse(const Duration(milliseconds: 2999));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
      expect(share?.platform, LinkPlatform.netease);
      expect(share?.track, isNull);
      expect(share?.problem, LinkProblem.unrecognized);
    });
  });

  test('a short link that does not redirect, or leads elsewhere, cannot be '
      'picked', () async {
    final missing = await resolver.resolve('https://163cn.tv/gone');
    expect(missing?.track, isNull);
    expect(missing?.problem, LinkProblem.unrecognized);

    http.answers['https://163cn.tv/ad'] = () =>
        redirectTo('https://example.com/landing');
    final elsewhere = await resolver.resolve('https://163cn.tv/ad');
    expect(elsewhere?.track, isNull);
    expect(elsewhere?.problem, LinkProblem.unrecognized);
  });

  test('a QQ Music song is the QQ Music song by its songmid', () async {
    for (final link in [
      'https://y.qq.com/n/ryqq/songDetail/0039MnYb0qxYhV',
      'https://y.qq.com/n/yqq/song/0039MnYb0qxYhV.html',
      'https://i.y.qq.com/v8/playsong.html?songmid=0039MnYb0qxYhV&ADTAG=x',
    ]) {
      expectSong(
        await resolver.resolve(link),
        TrackSource.qq,
        '0039MnYb0qxYhV',
        platform: LinkPlatform.qq,
      );
    }
    expect(http.requests, isEmpty);
  });

  test('a QQ Music short link shared by its app is followed', () async {
    http.answers['https://c6.y.qq.com/base/fcgi-bin/u?__=AbCd'] = () =>
        redirectTo(
          'https://i.y.qq.com/v8/playsong.html?songmid=0039MnYb0qxYhV'
          '&songtype=0',
        );

    final share = await resolver.resolve(
      '分享周杰伦的单曲《晴天》https://c6.y.qq.com/base/fcgi-bin/u?__=AbCd '
      '@QQ音乐',
    );

    expectSong(share, TrackSource.qq, '0039MnYb0qxYhV');
    expect(share!.platform, LinkPlatform.qq);
    expect(share.title, '晴天');
    expect(share.link, 'https://c6.y.qq.com/base/fcgi-bin/u?__=AbCd');
  });

  test('a QQ Music page that is not one song cannot be picked', () async {
    final playlist = await resolver.resolve(
      'https://y.qq.com/n/ryqq/playlist/7256912512',
    );
    expect(playlist?.problem, LinkProblem.notSong);
    expect(playlist?.track, isNull);

    final numbered = await resolver.resolve(
      'https://i.y.qq.com/v8/playsong.html?songid=102065756',
    );
    expect(numbered?.problem, LinkProblem.unrecognized);
  });

  test('a Bilibili link, short or not, is picked as the link itself, which '
      'the room follows', () async {
    final short = await resolver.resolve('【晴天 钢琴版】 https://b23.tv/xyz');
    expect(short?.platform, LinkPlatform.bilibili);
    expect(short?.track?.source, TrackSource.link);
    expect(short?.track?.id, 'https://b23.tv/xyz');
    expect(short?.problem, isNull);

    final video = await resolver.resolve(
      'https://www.bilibili.com/video/BV1xx411c7mD',
    );
    expect(video?.platform, LinkPlatform.bilibili);
    expect(video?.track?.id, 'https://www.bilibili.com/video/BV1xx411c7mD');
    expect(http.requests, isEmpty);
  });

  test('another link is picked as the link, normalized', () async {
    final share = await resolver.resolve('听这个 HTTPS://Example.COM/a.mp3');

    expect(share?.platform, LinkPlatform.web);
    expect(share?.track?.source, TrackSource.link);
    expect(share?.track?.id, 'https://example.com/a.mp3');
    expect(share?.link, 'https://example.com/a.mp3');
  });

  test('punctuation and brackets right after a link are not part of it', () {
    final cases = {
      'https://music.163.com/song?id=7（来自网易云音乐）': '7',
      '看这个：https://music.163.com/song?id=8。': '8',
      '(https://music.163.com/song?id=9)': '9',
      'https://music.163.com/song?id=10, 好听': '10',
    };
    for (final MapEntry(key: text, value: id) in cases.entries) {
      expect(
        resolver.resolve(text).then((share) => share?.track?.id),
        completion(id),
        reason: text,
      );
    }
  });

  test('without the network, a link is told at once and a short link is '
      'left to follow', () {
    expectSong(
      resolver.recognize(neteaseShareText),
      TrackSource.netease,
      '186016',
    );
    final short = resolver.recognize('《晴天》 https://163cn.tv/abcd');
    expect(short?.unfollowed, isTrue);
    expect(short?.platform, LinkPlatform.netease);
    expect(short?.title, '晴天');
    expect(short?.track, isNull);
    expect(short?.problem, isNull);
    expect(resolver.recognize('https://b23.tv/xyz')?.unfollowed, isFalse);
    expect(resolver.recognize('没有链接'), isNull);
    expect(http.requests, isEmpty);
  });

  test('following a short link is given up, request and all, once '
      'cancelled', () async {
    http.hang = true;
    final cancel = Completer<void>();
    final resolving = resolver.resolve(
      'https://163cn.tv/slow',
      cancel: cancel.future,
    );
    await pumpEventQueue();
    expect(http.requests, hasLength(1));

    cancel.complete();
    final share = await resolving;
    expect(share?.track, isNull);
    expect(share?.problem, LinkProblem.unrecognized);
    expect(http.cancelled, 1);
  });

  test('a short link, and each of its redirects, is requested over https '
      'even when given as http', () async {
    http.answers['https://163cn.tv/plain'] = () =>
        redirectTo('http://163cn.tv/next');
    http.answers['https://163cn.tv/next'] = () =>
        redirectTo('http://music.163.com/song?id=5');

    final share = await resolver.resolve('http://163cn.tv/plain');

    expectSong(share, TrackSource.netease, '5');
    expect(share!.link, 'http://163cn.tv/plain');
    expect(http.requests.map((request) => request.uri.toString()), [
      'https://163cn.tv/plain',
      'https://163cn.tv/next',
    ]);
  });

  test(
    'the body of a short link is not downloaded, redirect or page',
    () async {
      final opened = <String>[];
      final closed = <String>[];
      ResponseBody unread(String name, int status, [String? location]) {
        final body = StreamController<Uint8List>(
          onListen: () => opened.add(name),
          onCancel: () => closed.add(name),
        );
        addTearDown(body.close);
        return ResponseBody(
          body.stream,
          status,
          headers: {
            if (location != null) 'location': [location],
          },
        );
      }

      http.answers['https://163cn.tv/moved'] = () =>
          unread('redirect', 302, 'https://music.163.com/song?id=5');
      http.answers['https://163cn.tv/page'] = () => unread('page', 200);

      expectSong(
        await resolver.resolve('https://163cn.tv/moved'),
        TrackSource.netease,
        '5',
      );
      final page = await resolver.resolve('https://163cn.tv/page');
      expect(page?.problem, LinkProblem.unrecognized);
      // 结束请求稍后才生效。
      await pumpEventQueue();
      expect(closed, opened);
      expect(closed, ['redirect', 'page']);
    },
  );

  test('a QQ Music songmid has letters: a number alone is not one', () async {
    for (final link in [
      'https://y.qq.com/n/ryqq/songDetail/102065756',
      'https://i.y.qq.com/v8/playsong.html?songmid=12345',
    ]) {
      final share = await resolver.resolve(link);
      expect(share?.track, isNull, reason: link);
      expect(share?.problem, LinkProblem.unrecognized, reason: link);
    }
  });

  test('a link longer than 2048 characters is not taken, even when what is '
      'left once cut would be one', () async {
    const song = 'https://music.163.com/song?id=1';
    final within = await resolver.resolve('$song${')' * 2000}');
    final beyond = await resolver.resolve('$song${')' * 3000}');
    final longPath = await resolver.resolve('$song&x=${'a' * 3000}');

    expect(within?.track?.id, '1');
    expect(beyond, isNull);
    expect(longPath, isNull);
  });

  test('a very long text is read at once', () async {
    final watch = Stopwatch()..start();

    final brackets = await resolver.resolve(
      'https://music.163.com/song?id=1${')' * 100000}',
    );
    final repeated = await resolver.resolve('http://@' * 12500);
    final longLink = await resolver.resolve(
      'https://example.com/${'a' * 100000}',
    );
    final plain = await resolver.resolve('x' * 100000);

    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(brackets, isNull, reason: 'cut short, it is not the link');
    expect(repeated, isNull);
    expect(longLink, isNull, reason: 'a link is 2048 bytes at most');
    expect(plain, isNull);
  });

  test('a text without an http(s) link shares nothing', () async {
    expect(await resolver.resolve('分享周杰伦的单曲《晴天》'), isNull);
    expect(await resolver.resolve('ftp://example.com/a'), isNull);
    expect(await resolver.resolve(''), isNull);
  });
}
