import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:flutter/material.dart';

class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({required this.url, this.child, super.key});

  final String? url;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final url = this.url;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surface),
        RepaintBoundary(
          child: AnimatedSwitcher(
            duration: AlistenDurations.of(context, AlistenDurations.backdrop),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: url == null || url.isEmpty
                ? const SizedBox.expand()
                : _BlurredCover(
                    key: ValueKey(url),
                    cover: CoverImages.of(context, url),
                  ),
          ),
        ),
        ?child,
        DecoratedBox(decoration: BoxDecoration(gradient: colors.scrim)),
      ],
    );
  }
}

// 模糊后看不出细节，按这个宽度解码即可。
const _decodeWidth = 48;

// 只在小正方形上模糊一次，之后每帧把结果拉伸铺满屏幕：在全屏纹理上逐帧计算
// 大半径模糊太贵，进出房间页的转场会掉帧。
const _side = 96.0;
const _overscan = 1.25;
const _blurSigma = _side * _overscan * 0.05;

ui.Image blurCoverOnce(ui.Image cover) {
  const bounds = Rect.fromLTWH(0, 0, _side, _side);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _blurSigma,
          sigmaY: _blurSigma,
          tileMode: TileMode.clamp,
        ),
    );
  paintImage(
    canvas: canvas,
    rect: Rect.fromCenter(
      center: bounds.center,
      width: _side * _overscan,
      height: _side * _overscan,
    ),
    image: cover,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );
  canvas.restore();
  final picture = recorder.endRecording();
  final blurred = picture.toImageSync(_side.toInt(), _side.toInt());
  picture.dispose();
  return blurred;
}

/// 取不到封面时为 null，从不抛出。
Future<ui.Image?> blurredCoverOf(ImageProvider cover) {
  final result = Completer<ui.Image?>();
  final stream = ResizeImage(
    cover,
    width: _decodeWidth,
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(ui.Image? image) {
    stream.removeListener(listener);
    if (!result.isCompleted) result.complete(image);
  }

  listener = ImageStreamListener((info, _) {
    ui.Image? blurred;
    // 监听器抛出的异常会被图片流当作加载失败静默处理，需自行上报。
    try {
      blurred = blurCoverOnce(info.image);
    } catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'alisten',
          context: ErrorDescription('while blurring a cover'),
        ),
      );
    } finally {
      info.dispose();
    }
    finish(blurred);
  }, onError: (_, _) => finish(null));
  stream.addListener(listener);
  return result.future;
}

class _BlurredCover extends StatefulWidget {
  const _BlurredCover({required this.cover, super.key});

  final ImageProvider cover;

  @override
  State<_BlurredCover> createState() => _BlurredCoverState();
}

class _BlurredCoverState extends State<_BlurredCover> {
  late final _listener = ImageStreamListener(
    _show,
    onError: (_, _) => _stopListening(),
  );

  // 只订阅到第一帧：动图封面也只模糊一次，不随帧重做。
  ImageStream? _stream;
  ui.Image? _blurred;
  bool _subscribing = false;

  @override
  void initState() {
    super.initState();
    final stream = _stream = ResizeImage(
      widget.cover,
      width: _decodeWidth,
    ).resolve(ImageConfiguration.empty);
    // 封面已缓存时，addListener 会同步回调，此时仍在 initState 中，不能
    // setState。
    _subscribing = true;
    stream.addListener(_listener);
    _subscribing = false;
  }

  void _stopListening() {
    _stream?.removeListener(_listener);
    _stream = null;
  }

  void _show(ImageInfo info, bool _) {
    _stopListening();
    ui.Image? blurred;
    // 监听器抛出的异常会被图片流当作加载失败交给 onError 静默处理，需自行上报。
    try {
      blurred = blurCoverOnce(info.image);
      if (_subscribing) {
        _blurred = blurred;
      } else {
        setState(() => _blurred = blurred);
      }
    } catch (exception, stack) {
      if (!identical(blurred, _blurred)) blurred?.dispose();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'alisten',
          context: ErrorDescription('while blurring a cover for the backdrop'),
        ),
      );
    } finally {
      info.dispose();
    }
  }

  @override
  void dispose() {
    _stopListening();
    _blurred?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blurred = _blurred;
    if (blurred == null) return const SizedBox.expand();
    return RawImage(
      image: blurred,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }
}
