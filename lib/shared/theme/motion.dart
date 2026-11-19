import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// 页面、面板、开关和菜单共用这一套弹簧，全 App 的动效保持一致。
abstract final class AlistenSprings {
  static final page = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 300),
  );

  /// 翻页起步速度：每秒 9 倍距离，0.1 秒就走完大半，之后慢慢停稳。
  static const double pageLaunch = 9;

  /// 拖动时页面追手指的弹簧，比手指稍慢一点。
  static final follow = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 80),
    bounce: 0.15,
  );

  /// 拖动松手后带着手指速度完成返回或回弹。
  static final release = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 300),
    bounce: 0.15,
  );

  /// UIKit 的面板弹簧：质量 3、刚度 1000，临界阻尼。
  static final sheet = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 1000 / 3,
  );

  /// 菜单从触发按钮的外形长成面板，略冲过一点再停稳。
  static final menuOpen = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 400,
    ratio: 0.754,
  );

  /// 菜单收回按钮：约 0.35 秒缩回，不回弹。
  static final menuClose = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 350),
  );

  /// 页面和面板从被点的元素长出：略冲过一点再停稳。真机上调过再改这里。
  static final zoomOpen = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 400),
    bounce: 0.1,
  );

  /// 页面和面板缩回被点的元素，与菜单收起相同。
  static final zoomClose = menuClose;

  /// 刚发出的消息从输入框飞进时间线，落地时轻轻一弹。
  static final chatFlight = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 450),
    bounce: 0.15,
  );

  /// 菜单展开后外框从胶囊收成卡片圆角。
  static final menuCorners = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 324,
    ratio: 0.75,
  );
}

abstract final class AlistenMotion {
  /// 按下的反馈至少保持这么久，快速点按也看得到。
  static const pressHold = Duration(milliseconds: 150);
  static const pressInk = Duration(milliseconds: 200);
  static const pressRelease = Duration(milliseconds: 250);
  static const Curve pressReleaseCurve = Curves.easeInOut;
  static const double pressInkAlpha = 0.1;

  static const toggle = Duration(milliseconds: 300);
  static const Curve toggleCurve = Curves.easeOutBack;
  static const segment = Duration(milliseconds: 250);
  static const segmentLabel = Duration(milliseconds: 200);
  static const Curve segmentCurve = Curves.easeOutCubic;

  static const fadeThrough = Duration(milliseconds: 300);
  static const Curve fadeIn = Cubic(0, 0, 0.2, 1);
  static const Curve fadeOut = Cubic(0.4, 0, 1, 1);
  static const double fadeThroughFrom = 0.92;

  static const listChange = Duration(milliseconds: 300);
  static const Curve listIn = Curves.easeOutCubic;
  static const Curve listOut = Curves.easeInCubic;

  /// 一次变化超过这么多处时直接替换：大批移动的行互相穿过，看不出变了什么。
  static const int listMaxAnimatedChanges = 50;

  static const modeGlide = Duration(milliseconds: 300);
  static const Curve modeGlideCurve = Curves.ease;

  /// 菜单收起的总时长：先缩回按钮，最后按钮大小的底色淡出。
  static const menuDismiss = Duration(milliseconds: 500);
  static const menuCornersDelay = Duration(milliseconds: 70);
  static const double menuContentBlur = 4;

  /// 被新页面盖住的页面叠加的黑色不透明度。
  static const double coveredDim = 0.1;

  /// 向右拖动页面时，拖满一屏宽缩小这么多。
  static const double dragShrink = 0.3;
}

/// 从元素长出的外框底色有多实：起初透明，进度到 0.3 时不透明。
double morphSolid(double growth) => (growth / 0.3).clamp(0.0, 1.0);

/// 外框里的内容有多清楚：打开时进度 0.2 到 0.55 之间淡入；关闭时进度降到
/// 0.85 开始淡出，0.55 时已看不见，外框还没缩回去，内容先没了。
double morphContent(double growth, {required bool closing}) => closing
    ? ((growth - 0.55) / 0.3).clamp(0.0, 1.0)
    : ((growth - 0.2) / 0.35).clamp(0.0, 1.0);

// UIKit 按 UIScrollView.DecelerationRate.fast（0.99）投影松手后的落点。
const _sheetProjection = 0.99 / (1 - 0.99) / 1000;

/// 面板和任务页松手时，按速度投影的落点越过一半高度就关闭。[drag] 与
/// [velocity] 向下为正，单位是像素和像素每秒。
bool sheetCloses({
  required double drag,
  required double velocity,
  required double height,
}) => drag + velocity * _sheetProjection > height / 2;

const _settle = Tolerance(distance: 1e-3, velocity: 1e-2);

/// 弹簧过冲后在终点附近的尾巴由容差截断，停下时正好落在 [to]：控制器停在
/// 0.9995 这样的位置时，页面会一直被当作还在移动。
Simulation springTo(
  SpringDescription spring, {
  required double from,
  required double to,
  double velocity = 0,
}) {
  return _Arriving(
    SpringSimulation(spring, from, to, velocity, tolerance: _settle),
    to,
  );
}

/// UIKit 的橡皮筋：拉过头 [over] 时实际移动的距离，越拉越难，最多接近 [extent]。
double rubberBand(double over, double extent) =>
    (1 - 1 / (over * 0.55 / extent + 1)) * extent;

/// 减少动态效果时用：立即落在 [value]。
Simulation settledAt(double value) => _Settled(value);

final class _Settled extends Simulation {
  _Settled(this._value);

  final double _value;

  @override
  double x(double time) => _value;

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => true;
}

final class _Arriving extends Simulation {
  _Arriving(this._spring, this._end) : super(tolerance: _spring.tolerance);

  final Simulation _spring;
  final double _end;

  @override
  double x(double time) => _spring.isDone(time) ? _end : _spring.x(time);

  @override
  double dx(double time) => _spring.isDone(time) ? 0 : _spring.dx(time);

  @override
  bool isDone(double time) => _spring.isDone(time);
}

/// 前 [seconds] 秒按 [spring] 走，余下的误差线性补齐，正好在 1 结束。给只接受
/// 固定时长曲线的组件用。
final class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring, {required this.seconds})
    : _simulation = SpringSimulation(spring, 0, 1, 0);

  final double seconds;
  final SpringSimulation _simulation;
  late final double _residual = 1 - _simulation.x(seconds);

  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}

bool reducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
