import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:flutter/material.dart';

class PageGlow extends StatelessWidget {
  const PageGlow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AlistenColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    RadialGradient light(
      Color color,
      Alignment center,
      double radius,
      double strength,
    ) {
      return RadialGradient(
        center: center,
        radius: radius,
        colors: [
          color.withValues(alpha: strength),
          color.withValues(alpha: 0),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.colorScheme.surface),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: light(
              colors.aurora[0],
              const Alignment(-0.9, -1.1),
              1.2,
              dark ? 0.2 : 0.12,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: light(
              colors.aurora[1],
              const Alignment(1.1, -0.7),
              0.9,
              dark ? 0.12 : 0.07,
            ),
          ),
        ),
      ],
    );
  }
}
