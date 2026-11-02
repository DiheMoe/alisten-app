import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AlistenSpacing.page,
      AlistenSpacing.xl,
      AlistenSpacing.page,
      AlistenSpacing.sm,
    ),
    super.key,
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AlistenTypography.title.copyWith(
                  color: AlistenColors.of(context).onGlass,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AlistenSpacing.sm),
            trailing,
          ],
        ],
      ),
    );
  }
}
