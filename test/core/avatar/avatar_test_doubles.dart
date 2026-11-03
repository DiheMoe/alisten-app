import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/avatar/avatar_loader.dart';
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

  Future<void>? responding;

  final _requested = Completer<void>();

  Future<void> get requested => _requested.future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    requests.add(host);
    if (!_requested.isCompleted) _requested.complete();
    unawaited(cancelFuture?.then((_) => cancelled++));
    if (hanging.contains(host)) return Completer<ResponseBody>().future;
    await responding;
    final avatar = avatars[host];
    if (avatar != null) return ResponseBody.fromBytes(avatar, 200);
    if (missing.contains(host)) return ResponseBody.fromString('', 404);
    throw const SocketException('refused');
  }

  @override
  void close({bool force = false}) {}
}

/// 不在 [avatars] 里的地址按没设头像应答。
final class FakeAvatarCache implements AvatarCache {
  FakeAvatarCache({Map<String, Uint8List>? avatars, this.bytes = 0})
    : avatars = avatars ?? {};

  final Map<String, Uint8List> avatars;
  int bytes;
  int clears = 0;
  bool unreachable = false;
  Completer<void>? loading;

  Exception? clearError;

  @override
  Future<Uint8List?> load(String url) async {
    await loading?.future;
    if (unreachable) throw const AvatarUnavailable();
    return avatars[url];
  }

  @override
  Future<void> discard(String url) async {}

  @override
  Future<int> size() async => bytes;

  @override
  Future<void> clear() async {
    clears++;
    final error = clearError;
    if (error != null) throw error;
    bytes = 0;
  }
}
