import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// [durationMs] 不大于 0 表示时长未知。
class PlaybackProgressBar extends StatelessWidget {
  const PlaybackProgressBar({
    required this.positionMs,
    required this.durationMs,
    this.semanticLabel = '播放进度',
    super.key,
  });

  final int positionMs;
  final int durationMs;
  final String semanticLabel;

  static double heightOf(BuildContext context) =>
      AlistenSizes.progressTrack + AlistenSpacing.xs + _timesHeight(context);

  static double _timesHeight(BuildContext context) {
    final time = AlistenTypography.timecode;
    return MediaQuery.textScalerOf(context).scale(time.fontSize!) *
        time.height!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final known = durationMs > 0;
    final position = known
        ? positionMs.clamp(0, durationMs)
        : (positionMs < 0 ? 0 : positionMs);
    final style = AlistenTypography.timecode.copyWith(
      color: colors.onGlassMuted,
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      value: known
          ? '${spokenDuration(position)}，共${spokenDuration(durationMs)}'
          : spokenDuration(position),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomPaint(
            size: const Size.fromHeight(AlistenSizes.progressTrack),
            painter: _TrackPainter(
              played: known ? position / durationMs : 0,
              ink: colors.onGlass,
              empty: colors.outline,
              rtl: Directionality.of(context) == TextDirection.rtl,
            ),
          ),
          const SizedBox(height: AlistenSpacing.xs),
          // 高度固定为一行，与 [heightOf] 保持一致。
          SizedBox(
            height: _timesHeight(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(clockText(position), style: style),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      known ? clockText(durationMs) : '--:--',
                      style: style,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

(int hours, int minutes, int seconds) _parts(int ms) {
  final seconds = ms ~/ 1000;
  return (seconds ~/ 3600, seconds ~/ 60 % 60, seconds % 60);
}

String clockText(int ms) {
  final (hours, minutes, rest) = _parts(ms);
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$ss'
      : '$minutes:$ss';
}

String spokenDuration(int ms) {
  final (hours, minutes, seconds) = _parts(ms);
  return [
    if (hours > 0) '$hours小时',
    if (minutes > 0) '$minutes分',
    if (seconds > 0 || hours + minutes == 0) '$seconds秒',
  ].join();
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.played,
    required this.ink,
    required this.empty,
    required this.rtl,
  });

  final double played;
  final Color ink;
  final Color empty;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = empty,
    );
    if (played <= 0) return;
    final width = size.width * played.clamp(0.0, 1.0);
    final filled = rtl
        ? Rect.fromLTWH(size.width - width, 0, width, size.height)
        : Rect.fromLTWH(0, 0, width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(filled, radius),
      Paint()..color = ink,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) {
    return oldDelegate.played != played ||
        oldDelegate.ink != ink ||
        oldDelegate.empty != empty ||
        oldDelegate.rtl != rtl;
  }
}
