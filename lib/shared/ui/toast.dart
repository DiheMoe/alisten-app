import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

enum ToastKind { info, success, warning, failure }

/// 按对象标识区分：文字相同的两条提示仍是不同的提示，重复的消息会再次显示。
final class ToastMessage {
  ToastMessage(this.kind, this.text);

  final ToastKind kind;
  final String text;
}

final class ToastController extends ChangeNotifier {
  ToastController({this.duration = AlistenDurations.toast});

  final Duration duration;

  ToastMessage? _current;
  Timer? _timer;

  ToastMessage? get current => _current;

  void show(ToastKind kind, String text, {Duration? duration}) {
    _timer?.cancel();
    _current = ToastMessage(kind, text);
    _timer = Timer(duration ?? this.duration, dismiss);
    notifyListeners();
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 须放在导航器之上，切换页面时提示才不会消失。
class ToastHost extends StatefulWidget {
  const ToastHost({required this.controller, required this.child, super.key});

  final ToastController controller;
  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this)
    ..addStatusListener(_onMotionStatus);
  late final CurvedAnimation _rise = CurvedAnimation(
    parent: _motion,
    curve: AlistenCurves.bounce,
    reverseCurve: AlistenCurves.exit,
  );
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _motion,
    curve: AlistenCurves.standard,
    reverseCurve: AlistenCurves.exit,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, -0.25),
    end: Offset.zero,
  ).animate(_rise);

  // 离开动画播放期间仍保留已撤下的提示。
  ToastMessage? _shown;

  final _clearances = <Object, double>{};
  double _clearance = 0;
  bool _clearanceScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onToast);
    _shown = widget.controller.current;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = AlistenDurations.of(context, AlistenDurations.medium);
    if (_shown != null && !_motion.isAnimating && _motion.value == 0) {
      unawaited(_motion.forward());
    }
  }

  @override
  void didUpdateWidget(ToastHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onToast);
      widget.controller.addListener(_onToast);
      _onToast();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onToast);
    _rise.dispose();
    _fade.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _onToast() {
    final next = widget.controller.current;
    if (next != null) {
      setState(() => _shown = next);
      unawaited(_motion.forward());
    } else {
      unawaited(_motion.reverse());
    }
  }

  void _onMotionStatus(AnimationStatus status) {
    if (status.isDismissed && _shown != null) setState(() => _shown = null);
  }

  void _reserve(Object owner, double? extent) {
    if (extent == null) {
      _clearances.remove(owner);
    } else {
      _clearances[owner] = extent;
    }
    // 在栏的布局阶段调用，宿主此时不能重建，推迟到本帧之后。
    if (_clearanceScheduled) return;
    _clearanceScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _clearanceScheduled = false;
        final clearance = _clearances.values.fold(0.0, math.max);
        if (mounted && clearance != _clearance) {
          setState(() => _clearance = clearance);
        }
      })
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final top =
        math.max(MediaQuery.paddingOf(context).top, _clearance) +
        AlistenSpacing.xs;
    return _ToastScope(
      host: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (shown != null)
            Positioned(
              top: top,
              left: AlistenSpacing.page,
              right: AlistenSpacing.page,
              // 提示不挡住下方页面，到时自行消失。
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AlistenSizes.toastMaxWidth,
                        ),
                        child: _ToastCapsule(message: shown),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToastCapsule extends StatelessWidget {
  const _ToastCapsule({required this.message});

  final ToastMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final (icon, ink) = switch (message.kind) {
      ToastKind.info => (Icons.info_rounded, colors.onGlass),
      ToastKind.success => (Icons.check_circle_rounded, colors.success),
      ToastKind.warning => (Icons.warning_rounded, colors.warning),
      ToastKind.failure => (Icons.error_rounded, colors.danger),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.raised,
          borderRadius: BorderRadius.circular(AlistenRadii.pill),
          border: Border.all(color: colors.glassStroke),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow
                  .withValues(alpha: 0.24),
              blurRadius: AlistenSpacing.xl,
              offset: const Offset(0, AlistenSpacing.xs),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AlistenSpacing.xs,
            AlistenSpacing.xs,
            AlistenSpacing.lg,
            AlistenSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ink.withValues(alpha: 0.16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AlistenSpacing.xxs),
                  child: Icon(icon, size: AlistenSizes.iconSm, color: ink),
                ),
              ),
              const SizedBox(width: AlistenSpacing.sm),
              Flexible(
                // 宿主位于所有页面之上，拿不到页面的默认文字样式。
                child: DefaultTextStyle(
                  style: AlistenTypography.bodyStrong.copyWith(
                    color: colors.onGlass,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  child: Text(message.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastScope extends InheritedWidget {
  const _ToastScope({required this.host, required super.child});

  final _ToastHostState host;

  @override
  bool updateShouldNotify(_ToastScope oldWidget) =>
      !identical(host, oldWidget.host);
}

/// 包住页面顶部的栏，提示显示在它下方。测得的高度按距屏幕顶端的距离使用，
/// 因此栏必须从屏幕顶端开始。
class ToastClearance extends StatefulWidget {
  const ToastClearance({required this.child, super.key});

  final Widget child;

  @override
  State<ToastClearance> createState() => _ToastClearanceState();
}

class _ToastClearanceState extends State<ToastClearance> {
  _ToastHostState? _host;
  double? _extent;

  // 被其他页面盖住或应用在后台时 TickerMode 关闭，借此判断是否在屏幕上。
  bool _onScreen = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = context
        .dependOnInheritedWidgetOfExactType<_ToastScope>()
        ?.host;
    _onScreen = TickerMode.valuesOf(context).enabled;
    if (!identical(host, _host)) {
      _host?._reserve(this, null);
      _host = host;
    }
    _report();
  }

  @override
  void dispose() {
    _host?._reserve(this, null);
    super.dispose();
  }

  void _report() => _host?._reserve(this, _onScreen ? _extent : null);

  @override
  Widget build(BuildContext context) {
    return _SizeReporter(
      onSize: (size) {
        _extent = size.height;
        _report();
      },
      child: widget.child,
    );
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  _RenderSizeReporter createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _reported) {
      _reported = size;
      onSize(size);
    }
  }
}
