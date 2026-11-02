import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

const gravatar = 'www.gravatar.com';
const weavatar = 'weavatar.com';
const cravatar = 'cravatar.cn';

String avatarUrl([String hash = 'abc123']) =>
    'https://$gravatar/avatar/$hash?d=404&s=80';

/// 按站点应答，不看路径；不在任何集合里的站点拒绝连接。
final class AvatarServer implements HttpClientAdapter {
  final avatars = <String, List<int>>{};
  final missing = <String>{};
  final hanging = <String>{};
  final requests = <String>[];
  int cancelled = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    requests.add(host);
    unawaited(cancelFuture?.then((_) => cancelled++));
    if (hanging.contains(host)) return Completer<ResponseBody>().future;
    final avatar = avatars[host];
    if (avatar != null) return ResponseBody.fromBytes(avatar, 200);
    if (missing.contains(host)) return ResponseBody.fromString('', 404);
    throw const SocketException('refused');
  }

  @override
  void close({bool force = false}) {}
}
