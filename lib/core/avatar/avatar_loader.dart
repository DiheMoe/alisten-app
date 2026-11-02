import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/logging/app_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final avatarLoaderProvider = Provider<AvatarLoader>((ref) {
  throw UnimplementedError('avatarLoader 未注入');
});

const _logSource = 'avatars';

const _gravatarHost = 'www.gravatar.com';

// 有些网络连不上 Gravatar。这些镜像用同样的路径和参数给出同一头像。
const _mirrorHosts = ['weavatar.com', 'cravatar.cn'];

// 被拦截的站点常常既连不上也不报错，只能靠超时判断。
const _gravatarProbeTimeout = Duration(seconds: 3);
const _mirrorProbeTimeout = Duration(seconds: 5);
const _downloadTimeout = Duration(seconds: 10);

typedef _Answer = ({String host, Uint8List? avatar});

/// 第一次加载时选定一个连得上的站点，之后的头像都从它下载。选定期间其他头像
/// 等待结果，不各自探测。选定的站点连不上时重新从 Gravatar 选起。
final class AvatarLoader {
  AvatarLoader(this._dio);

  final Dio _dio;
  String? _host;
  Future<({Uri uri, _Answer answer})?>? _choosing;

  // 本次运行中已知没设头像的地址，不再请求。
  final _absent = <String>{};

  /// [url] 是 Gravatar 的头像地址。没设头像时为 null；
  /// 没有站点连得上时抛出 [AvatarUnavailable]。
  Future<Uint8List?> load(String url) async {
    if (_absent.contains(url)) return null;
    final answer = await _answer(Uri.parse(url));
    if (answer == null) throw const AvatarUnavailable();
    final avatar = answer.avatar;
    if (avatar == null) _absent.add(url);
    return avatar;
  }

  Future<_Answer?> _answer(Uri uri) async {
    final host = _host;
    if (host != null) {
      final answer = await _get(uri, host, _downloadTimeout);
      if (answer != null) return answer;
      // 之后的头像改为等待重新选择，不再各自在失效的站点上等超时。
      if (_host == host) _host = null;
    }
    final choice = await (_choosing ??= _choose(uri)
        .whenComplete(() => _choosing = null));
    if (choice == null) return null;
    if (choice.uri == uri) return choice.answer;
    return _get(uri, choice.answer.host, _downloadTimeout);
  }

  // 先试 Gravatar，连不上再同时试各个镜像，用最先应答的那个。
  Future<({Uri uri, _Answer answer})?> _choose(Uri uri) async {
    final answer =
        await _get(uri, _gravatarHost, _gravatarProbeTimeout) ??
        await _firstNonNull([
          for (final host in _mirrorHosts) _get(uri, host, _mirrorProbeTimeout),
        ]);
    if (answer == null) return null;
    _host = answer.host;
    return (uri: uri, answer: answer);
  }

  // 连不上、超时或应答异常时为 null；404 表示站点连得上，只是没设头像。
  // 日志不含地址：地址中有邮箱的哈希。
  Future<_Answer?> _get(Uri uri, String host, Duration timeout) async {
    final cancel = CancelToken();
    final Response<List<int>> response;
    try {
      response = await _dio
          .getUri<List<int>>(
            uri.replace(host: host),
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.bytes,
              connectTimeout: timeout,
            ),
          )
          .timeout(timeout);
    } on TimeoutException {
      cancel.cancel();
      AppLog.debug(_logSource, 'avatar download timed out');
      return null;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 404) return (host: host, avatar: null);
      AppLog.debug(
        _logSource,
        'avatar not downloaded',
        code: status?.toString(),
        outcome: error.type,
      );
      return null;
    }
    final data = response.data;
    if (data == null || data.isEmpty) {
      AppLog.debug(_logSource, 'avatar empty');
      return null;
    }
    return (
      host: host,
      avatar: data is Uint8List ? data : Uint8List.fromList(data),
    );
  }
}

Future<T?> _firstNonNull<T extends Object>(List<Future<T?>> futures) {
  final first = Completer<T?>();
  var pending = futures.length;
  for (final future in futures) {
    unawaited(
      future.then((value) {
        pending--;
        if (first.isCompleted) return;
        if (value != null || pending == 0) first.complete(value);
      }),
    );
  }
  return first.future;
}

/// 不带地址：地址中有邮箱的哈希。
final class AvatarUnavailable implements Exception {
  const AvatarUnavailable();

  @override
  String toString() => 'AvatarUnavailable';
}
