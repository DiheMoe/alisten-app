import 'dart:async';

import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

class Collapsible extends StatefulWidget {
  const Collapsible({required this.open, required this.child, super.key});

  final bool open;
  final Widget child;

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion =
      AnimationController(vsync: this, value: widget.open ? 1 : 0)
        ..addStatusListener((status) {
          if (status.isDismissed && mounted) setState(() {});
        });
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _motion,
    curve: AlistenCurves.standard,
    reverseCurve: AlistenCurves.exit,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = AlistenDurations.of(context, AlistenDurations.short);
  }

  @override
  void didUpdateWidget(Collapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    unawaited(widget.open ? _motion.forward() : _motion.reverse());
  }

  @override
  void dispose() {
    _size.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && _motion.isDismissed) return const SizedBox.shrink();
    // 展开和收起保持相同的组件结构，收起途中再展开时内容不丢失状态。
    final closing = !widget.open;
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        ignoring: closing,
        child: ExcludeFocus(excluding: closing, child: widget.child),
      ),
    );
  }
}
