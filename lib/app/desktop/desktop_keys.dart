import 'dart:async';

import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面窗口的快捷键：Esc 返回；在房间里 Ctrl/Cmd K 打开点歌，空格切换本机暂停。
class DesktopKeys extends ConsumerWidget {
  const DesktopKeys({required this.location, required this.child, super.key});

  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.of(context);
    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      final keyboard = HardwareKeyboard.instance;
      if (key == LogicalKeyboardKey.escape && router.canPop()) {
        router.pop();
        return KeyEventResult.handled;
      }
      final room = ref.read(roomControllerProvider);
      final roomId = room.activeRoomId;
      if (roomId == null) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyK &&
          (keyboard.isControlPressed || keyboard.isMetaPressed)) {
        final search = '/r/${room.roomSlug ?? roomId}/search';
        if (location.path != search) unawaited(router.push<void>(search));
        return KeyEventResult.handled;
      }
      // 正在输入时空格是文字。
      final typing =
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() !=
          null;
      if (key == LogicalKeyboardKey.space && !typing) {
        unawaited(
          ref.read(playbackControllerProvider.notifier).toggleLocalPause(),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: onKey,
      child: child,
    );
  }
}
