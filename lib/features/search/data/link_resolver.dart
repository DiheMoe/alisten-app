import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/protocol_runtime.dart'
    show isValidLink, normalizeLink;
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/application/pickable_link.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:dio/dio.dart';

/// 展开一个短链接的总时限，包含所有跳转。
const shortLinkTimeout = Duration(seconds: 3);

const _maxRedirects = 3;

// 服务端不展开这些音乐平台的短链接。
const _shortLinkHosts = {
  '163cn.tv': LinkPlatform.netease,
  'c6.y.qq.com': LinkPlatform.qq,
};

// 有效链接最长 2048 字节；这里的链接只含 ASCII 字符，字符数即字节数。
const _maxLinkLength = 2048;

const _logSource = 'share';

final _linkStart = RegExp('https?://', caseSensitive: false);
final _songName = RegExp('《([^《》]+)》');
final _digits = RegExp(r'^[0-9]+$');

// songmid 含字母；纯数字是另一种歌曲 id。
final _songMid = RegExp(r'^(?=[0-9]*[A-Za-z])[0-9A-Za-z]+$');

// 除空白和非 ASCII 字符（例如紧跟在链接后的中文标点）之外，这些字符也会结束
// 链接。
const _linkEnds = '<>"\'`{}|\\^';

// 链接末尾的这些字符视为句子标点，不属于链接。
const _trailing = '.,;:!?\'"';

// 网易云和 QQ 音乐的页面链接要转成对应的歌，否则服务端会把它们当作网页下载；
// B 站和其他链接原样交给服务端处理。
//
// 只请求网易云和 QQ 音乐的短链接，一律走 https，每次只取一跳，不自动跟随跳转，
// 也不读取响应体。
final class DioLinkResolver implements LinkResolver {
  DioLinkResolver(this._dio);

  final Dio _dio;

  @override
  ResolvedShare? recognize(String text) {
    final found = _firstLink(text);
    if (found == null) return null;
    final (:link, :at) = found;
    final title = _title(text.substring(0, at));
    final uri = Uri.tryParse(link);
    final short = _shortLinkHosts[uri?.host];
    if (short != null) {
      return ResolvedShare(
        link: link,
        platform: short,
        title: title,
        unfollowed: true,
      );
    }
    final page = uri == null ? null : _musicPage(uri);
    if (page != null) {
      return ResolvedShare(
        link: link,
        platform: page.platform,
        track: page.track,
        title: title,
        problem: page.problem,
      );
    }
    return ResolvedShare(
      link: link,
      platform: uri != null && isBilibiliHost(uri.host)
          ? LinkPlatform.bilibili
          : LinkPlatform.web,
      track: Track(source: TrackSource.link, id: link),
      title: title,
    );
  }

  @override
  Future<ResolvedShare?> resolve(String text, {Future<void>? cancel}) async {
    final share = recognize(text);
    if (share == null || !share.unfollowed) return share;
    final target = await _follow(Uri.parse(share.link), cancel);
    final page = target == null ? null : _musicPage(target);
    return ResolvedShare(
      link: share.link,
      platform: page?.platform ?? share.platform,
      track: page?.track,
      title: share.title,
      problem: page == null ? LinkProblem.unrecognized : page.problem,
    );
  }

  Future<Uri?> _follow(Uri link, Future<void>? cancel) async {
    final stop = CancelToken();
    unawaited(cancel?.then((_) => stop.cancel()));
    try {
      return await _redirects(link, stop).timeout(shortLinkTimeout);
    } on TimeoutException {
      stop.cancel();
      AppLog.debug(_logSource, 'short link timed out');
    } on DioException catch (error) {
      AppLog.debug(_logSource, 'short link failed', outcome: error.type);
    } on FormatException {
      AppLog.debug(_logSource, 'short link redirected to an invalid link');
    }
    return null;
  }

  Future<Uri?> _redirects(Uri link, CancelToken stop) async {
    var current = link;
    for (var attempt = 1; attempt <= _maxRedirects; attempt++) {
      // Release 构建禁止明文请求，这两个平台也都提供 https。
      final response = await _headers(current.replace(scheme: 'https'), stop);
      final status = response.statusCode ?? 0;
      final location = response.headers['location']?.firstOrNull;
      if (status < 300 || status >= 400 || location == null) {
        AppLog.debug(
          _logSource,
          'short link did not redirect',
          code: '$status',
          attempt: attempt,
        );
        return null;
      }
      final next = current.resolve(location);
      if (!_shortLinkHosts.containsKey(next.host)) return next;
      current = next;
    }
    AppLog.debug(_logSource, 'short link redirected too often');
    return null;
  }

  // 收到状态码和响应头后立即取消请求，否则 dio 会读完流式响应体，没有跳转时就是
  // 一整个网页。
  Future<Response<ResponseBody>> _headers(Uri uri, CancelToken stop) async {
    final request = CancelToken();
    unawaited(stop.whenCancel.then((_) => request.cancel()));
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: request,
      options: Options(
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    request.cancel();
    return response;
  }
}

// 依次尝试每个可能的起点。同一段连续的链接字符只扫描一次，长文本也只需线性
// 时间；从某个起点算起超过 [_maxLinkLength] 的不算链接，也不截短后使用。
({String link, int at})? _firstLink(String text) {
  var runEnd = 0;
  for (final match in _linkStart.allMatches(text)) {
    if (match.start >= runEnd) {
      runEnd = match.end;
      while (runEnd < text.length && _inLink(text.codeUnitAt(runEnd))) {
        runEnd++;
      }
    }
    if (runEnd - match.start > _maxLinkLength) continue;
    final link = _trimEnd(text.substring(match.start, runEnd));
    if (isValidLink(link)) {
      return (link: normalizeLink(link), at: match.start);
    }
  }
  return null;
}

bool _inLink(int unit) {
  return unit > 0x20 && unit < 0x7f && !_linkEnds.codeUnits.contains(unit);
}

// 去掉句末标点，以及链接中没有对应左括号的右括号。
String _trimEnd(String link) {
  // 每种括号只在首次用到时计数；裁剪只会去掉右括号，同步扣减其计数即可。
  final counts = <String, int>{};
  var end = link.length;
  int count(String char) =>
      counts[char] ??= _count(link.substring(0, end), char);
  while (end > 0) {
    final last = link[end - 1];
    if (_trailing.contains(last)) {
      end--;
      continue;
    }
    final opening = switch (last) {
      ')' => '(',
      ']' => '[',
      _ => null,
    };
    if (opening == null || count(opening) >= count(last)) break;
    counts[last] = counts[last]! - 1;
    end--;
  }
  return link.substring(0, end);
}

int _count(String text, String char) => char.allMatches(text).length;

// 音乐应用分享的文本在链接前用《》写出歌名。
String? _title(String beforeLink) {
  final name = _songName.firstMatch(beforeLink)?.group(1)?.trim();
  return name == null || name.isEmpty ? null : name;
}

typedef _MusicPage = ({
  LinkPlatform platform,
  Track? track,
  LinkProblem? problem,
});

_MusicPage? _musicPage(Uri uri) {
  final host = uri.host;
  if (host == 'music.163.com' || host.endsWith('.music.163.com')) {
    return _page(
      LinkPlatform.netease,
      TrackSource.netease,
      _neteaseSong(uri),
      uri,
    );
  }
  if (host == 'y.qq.com' || host.endsWith('.y.qq.com')) {
    return _page(LinkPlatform.qq, TrackSource.qq, _qqSong(uri), uri);
  }
  return null;
}

_MusicPage _page(
  LinkPlatform platform,
  TrackSource source,
  String? id,
  Uri uri,
) {
  if (id != null) {
    return (
      platform: platform,
      track: Track(source: source, id: id),
      problem: null,
    );
  }
  // 路径或片段中带 song 的是缺少 id 或 id 格式错误的歌曲页，其余是歌单、专辑
  // 或歌手页。
  final aboutSong = '${uri.path}#${uri.fragment}'.toLowerCase().contains(
    'song',
  );
  return (
    platform: platform,
    track: null,
    problem: aboutSong ? LinkProblem.unrecognized : LinkProblem.notSong,
  );
}

// 识别 `/song?id=1`、`/m/song?id=1`、`/#/song?id=1` 和 `/song/1` 这几种页面。
String? _neteaseSong(Uri uri) {
  // 网页版播放器把页面路径放在片段里。
  final fragment = uri.fragment.isEmpty ? null : Uri.tryParse(uri.fragment);
  for (final page in [uri, ?fragment]) {
    final segments = _segments(page);
    if (segments.lastOrNull == 'song') {
      final id = _query(page, 'id');
      if (id != null && _digits.hasMatch(id)) return id;
    }
    final at = segments.indexOf('song');
    if (at >= 0 && at + 1 < segments.length) {
      final id = segments[at + 1];
      if (_digits.hasMatch(id)) return id;
    }
  }
  return null;
}

// 识别 `/n/ryqq/songDetail/<mid>`、`/n/yqq/song/<mid>.html` 和带 `songmid`
// 查询参数的页面。服务端用 songmid 标识 QQ 音乐的歌。
String? _qqSong(Uri uri) {
  final segments = _segments(uri);
  final candidates = [
    _query(uri, 'songmid'),
    for (final (index, segment) in segments.indexed)
      if ((segment.toLowerCase() == 'songdetail' || segment == 'song') &&
          index + 1 < segments.length)
        segments[index + 1].replaceFirst(RegExp(r'\.html$'), ''),
  ];
  for (final mid in candidates) {
    if (mid != null && _songMid.hasMatch(mid)) return mid;
  }
  return null;
}

List<String> _segments(Uri uri) {
  return [
    for (final segment in uri.path.split('/'))
      if (segment.isNotEmpty) segment,
  ];
}

// 不解码查询参数：分享链接的查询串格式有误时也不会出错，要找的 id 本身也无需
// 解码。
String? _query(Uri uri, String key) {
  for (final pair in uri.query.split('&')) {
    final equals = pair.indexOf('=');
    if (equals > 0 && pair.substring(0, equals) == key) {
      return pair.substring(equals + 1);
    }
  }
  return null;
}
