import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

typedef LyricSnapshotKey = (int row, int level);

final class LyricSnapshot {
  const LyricSnapshot(this.image, this.rect);

  final ui.Image image;

  /// 图片覆盖的范围，行内坐标；模糊会超出文字本身。
  final Rect rect;
}

/// 模糊结果的固定容量缓存，上限决定了歌词页占用的图片内存。
final class LyricSnapshotCache {
  LyricSnapshotCache({this._capacity = 32});

  int _capacity;
  int get capacity => _capacity;
  set capacity(int value) {
    _capacity = value;
    _trim();
  }

  final _entries = <LyricSnapshotKey, LyricSnapshot>{};

  LyricSnapshot? operator [](LyricSnapshotKey key) {
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry;
    return entry;
  }

  void store(LyricSnapshotKey key, LyricSnapshot snapshot) {
    _entries.remove(key)?.image.dispose();
    _entries[key] = snapshot;
    _trim();
  }

  void _trim() {
    while (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first)?.image.dispose();
    }
  }

  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
  }
}
