import 'dart:async';
import 'dart:io';

import 'package:alisten/core/avatar/avatar_cache.dart';
import 'package:alisten/core/avatar/avatar_loader.dart';
import 'package:alisten/core/cache/disk_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const _logSource = 'avatars';

/// 存下的头像立即返回，每次运行在后台向站点重新下载一次，只更新磁盘上的文件。
final class DiskAvatarCache implements AvatarCache {
  DiskAvatarCache(
    this._loader, {
    Future<Directory> Function() directory = _appAvatarDirectory,
    int maxBytes = 20 * 1024 * 1024,
    DateTime Function() now = DateTime.now,
  }) : _store = DiskStore(
         directory: directory,
         maxBytes: maxBytes,
         logSource: _logSource,
         now: now,
       );

  final AvatarLoader _loader;
  final DiskStore _store;
  final _loads = <String, Future<Uint8List?>>{};
  final _checkedThisRun = <String>{};
  final _rechecks = <Future<void>>{};

  @visibleForTesting
  Future<void> get refreshing => Future.wait([..._rechecks]);

  @visibleForTesting
  Future<void> get trimming => _store.trimming;

  @override
  Future<Uint8List?> load(String url) => _loads[url] ??= _loadOnce(url);

  Future<Uint8List?> _loadOnce(String url) async {
    try {
      return await _load(url);
    } finally {
      unawaited(_loads.remove(url));
    }
  }

  @override
  Future<void> discard(String url) => _store.remove(url);

  @override
  Future<int> size() => _store.size();

  @override
  Future<void> clear() => _store.clear();

  Future<Uint8List?> _load(String url) async {
    final clears = _store.clears;
    final stored = await _store.read(url);
    if (stored != null) {
      if (_checkedThisRun.add(url)) _recheckLater(url, stored, clears);
      return stored;
    }
    final avatar = await _loader.load(url);
    _checkedThisRun.add(url);
    if (avatar != null) await _store.write(url, avatar, clears);
    return avatar;
  }

  void _recheckLater(String url, Uint8List stored, int clears) {
    final recheck = _recheck(url, stored, clears);
    _rechecks.add(recheck);
    unawaited(recheck.whenComplete(() => _rechecks.remove(recheck)));
  }

  // 在后台运行，不得抛出。
  Future<void> _recheck(String url, Uint8List stored, int clears) async {
    try {
      final avatar = await _loader.load(url);
      if (avatar == null) {
        await _store.remove(url, clears: clears);
      } else if (!listEquals(avatar, stored)) {
        await _store.write(url, avatar, clears);
      }
    } on AvatarUnavailable {
      // 连不上时保留存下的头像。
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'avatar not rechecked',
        type: '${error.runtimeType}',
      );
    }
  }
}

Future<Directory> _appAvatarDirectory() async {
  return Directory('${(await getApplicationCacheDirectory()).path}/avatars');
}
