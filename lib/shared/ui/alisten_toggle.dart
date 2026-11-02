import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

class AlistenToggle extends StatelessWidget {
  const AlistenToggle({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final onChanged = this.onChanged;
    final duration = AlistenDurations.of(context, AlistenDurations.short);
    final pill = BorderRadius.circular(AlistenRadii.pill);
    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged(!value),
      semanticLabel: semanticLabel,
      button: false,
      toggled: value,
      focusRadius: pill,
      child: SizedBox(
        height: AlistenSizes.minTouchTarget,
        child: Center(
          widthFactor: 1,
          child: AnimatedContainer(
            duration: duration,
            curve: AlistenCurves.standard,
            width: AlistenSizes.toggleTrack.width,
            height: AlistenSizes.toggleTrack.height,
            padding: const EdgeInsets.all(AlistenSizes.toggleInset),
            decoration: BoxDecoration(
              borderRadius: pill,
              gradient: value ? colors.brandGradient : null,
              color: value ? null : colors.outline,
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: AlistenCurves.bounce,
              alignment: value
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: Container(
                width: _knob,
                height: _knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.knob,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.shadow
                          .withValues(alpha: 0.2),
                      blurRadius: AlistenSpacing.xs,
                      offset: const Offset(0, AlistenSpacing.xxs / 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _knob = AlistenSizes.toggleTrack.height - 2 * AlistenSizes.toggleInset;
