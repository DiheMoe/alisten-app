import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/release/app_release.dart';
import 'package:alisten/features/update/application/release_source.dart';
import 'package:dio/dio.dart';

const _logSource = 'update';

const _repository = ['DiheMoe', 'alisten-app'];

/// 只接受指向本仓库发布页和发布附件的 https 地址：这些地址会交给浏览器打开，
/// 别处的地址可能下载到不是本应用的安装包。
final class GitHubReleaseSource implements ReleaseSource {
  /// [_dio] 不得带有凭据或 Alisten 服务器地址。
  GitHubReleaseSource(this._dio, {this.timeout = const Duration(seconds: 10)});

  static final _latestRelease = Uri.https(
    'api.github.com',
    '/repos/${_repository.join('/')}/releases/latest',
  );

  // GitHub 限制发布说明不超过 125000 个字符，全是汉字时约 375 KB。
  static const maxBodyBytes = 1 << 20;

  final Dio _dio;
  final Duration timeout;

  @override
  Future<AppRelease> latest() async {
    final cancel = CancelToken();
    final ({int status, Uint8List? body}) response;
    try {
      response = await _fetch(cancel).timeout(
        timeout,
        onTimeout: () {
          cancel.cancel();
          throw TimeoutException(null, timeout);
        },
      );
    } on TimeoutException {
      _unavailable('latest release timed out');
    } on DioException catch (error) {
      AppLog.debug(
        _logSource,
        'latest release not fetched',
        outcome: error.type,
      );
      throw const ReleaseUnavailable();
    } on Object catch (error) {
      AppLog.debug(
        _logSource,
        'latest release not fetched',
        type: '${error.runtimeType}',
      );
      throw const ReleaseUnavailable();
    }
    if (response.status != 200) {
      AppLog.debug(
        _logSource,
        'latest release not fetched',
        code: '${response.status}',
      );
      throw const ReleaseUnavailable();
    }
    final body = response.body;
    if (body == null) _unavailable('latest release too large');
    return _release(body);
  }

  // 状态不是 200 时不读响应体；响应体超过上限时 body 为 null。
  Future<({int status, Uint8List? body})> _fetch(CancelToken cancel) async {
    final response = await _dio.getUri<ResponseBody>(
      _latestRelease,
      cancelToken: cancel,
      options: Options(
        headers: const {
          'Accept': 'application/vnd.github.text+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    final status = response.statusCode ?? 0;
    final stream = response.data?.stream;
    final bytes = BytesBuilder(copy: false);
    // 取消订阅 Dio 包装的响应流不会关闭连接，只有 cancelToken 会。
    if (status != 200 || stream == null) {
      cancel.cancel();
      return (status: status, body: bytes.takeBytes());
    }
    await for (final chunk in stream) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) {
        cancel.cancel();
        return (status: status, body: null);
      }
    }
    return (status: status, body: bytes.takeBytes());
  }
}

AppRelease _release(Uint8List body) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(body));
  } on FormatException {
    _unavailable('latest release not decoded');
  }
  if (json is! Map<String, Object?>) _unavailable('latest release malformed');
  final tag = json['tag_name'];
  final notes = json['body_text'] ?? '';
  final assets = json['assets'] ?? const <Object?>[];
  if (tag is! String || notes is! String || assets is! List<Object?>) {
    _unavailable('latest release malformed');
  }
  final page = _url(json['html_url'], ['releases', 'tag', tag]);
  if (page == null) _unavailable('release page not accepted');
  return AppRelease(
    tag: tag,
    notes: notes,
    page: page,
    assets: [for (final asset in assets) ?_asset(asset, tag)],
  );
}

ReleaseAsset? _asset(Object? json, String tag) {
  if (json is! Map<String, Object?>) return null;
  final name = json['name'];
  final url = _url(json['browser_download_url'], [
    'releases',
    'download',
    tag,
    null,
  ]);
  if (name is! String || url == null) return null;
  return ReleaseAsset(name: name, downloadUrl: url);
}

final _unsafeInSegment = RegExp(r'[/\\%]');

// 路径必须恰好是本仓库之下的 [path]，null 表示任意非空的一段；owner 和 repo
// 与 GitHub 一样不区分大小写，其余各段精确比较。解析时已去掉 `.` 和 `..`，
// 但交给浏览器的仍是编码后的形式，解码后含 `/`、`\` 或 `%` 的段在服务端可能
// 再被解码而跳出本仓库，一律拒绝；查询和片段也会原样带给浏览器，同样拒绝。
Uri? _url(Object? value, List<String?> path) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isScheme('https') ||
      uri.host != 'github.com' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length != _repository.length + path.length ||
      segments.any(
        (segment) => segment.isEmpty || segment.contains(_unsafeInSegment),
      )) {
    return null;
  }
  for (final (index, name) in _repository.indexed) {
    if (segments[index].toLowerCase() != name.toLowerCase()) return null;
  }
  for (final (index, expected) in path.indexed) {
    if (expected != null && segments[_repository.length + index] != expected) {
      return null;
    }
  }
  return uri;
}

Never _unavailable(String event) {
  AppLog.debug(_logSource, event);
  throw const ReleaseUnavailable();
}
