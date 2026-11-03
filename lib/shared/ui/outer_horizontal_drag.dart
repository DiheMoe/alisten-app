import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 在 [child] 上开始的横向拖动交给外层的横向滚动视图（如分页）。
///
/// 用于 [child] 里有同样认领横向拖动、又比外层先收到触摸的手势时，比如 Android
/// 上的文字选择区：它与外层滚动视图的判定阈值相同，总是先胜出。没有外层横向
/// 滚动视图时不起作用。
class OuterHorizontalDrag extends StatefulWidget {
  const OuterHorizontalDrag({required this.child, super.key});

  final Widget child;

  @override
  State<OuterHorizontalDrag> createState() => _OuterHorizontalDragState();
}

class _OuterHorizontalDragState extends State<OuterHorizontalDrag> {
  ScrollableState? _outer;
  ScrollHoldController? _hold;
  Drag? _drag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outer = Scrollable.maybeOf(context, axis: Axis.horizontal);
  }

  // 拖动中被移除时识别器不会报告拖动结束，要在这里结束，外层才不会停在半途。
  // 外层是祖先，此时仍然存在。
  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  // 与 `ScrollableState` 处理自己拖动的方式相同。
  void _down(DragDownDetails _) {
    _hold = _outer?.position.hold(() => _hold = null);
  }

  void _start(DragStartDetails details) {
    _drag = _outer?.position.drag(details, () => _drag = null);
    _hold = null;
  }

  void _update(DragUpdateDetails details) => _drag?.update(details);

  void _end(DragEndDetails details) => _drag?.end(details);

  void _cancel() {
    _hold?.cancel();
    _drag?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final outer = _outer;
    final behavior = ScrollConfiguration.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        // 叠在子组件之上，比其中的手势先收到触摸、先判定横向拖动。
        if (outer != null)
          Positioned.fill(
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              excludeFromSemantics: true,
              gestures: {
                HorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      HorizontalDragGestureRecognizer
                    >(
                      () => HorizontalDragGestureRecognizer(
                        debugOwner: this,
                        supportedDevices: behavior.dragDevices,
                      ),
                      (recognizer) {
                        final physics = outer.position.physics;
                        recognizer
                          ..onDown = _down
                          ..onStart = _start
                          ..onUpdate = _update
                          ..onEnd = _end
                          ..onCancel = _cancel
                          ..minFlingDistance = physics.minFlingDistance
                          ..minFlingVelocity = physics.minFlingVelocity
                          ..maxFlingVelocity = physics.maxFlingVelocity
                          ..velocityTrackerBuilder = behavior
                              .velocityTrackerBuilder(context)
                          ..dragStartBehavior = outer.widget.dragStartBehavior
                          ..multitouchDragStrategy = behavior
                              .getMultitouchDragStrategy(context)
                          ..gestureSettings = MediaQuery.maybeGestureSettingsOf(
                            context,
                          )
                          ..supportedDevices = behavior.dragDevices;
                      },
                    ),
              },
            ),
          ),
      ],
    );
  }
}
