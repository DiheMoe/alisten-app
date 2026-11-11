import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:flutter/material.dart';

class ShowPasswordRow extends StatelessWidget {
  const ShowPasswordRow({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Row(
      children: [
        Expanded(
          child: ExcludeSemantics(
            child: Text(
              '显示密码',
              style: AlistenTypography.body.copyWith(color: colors.onGlass),
            ),
          ),
        ),
        AlistenToggle(
          value: value,
          onChanged: onChanged,
          semanticLabel: '显示密码',
        ),
      ],
    );
  }
}
