import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 无系统标题栏时的窗口顶部信息：右上角控制按钮占用的宽高以及空白顶栏的拖动、
/// 双击最大化、右键系统菜单回调。
@immutable
final class WindowChromeData {
  const WindowChromeData({
    required this.titleBarHeight,
    required this.rightInset,
    this.onStartDragging,
    this.onToggleMaximize,
    this.onShowSystemMenu,
  });

  const WindowChromeData.none()
    : titleBarHeight = 0,
      rightInset = 0,
      onStartDragging = null,
      onToggleMaximize = null,
      onShowSystemMenu = null;

  final double titleBarHeight;

  /// 当前子区域右上角需要给窗口控制按钮留出的水平宽度。
  final double rightInset;
  final VoidCallback? onStartDragging;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onShowSystemMenu;

  bool get active => titleBarHeight > 0;

  WindowChromeData copyWith({double? rightInset}) => WindowChromeData(
    titleBarHeight: titleBarHeight,
    rightInset: rightInset ?? this.rightInset,
    onStartDragging: onStartDragging,
    onToggleMaximize: onToggleMaximize,
    onShowSystemMenu: onShowSystemMenu,
  );

  @override
  bool operator ==(Object other) =>
      other is WindowChromeData &&
      other.titleBarHeight == titleBarHeight &&
      other.rightInset == rightInset &&
      other.onStartDragging == onStartDragging &&
      other.onToggleMaximize == onToggleMaximize &&
      other.onShowSystemMenu == onShowSystemMenu;

  @override
  int get hashCode => Object.hash(
    titleBarHeight,
    rightInset,
    onStartDragging,
    onToggleMaximize,
    onShowSystemMenu,
  );
}

class WindowChrome extends InheritedWidget {
  const WindowChrome({required this.data, required super.child, super.key});

  final WindowChromeData data;

  static WindowChromeData of(BuildContext context) {
    if (!isWindowsDesktop) return const WindowChromeData.none();
    return context.dependOnInheritedWidgetOfExactType<WindowChrome>()?.data ??
        const WindowChromeData.none();
  }

  @override
  bool updateShouldNotify(WindowChrome oldWidget) => data != oldWidget.data;
}

/// 局部覆盖 [WindowChromeData.rightInset]，保留父级的标题栏高度与拖动回调。
class WindowChromeInset extends StatelessWidget {
  const WindowChromeInset({
    required this.rightInset,
    required this.child,
    super.key,
  });

  final double rightInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final current = WindowChrome.of(context);
    if (!current.active) return child;
    // 让位的宽度和上层一样时也包这一层：宽度随窗口变化，时包时不包会重建整页。
    return WindowChrome(
      data: current.copyWith(rightInset: rightInset),
      child: child,
    );
  }
}

/// 放在一行的末尾，把窗口控制按钮盖住的那一段让出来。
class WindowButtonsGap extends StatelessWidget {
  const WindowButtonsGap({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: WindowChrome.of(context).rightInset);
}

/// 页面最上面与标题栏等高的一条 [WindowDragArea]。放在 Stack 里、页面内容之下。
class WindowDragStrip extends StatelessWidget {
  const WindowDragStrip({super.key});

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    height: WindowChrome.of(context).titleBarHeight,
    child: const WindowDragArea(),
  );
}

/// 在一条顶栏的下面垫一层 [WindowDragArea]：栏里的按钮照常点，空白处拖动窗口。
class WindowDragBar extends StatelessWidget {
  const WindowDragBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isWindowsDesktop) return child;
    return Stack(
      children: [
        const Positioned.fill(child: WindowDragArea()),
        child,
      ],
    );
  }
}

/// 顶栏空白处的透明命中层：应放在按钮之下，拖动移动窗口、双击最大化/还原、
/// 右键呼出系统窗口菜单。
class WindowDragArea extends StatefulWidget {
  const WindowDragArea({super.key});

  @override
  State<WindowDragArea> createState() => _WindowDragAreaState();
}

class _WindowDragAreaState extends State<WindowDragArea> {
  static const _dragSlop = 4.0;
  static const _doubleTapSlop = 8.0;

  // Windows 默认的双击间隔，比 Flutter 的 300 毫秒宽。
  static const _doubleTapTimeout = Duration(milliseconds: 500);

  int? _pointer;
  Offset? _downPos;
  Duration? _lastTapAt;
  Offset? _lastTapPos;

  void _onDown(PointerDownEvent event, WindowChromeData chrome) {
    if (event.buttons & kPrimaryMouseButton != 0) {
      final lastAt = _lastTapAt;
      final lastPos = _lastTapPos;
      if (lastAt != null &&
          lastPos != null &&
          event.timeStamp - lastAt <= _doubleTapTimeout &&
          (event.position - lastPos).distance <= _doubleTapSlop) {
        _lastTapAt = null;
        _lastTapPos = null;
        _pointer = null;
        _downPos = null;
        chrome.onToggleMaximize?.call();
        return;
      }
      _lastTapAt = event.timeStamp;
      _lastTapPos = event.position;
      _pointer = event.pointer;
      _downPos = event.position;
    } else if (event.buttons & kSecondaryMouseButton != 0) {
      _pointer = null;
      _downPos = null;
      chrome.onShowSystemMenu?.call();
    }
  }

  void _onMove(PointerMoveEvent event, WindowChromeData chrome) {
    final down = _downPos;
    if (event.pointer != _pointer || down == null) return;
    if ((event.position - down).distance >= _dragSlop) {
      _pointer = null;
      _downPos = null;
      _lastTapAt = null;
      _lastTapPos = null;
      chrome.onStartDragging?.call();
    }
  }

  void _onUpOrCancel(PointerEvent event) {
    if (event.pointer == _pointer) {
      _pointer = null;
      _downPos = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = WindowChrome.of(context);
    if (!chrome.active) return const SizedBox.shrink();
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _onDown(event, chrome),
      onPointerMove: (event) => _onMove(event, chrome),
      onPointerUp: _onUpOrCancel,
      onPointerCancel: _onUpOrCancel,
      child: const SizedBox.expand(),
    );
  }
}
