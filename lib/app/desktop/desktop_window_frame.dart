import 'dart:async';

import 'package:alisten/app/desktop/desktop_window_control.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/window_chrome.dart';
import 'package:flutter/widgets.dart';

const desktopTitleBarHeight = 36.0;

// 与 Windows 11 自带的窗口按钮同宽。
const _captionButtonWidth = 46.0;
const desktopCaptionButtonsWidth = _captionButtonWidth * 3;
const _windowCornerRadius = 8.0;
const _closeHoverColor = Color(0xFFC42B1C);
const _closePressColor = Color(0xFFB32619);

/// Windows 上没有系统标题栏：页面顶到窗口上沿，窗口按钮叠在右上角，页面经
/// [WindowChrome] 得知要让出多宽。
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({
    required this.control,
    required this.child,
    super.key,
  });

  final DesktopWindowControl control;
  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  DesktopWindowControl get _control => widget.control;
  bool _maximized = false;

  void _startDragging() => unawaited(_control.startDragging());
  void _toggleMaximize() => unawaited(_control.toggleMaximize());
  void _showSystemMenu() => unawaited(_control.showSystemMenu());

  @override
  void initState() {
    super.initState();
    _control.listenMaximized(_onMaximizedChanged);
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    _control.listenMaximized(null);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final maximized = await _control.isMaximized();
    if (mounted && _maximized != maximized) {
      setState(() => _maximized = maximized);
    }
  }

  void _onMaximizedChanged(bool maximized) {
    if (mounted && _maximized != maximized) {
      setState(() => _maximized = maximized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = WindowChromeData(
      titleBarHeight: desktopTitleBarHeight,
      rightInset: desktopCaptionButtonsWidth,
      onStartDragging: _startDragging,
      onToggleMaximize: _toggleMaximize,
      onShowSystemMenu: _showSystemMenu,
    );
    return WindowChrome(
      data: chrome,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            top: 0,
            right: 0,
            height: desktopTitleBarHeight,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CaptionButton(
                    key: const ValueKey('window-minimize'),
                    glyph: _CaptionGlyph.minimize,
                    semanticLabel: '最小化',
                    onPressed: () => unawaited(_control.minimize()),
                  ),
                  _CaptionButton(
                    key: const ValueKey('window-maximize'),
                    glyph: _maximized
                        ? _CaptionGlyph.restore
                        : _CaptionGlyph.maximize,
                    semanticLabel: _maximized ? '还原' : '最大化',
                    onPressed: _toggleMaximize,
                  ),
                  _CaptionButton(
                    key: const ValueKey('window-close'),
                    glyph: _CaptionGlyph.close,
                    semanticLabel: '关闭',
                    cornerRadius: _maximized ? 0 : _windowCornerRadius,
                    onPressed: () => unawaited(_control.close()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CaptionGlyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.glyph,
    required this.semanticLabel,
    required this.onPressed,
    this.cornerRadius = 0,
    super.key,
  });

  final _CaptionGlyph glyph;
  final String semanticLabel;
  final VoidCallback onPressed;
  final double cornerRadius;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final close = widget.glyph == _CaptionGlyph.close;
    final fill = close
        ? _pressed
              ? _closePressColor
              : _hovered
              ? _closeHoverColor
              : const Color(0x00000000)
        : _pressed
        ? colors.onGlass.withValues(alpha: 0.14)
        : _hovered
        ? colors.onGlass.withValues(alpha: 0.08)
        : const Color(0x00000000);
    final iconColor = close && (_hovered || _pressed)
        ? const Color(0xFFFFFFFF)
        : colors.onGlass.withValues(alpha: _hovered || _pressed ? 1.0 : 0.84);
    final duration = AlistenDurations.of(
      context,
      const Duration(milliseconds: 100),
    );
    final radius = widget.cornerRadius > 0
        ? BorderRadius.only(topRight: Radius.circular(widget.cornerRadius))
        : BorderRadius.zero;
    return Semantics(
      container: true,
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: duration,
            width: _captionButtonWidth,
            height: desktopTitleBarHeight,
            decoration: BoxDecoration(color: fill, borderRadius: radius),
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _CaptionGlyphPainter(
                glyph: widget.glyph,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter({required this.glyph, required this.color});

  final _CaptionGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    switch (glyph) {
      case _CaptionGlyph.minimize:
        final y = (size.height / 2).floorToDouble() + 0.5;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      case _CaptionGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
            const Radius.circular(1.5),
          ),
          paint,
        );
      case _CaptionGlyph.restore:
        final front = RRect.fromRectAndRadius(
          Rect.fromLTWH(0.5, 2.5, size.width - 3, size.height - 3),
          const Radius.circular(1.2),
        );
        canvas.drawRRect(front, paint);
        final back = Path()
          ..moveTo(2.5, 2.0)
          ..lineTo(2.5, 1.5)
          ..quadraticBezierTo(2.5, 0.5, 3.5, 0.5)
          ..lineTo(size.width - 1.5, 0.5)
          ..quadraticBezierTo(size.width - 0.5, 0.5, size.width - 0.5, 1.5)
          ..lineTo(size.width - 0.5, size.height - 3.5)
          ..quadraticBezierTo(
            size.width - 0.5,
            size.height - 2.5,
            size.width - 1.5,
            size.height - 2.5,
          )
          ..lineTo(size.width - 2.0, size.height - 2.5);
        canvas.drawPath(back, paint);
      case _CaptionGlyph.close:
        canvas
          ..drawLine(
            const Offset(0.75, 0.75),
            Offset(size.width - 0.75, size.height - 0.75),
            paint,
          )
          ..drawLine(
            Offset(size.width - 0.75, 0.75),
            Offset(0.75, size.height - 0.75),
            paint,
          );
    }
  }

  @override
  bool shouldRepaint(_CaptionGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
