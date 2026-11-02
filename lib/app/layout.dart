import 'package:flutter/widgets.dart';

bool roomInTwoPanes(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width >= _twoPanesMinWidth && size.height >= _twoPanesMinHeight;
}

// 取自 Material 窗口尺寸类别：宽度 840 起为 expanded；高度低于 480 为 compact
// （包括横屏手机），宽度再大也放不下播放器和下方的歌词。
const _twoPanesMinWidth = 840.0;
const _twoPanesMinHeight = 480.0;
