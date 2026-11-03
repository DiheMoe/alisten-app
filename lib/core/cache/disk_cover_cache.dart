import 'dart:async';
import 'dart:io';

import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/cache/disk_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const _logSource = 'covers';

const _connectTimeout = Duration(seconds: 10);

// 封面原图可能有几 MB，总超时比接口请求的 15 秒宽松。
const _downloadTimeout = Duration(seconds: 30);

// 超过这个大小的多半不是封面，中途取消且不存储。
const _maxCoverBytes = 10 * 1024 * 1024;

final class DiskCoverCache implements CoverCache {
  DiskCoverCache(
    this._dio, {
    Future<Directory> Function() directory = _appCoverDirectory,
    int maxBytes = 200 * 1024 * 1024,
    DateTime Function() now = DateTime.now,
  }) : _store = DiskStore(
         directory: directory,
         maxBytes: maxBytes,
         logSource: _logSource,
         now: now,
       );

  final Dio _dio;
  final DiskStore _store;
  final _loads = <String, Future<Uint8List>>{};

  @visibleForTesting
  Future<void> get trimming => _store.trimming;

  @override
  Future<Uint8List> load(String url) => _loads[url] ??= _loadOnce(url);

  Future<Uint8List> _loadOnce(String url) async {
    try {
      return await _load(url);
    } finally {
      unawaited(_loads.remove(url));
    }
  }

  @override
  Future<Uri?> localFile(String url) async {
    await load(url);
    return (await _store.storedFile(url))?.uri;
  }

  @override
  Future<void> discard(String url) => _store.remove(url);

  @override
  Future<int> size() => _store.size();

  @override
  Future<void> clear() => _store.clear();

  Future<Uint8List> _load(String url) async {
    final clears = _store.clears;
    final cached = await _store.read(url);
    if (cached != null) return cached;
    final bytes = await _download(url);
    await _store.write(url, bytes, clears);
    return bytes;
  }

  // 错误不含地址：图片加载失败时 Flutter 可能打印错误。
  Future<Uint8List> _download(String url) async {
    final cancel = CancelToken();
    var tooLarge = false;
    final Response<List<int>> response;
    try {
      response = await _dio
          .get<List<int>>(
            url,
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.bytes,
              connectTimeout: _connectTimeout,
            ),
            // 按声明的长度或已收到的长度尽早取消；长度未知时 total 为 -1。
            onReceiveProgress: (received, total) {
              if (tooLarge ||
                  (received <= _maxCoverBytes && total <= _maxCoverBytes)) {
                return;
              }
              tooLarge = true;
              cancel.cancel();
            },
          )
          .timeout(_downloadTimeout);
    } on TimeoutException {
      cancel.cancel();
      AppLog.debug(_logSource, 'cover download timed out');
      throw const CoverUnavailable('timed out');
    } on DioException catch (error) {
      if (tooLarge) throw _tooLarge();
      AppLog.debug(
        _logSource,
        'cover not downloaded',
        code: error.response?.statusCode?.toString(),
        outcome: error.type,
      );
      throw CoverUnavailable(error.type.name);
    }
    final data = response.data;
    if (data == null || data.isEmpty) {
      AppLog.debug(_logSource, 'cover empty');
      throw const CoverUnavailable('empty');
    }
    // 取消可能晚于完整的响应到达。
    if (data.length > _maxCoverBytes) throw _tooLarge();
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  static CoverUnavailable _tooLarge() {
    AppLog.debug(_logSource, 'cover too large');
    return const CoverUnavailable('too large');
  }
}

/// 只带原因，不带封面地址。
final class CoverUnavailable implements Exception {
  const CoverUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'CoverUnavailable: $reason';
}

Future<Directory> _appCoverDirectory() async {
  return Directory('${(await getApplicationCacheDirectory()).path}/covers');
}
