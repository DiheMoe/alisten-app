import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:flutter/material.dart';

abstract interface class CoverSchemeLoader {
  Future<ColorScheme> load(String url, Brightness brightness);
}

/// 须传入与界面封面相同的图片来源，取色和显示才能共用一次下载。
final class ImageCoverSchemeLoader implements CoverSchemeLoader {
  const ImageCoverSchemeLoader(this._image);

  final ImageProvider Function(String url) _image;

  @override
  Future<ColorScheme> load(String url, Brightness brightness) {
    return coverColorScheme(_image(url), brightness);
  }
}

Future<ColorScheme> coverColorScheme(
  ImageProvider cover,
  Brightness brightness,
) {
  return ColorScheme.fromImageProvider(
    provider: ResizeImage(cover, width: 64),
    brightness: brightness,
    dynamicSchemeVariant: AlistenColors.schemeVariant,
  );
}

final class CoverPalette implements CoverSchemeLoader {
  CoverPalette(this._source, {this.capacity = 16});

  final CoverSchemeLoader _source;
  final int capacity;

  // 按最近使用时间从早到晚排列。
  final _schemes = <(String, Brightness), Future<ColorScheme>>{};

  @override
  Future<ColorScheme> load(String url, Brightness brightness) async {
    final key = (url, brightness);
    final remembered = _schemes.remove(key);
    if (remembered != null) {
      _schemes[key] = remembered;
      return remembered;
    }

    final loading = _source.load(url, brightness);
    _schemes[key] = loading;
    // 每次读取都有调用方在等待，被移出缓存的读取不会丢失结果。
    if (_schemes.length > capacity) {
      unawaited(_schemes.remove(_schemes.keys.first));
    }
    try {
      return await loading;
    } on Object {
      if (identical(_schemes[key], loading)) unawaited(_schemes.remove(key));
      rethrow;
    }
  }
}
