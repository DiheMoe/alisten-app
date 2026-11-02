import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/cache/disk_cover_cache.dart';
import 'package:dio/dio.dart';

final class CoverServer implements HttpClientAdapter {
  final covers = <String, List<int>>{};
  final requests = <String>[];
  bool hang = false;
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
    final url = options.uri.toString();
    requests.add(url);
    if (!_requested.isCompleted) _requested.complete();
    unawaited(cancelFuture?.then((_) => cancelled++));
    if (hang) return Completer<ResponseBody>().future;
    await responding;
    final body = covers[url];
    return body == null
        ? ResponseBody.fromString('', 404)
        : ResponseBody.fromBytes(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

final class FakeCoverCache implements CoverCache {
  FakeCoverCache({Map<String, Uint8List>? covers, this.bytes = 0})
    : covers = covers ?? {};

  final Map<String, Uint8List> covers;
  int bytes;
  final loads = <String>[];
  final discarded = <String>[];
  int clears = 0;
  Completer<void>? measuring;
  Completer<void>? clearing;

  Exception? clearError;

  @override
  Future<Uint8List> load(String url) async {
    loads.add(url);
    final cover = covers[url];
    if (cover == null) throw const CoverUnavailable('missing');
    return cover;
  }

  static Uri fileOf(String url) =>
      Uri.file('/cache/covers/${Uri.encodeComponent(url)}');

  final fileRequests = <String>[];

  @override
  Future<Uri?> localFile(String url) async {
    fileRequests.add(url);
    if (!covers.containsKey(url)) throw const CoverUnavailable('missing');
    return fileOf(url);
  }

  @override
  Future<void> discard(String url) async => discarded.add(url);

  @override
  Future<int> size() async {
    await measuring?.future;
    return bytes;
  }

  @override
  Future<void> clear() async {
    clears++;
    await clearing?.future;
    final error = clearError;
    if (error != null) throw error;
    bytes = 0;
  }
}
