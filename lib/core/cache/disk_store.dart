import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alisten/core/logging/app_log.dart';

/// 目录不可用时读不到也存不下，调用方照常下载。
final class DiskStore {
  DiskStore({
    required Future<Directory> Function() directory,
    required this._maxBytes,
    required this._logSource,
    this._now = DateTime.now,
  }) : _directoryOf = directory;

  final Future<Directory> Function() _directoryOf;
  final int _maxBytes;
  final String _logSource;
  final DateTime Function() _now;

  late final Future<Directory> _directory = _directoryOf();
  Future<void> _trimming = Future.value();
  bool _trimmedOnce = false;
  int _writtenSinceTrim = 0;
  int _clears = 0;
  bool _directoryWarned = false;

  /// 每次清除加一。调用方须在下载开始前读取并交给 [write]：下载期间发生过
  /// 清除时不再存储，以免清除后又写回。
  int get clears => _clears;

  Future<void> get trimming => _trimming;

  Future<Uint8List?> read(String url) async {
    final file = await _fileFor(url);
    if (file == null) return null;
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
      AppLog.debug(_logSource, 'use not recorded');
    }
    return bytes;
  }

  Future<File?> storedFile(String url) async {
    final file = await _fileFor(url);
    if (file == null || !await file.exists()) return null;
    return file;
  }

  Future<void> write(String url, Uint8List bytes, int clears) async {
    final file = await _fileFor(url);
    if (file != null && await _store(file, bytes, clears)) {
      _wrote(bytes.length);
    }
  }

  /// 给出 [clears] 时与 [write] 一样：之后发生过清除就不删，目录里可能已是
  /// 清除后重新存下的文件。
  Future<void> remove(String url, {int? clears}) async {
    if (clears != null && clears != _clears) return;
    final file = await _fileFor(url);
    if (file != null) await _deleteQuietly(file);
  }

  /// 占用的字节数。
  Future<int> size() async {
    var total = 0;
    for (final (_, stat) in await _files()) {
      total += stat.size;
    }
    return total;
  }

  Future<void> clear() async {
    _clears++;
    final directory = await _directory;
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } on PathNotFoundException {
        // 同时被淘汰或删除了，结果一样。
      }
    }
  }

  Future<File?> _fileFor(String url) async {
    try {
      return File('${(await _directory).path}/${_fileName(url)}');
    } on Object catch (error) {
      // 目录不可用时每次读写都会走到这里，只记一次。
      if (!_directoryWarned) {
        _directoryWarned = true;
        AppLog.warn(
          _logSource,
          'cache directory unavailable',
          type: '${error.runtimeType}',
        );
      }
      return null;
    }
  }

  // 先写临时文件再改名，目录中只有完整的文件。
  Future<bool> _store(File file, Uint8List bytes, int clears) async {
    if (clears != _clears) return false;
    final temporary = File('${file.path}.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } on FileSystemException {
      AppLog.debug(_logSource, 'not stored');
      await _deleteQuietly(temporary);
      return false;
    }
    // 写入期间开始的清除可能漏掉这个文件。
    if (clears != _clears) {
      await _deleteQuietly(file);
      return false;
    }
    // 记录失败时文件保留写入时间，只会让淘汰顺序略有偏差，仍算已存储。
    try {
      await file.setLastModified(_now());
    } on FileSystemException {
      AppLog.debug(_logSource, 'use not recorded');
    }
    return true;
  }

  // 每写入上限的 1/20 才清点一次目录，避免每存一个文件都遍历全部文件，
  // 总量因此可能暂时超出这么多。每次运行的首次写入都清点，
  // 以清理上次运行留下的超量。
  void _wrote(int bytes) {
    _writtenSinceTrim += bytes;
    if (_trimmedOnce && _writtenSinceTrim < _maxBytes ~/ 20) return;
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
        if (total <= _maxBytes) break;
        await _deleteQuietly(file);
        total -= stat.size;
      }
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'cache not trimmed',
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

// 64 位 FNV-1a 的十六进制：文件名不暴露地址。
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
