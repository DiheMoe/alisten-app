import 'package:flutter/widgets.dart';

enum RoomLayout { compact, portraitTwoPanes, landscapeTwoPanes }

RoomLayout roomLayoutOf(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width < _twoPanesMinWidth || size.height < _twoPanesMinHeight) {
    return RoomLayout.compact;
  }
  return size.width > size.height
      ? RoomLayout.landscapeTwoPanes
      : RoomLayout.portraitTwoPanes;
}

// 取自 Material 窗口尺寸类别：宽度 840 起为 expanded；高度低于 480 为 compact
// （包括横屏手机），宽度再大也放不下两栏。横屏时左侧独占播放器、右侧切换
// 歌词/队列/聊天，避免左栏上下平分导致歌词与播放器都被压扁。
const _twoPanesMinWidth = 840.0;
const _twoPanesMinHeight = 480.0;
