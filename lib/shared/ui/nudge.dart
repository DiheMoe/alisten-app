import 'dart:async';

import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

const _distance = 5.0;

/// [trigger] 变成新的非空值时，把 [child] 向前推一下再弹回。
class Nudge extends StatefulWidget {
  const Nudge({required this.trigger, required this.child, super.key});

  final Object? trigger;
  final Widget child;

  @override
  State<Nudge> createState() => _NudgeState();
}

class _NudgeState extends State<Nudge> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: AlistenDurations.bounce,
  );

  late final Animation<double> _offset = _motion.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: _distance,
        ).chain(CurveTween(curve: AlistenCurves.standard)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: _distance,
          end: 0,
        ).chain(CurveTween(curve: AlistenCurves.bounce)),
        weight: 75,
      ),
    ]),
  );

  @override
  void didUpdateWidget(Nudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final trigger = widget.trigger;
    if (trigger == null || trigger == oldWidget.trigger) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    unawaited(_motion.forward(from: 0));
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_offset.value, 0), child: child),
      child: widget.child,
    );
  }
}
