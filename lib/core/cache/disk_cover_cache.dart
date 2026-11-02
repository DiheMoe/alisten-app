import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alisten/core/cache/cover_cache.dart';
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
    this.maxBytes = 200 * 1024 * 1024,
    this._now = DateTime.now,
  }) : _directoryOf = directory;

  final Dio _dio;
  final Future<Directory> Function() _directoryOf;
  final int maxBytes;
  final DateTime Function() _now;

  late final Future<Directory> _directory = _directoryOf();
  final _loads = <String, Future<Uint8List>>{};
  Future<void> _trimming = Future.value();
  bool _trimmedOnce = false;
  int _writtenSinceTrim = 0;

  // 每次清除加一。下载期间发生过清除时不再存储下载结果，以免清除后又写回。
  int _clears = 0;

  @visibleForTesting
  Future<void> get trimming => _trimming;

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
    final file = await _fileFor(url);
    if (file == null || !await file.exists()) return null;
    return file.uri;
  }

  @override
  Future<void> discard(String url) async {
    final file = await _fileFor(url);
    if (file != null) await _deleteQuietly(file);
  }

  @override
  Future<int> size() async {
    var total = 0;
    for (final (_, stat) in await _files()) {
      total += stat.size;
    }
    return total;
  }

  @override
  Future<void> clear() async {
    _clears++;
    final directory = await _directory;
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } on PathNotFoundException {
        // 同时被淘汰或丢弃了，结果一样。
      }
    }
  }

  Future<Uint8List> _load(String url) async {
    final clears = _clears;
    final file = await _fileFor(url);
    if (file != null) {
      final cached = await _read(file);
      if (cached != null) return cached;
    }
    final bytes = await _download(url);
    if (file != null && await _store(file, bytes, clears)) {
      _wrote(bytes.length);
    }
    return bytes;
  }

  // 目录不可用时照常下载，只是不存。
  Future<File?> _fileFor(String url) async {
    try {
      return File('${(await _directory).path}/${_fileName(url)}');
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'cover directory unavailable',
        type: '${error.runtimeType}',
      );
      return null;
    }
  }

  Future<Uint8List?> _read(File file) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
    if (bytes.isEmpty) return null;
    // 修改时间记录最近一次使用，淘汰时按它排序。
    try {
      await file.setLastModified(_now());
    } on FileSystemException {
      AppLog.debug(_logSource, 'cover use not recorded');
    }
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

  // 先写临时文件再改名，目录中只有完整的封面。[clears] 是下载开始前的清除次数。
  Future<bool> _store(File file, Uint8List bytes, int clears) async {
    if (clears != _clears) return false;
    final temporary = File('${file.path}.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } on FileSystemException {
      AppLog.debug(_logSource, 'cover not stored');
      await _deleteQuietly(temporary);
      return false;
    }
    // 写入期间开始的清除可能漏掉这个文件。
    if (clears != _clears) {
      await _deleteQuietly(file);
      return false;
    }
    // 记录失败时文件保留写入时间，只会让淘汰顺序略有偏差，封面仍算已存储。
    try {
      await file.setLastModified(_now());
    } on FileSystemException {
      AppLog.debug(_logSource, 'cover use not recorded');
    }
    return true;
  }

  // 每写入上限的 1/20 才清点一次目录，避免每存一张封面都遍历全部文件，
  // 总量因此可能暂时超出这么多。每次运行的首次写入都清点，
  // 以清理上次运行留下的超量。
  void _wrote(int bytes) {
    _writtenSinceTrim += bytes;
    if (_trimmedOnce && _writtenSinceTrim < maxBytes ~/ 20) return;
    _trimmedOnce = true;
    _writtenSinceTrim = 0;
    _trimming = _trimming.then((_) => _trim());
  }

  Future<void> _trim() async {
    try {
      final files = await _files();
      var total = 0;
      for (final (_, stat) in files) {
        total += stat.size;
      }
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in files) {
        if (total <= maxBytes) break;
        await _deleteQuietly(file);
        total -= stat.size;
      }
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'cover cache not trimmed',
        type: '${error.runtimeType}',
      );
    }
  }

  Future<List<(File, FileStat)>> _files() async {
    final directory = await _directory;
    if (!await directory.exists()) return [];
    final files = <(File, FileStat)>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.file) files.add((entity, stat));
    }
    return files;
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

// 64 位 FNV-1a 的十六进制：文件名不暴露封面地址。
String _fileName(String url) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(url)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  String hex(int half) => half.toRadixString(16).padLeft(8, '0');
  return hex(hash >>> 32) + hex(hash & 0xffffffff);
}

Future<void> _deleteQuietly(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // 已经不在，或者下次淘汰时再删。
  }
}
