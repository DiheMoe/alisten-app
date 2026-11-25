import 'package:flutter/widgets.dart';

enum RoomLayout { compact, landscapeTwoPanes }

RoomLayout roomLayoutOf(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width >= _twoPanesMinWidth &&
          size.height >= _twoPanesMinHeight &&
          size.width > size.height
      ? RoomLayout.landscapeTwoPanes
      : RoomLayout.compact;
}

// 取自 Material 窗口尺寸类别：宽度 840 起为 expanded；高度低于 480 为 compact
// （包括横屏手机），宽度再大也放不下两栏。竖着拿时不分两栏，和手机一致。
const _twoPanesMinWidth = 840.0;
const _twoPanesMinHeight = 480.0;
