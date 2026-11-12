import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/aurora_background.dart';
import 'package:alisten/shared/ui/cover_backdrop.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:alisten/shared/ui/visible_frames.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 与极光相同：色块大而柔和，约 30 帧/秒已足够平滑，也不随 120 Hz 屏幕翻倍。
const _frameInterval = Duration(milliseconds: 33);

const _periodASeconds = 120.0;
const _periodBSeconds = 70.0;
const _periodCSeconds = 90.0;
const _warpDivisor = 3.5;

const _shaderAsset = 'shaders/flowing_cover.frag';

// 着色器按物理像素的这个比例出图，再放大铺满。色块大而柔和，放大看不出差别；
// 抗色带的噪点在半分辨率下仍然够细。
const _renderScale = 0.5;

/// 角度取模后才传给着色器：`mediump` 下持续增长的时间值放久了会抖动。
@visibleForTesting
({double a, double b, double c, double warp}) flowPhase(double seconds) {
  double angle(double period) => 2 * math.pi * ((seconds / period) % 1);
  return (
    a: angle(_periodASeconds),
    b: angle(_periodBSeconds),
    c: angle(_periodCSeconds),
    warp: (math.sin(seconds / _warpDivisor) + 1) / 2,
  );
}

/// 房间页的背景：模糊的封面缓慢流动。没有封面时显示极光。
class FlowingCoverBackdrop extends StatefulWidget {
  const FlowingCoverBackdrop({required this.url, super.key});

  final String? url;

  @override
  State<FlowingCoverBackdrop> createState() => _FlowingCoverBackdropState();
}

class _FlowingCoverBackdropState extends State<FlowingCoverBackdrop>
    with WidgetsBindingObserver, VisibleFrames {
  final _frame = ValueNotifier<int>(0);
  ui.FragmentShader? _shader;
  bool _shaderFailed = false;

  ui.Image? _from;
  ui.Image? _to;

  // 最近一次着色器出的图。别的动画让房间页每帧重新合成时，只贴这张图，不必
  // 每帧在全屏上重跑着色器。
  ui.Image? _rendered;
  double _mix = 1;
  double _alpha = 0;
  bool _showing = false;

  Timer? _timer;
  int _load = 0;
  String? _loadedUrl;
  bool _urlSeen = false;

  // 只累计实际流动的时长，暂停后恢复不会跳变。
  Duration _drifted = Duration.zero;
  Duration _fadeBase = Duration.zero;

  double get _fadeSeconds {
    return AlistenDurations.backdrop.inMicroseconds /
        Duration.microsecondsPerSecond;
  }

  Duration get _elapsed {
    final timer = _timer;
    return timer == null ? _drifted : _drifted + _frameInterval * timer.tick;
  }

  bool get _flowing {
    return onScreen &&
        !keyboardUp &&
        !animationsRemoved &&
        _to != null &&
        _shader != null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(_shaderAsset);
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      visibleFramesChanged();
    } on Object catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'alisten',
          context: ErrorDescription('while loading the backdrop shader'),
        ),
      );
      if (mounted) setState(() => _shaderFailed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_urlSeen) {
      _urlSeen = true;
      unawaited(_loadCover(widget.url));
    }
  }

  @override
  void didUpdateWidget(FlowingCoverBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) unawaited(_loadCover(widget.url));
  }

  @override
  void visibleFramesChanged() {
    final flowing = _flowing;
    final timer = _timer;
    if (flowing == (timer != null)) return;
    if (timer == null) {
      _timer = Timer.periodic(_frameInterval, _advance);
    } else {
      _drifted += _frameInterval * timer.tick;
      timer.cancel();
      _timer = null;
      _finishFade();
    }
  }

  // 新封面就绪之前旧封面保持不动，不经过无封面的状态。
  Future<void> _loadCover(String? url) async {
    final load = ++_load;
    if (url == null || url.isEmpty) {
      _loadedUrl = null;
      _hide();
      return;
    }
    if (url == _loadedUrl) return;
    final image = await blurredCoverOf(CoverImages.of(context, url));
    if (!mounted || load != _load) {
      image?.dispose();
      return;
    }
    _loadedUrl = image == null ? null : url;
    if (image == null) {
      _hide();
    } else {
      _show(image);
    }
  }

  void _show(ui.Image image) {
    _from?.dispose();
    _from = _to;
    _to = image;
    _mix = _from == null ? 1 : 0;
    _showing = true;
    _fadeBase = _elapsed;
    setState(() {});
    visibleFramesChanged();
    if (_timer == null) _finishFade();
  }

  void _hide() {
    if (_to == null) return;
    _showing = false;
    _fadeBase = _elapsed;
    if (_timer == null) {
      _finishFade();
    } else {
      setState(() {});
    }
  }

  void _finishFade() {
    if (_mix < 1 || _from != null) {
      _from?.dispose();
      _from = null;
    }
    _mix = 1;
    _alpha = _showing ? 1 : 0;
    if (!_showing) {
      _to?.dispose();
      _to = null;
    }
    if (mounted) {
      setState(() {});
      // 画面可能停在淡入途中，而着色器的输入没有变。
      _frame.value++;
    }
  }

  void _advance(Timer _) {
    final seconds =
        (_elapsed - _fadeBase).inMicroseconds / Duration.microsecondsPerSecond;
    final progress = (seconds / _fadeSeconds).clamp(0.0, 1.0);
    final auroraWasNeeded = _alpha < 1;
    if (_from != null) {
      _mix = progress;
    }
    _alpha = _showing
        ? math.max(_alpha, progress)
        : math.min(_alpha, 1 - progress);
    if (progress >= 1 && (_from != null || !_showing)) {
      _finishFade();
      visibleFramesChanged();
    } else if (auroraWasNeeded != (_alpha < 1)) {
      setState(() {});
    }
    _frame.value++;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _load++;
    _frame.dispose();
    _rendered?.dispose();
    _shader?.dispose();
    _from?.dispose();
    _to?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final image = _to;
    final shader = _shader;
    final hasFlow = image != null && shader != null;
    final hasStill = image != null && _shaderFailed;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surface),
        if (!hasStill && (!hasFlow || _alpha < 1)) const AuroraBackground(),
        if (hasFlow)
          RepaintBoundary(
            child: CustomPaint(
              painter: _FlowPainter(
                shader: shader,
                from: _from ?? image,
                to: image,
                frame: _frame,
                state: this,
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
        if (hasStill)
          RawImage(
            image: image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        DecoratedBox(decoration: BoxDecoration(gradient: colors.scrim)),
      ],
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.shader,
    required this.from,
    required this.to,
    required this.frame,
    required this.state,
    required this.pixelRatio,
  }) : super(repaint: frame);

  final ui.FragmentShader shader;
  final ui.Image from;
  final ui.Image to;
  final ValueListenable<int> frame;
  final _FlowingCoverBackdropState state;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final width = (size.width * pixelRatio * _renderScale).ceil();
    final height = (size.height * pixelRatio * _renderScale).ceil();
    if (width <= 0 || height <= 0) return;
    final seconds =
        state._elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final phase = flowPhase(seconds);
    shader
      ..setFloat(0, width.toDouble())
      ..setFloat(1, height.toDouble())
      ..setFloat(2, phase.a)
      ..setFloat(3, phase.b)
      ..setFloat(4, phase.c)
      ..setFloat(5, phase.warp)
      ..setFloat(6, state._mix)
      ..setFloat(7, state._alpha)
      // 默认是最近邻采样，放大小图时会出现方块。
      ..setImageSampler(0, from, filterQuality: FilterQuality.low)
      ..setImageSampler(1, to, filterQuality: FilterQuality.low);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    final rendered = picture.toImageSync(width, height);
    picture.dispose();
    state._rendered?.dispose();
    state._rendered = rendered;
    canvas.drawImageRect(
      rendered,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_FlowPainter oldDelegate) {
    return !identical(oldDelegate.from, from) ||
        !identical(oldDelegate.to, to) ||
        !identical(oldDelegate.shader, shader) ||
        oldDelegate.pixelRatio != pixelRatio;
  }
}
