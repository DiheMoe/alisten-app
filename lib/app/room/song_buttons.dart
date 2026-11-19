import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/material.dart';

/// 房间里点歌的两个按钮只有图标，长按时说明用途；读屏直接读到用途。
///
/// 搜歌最常用，用品牌色；从歌单点歌用玻璃底，两边不都是重色。
class SearchSongsButton extends StatelessWidget {
  const SearchSongsButton({
    required this.onPressed,
    this.diameter = AlistenSizes.iconButton,
    super.key,
  });

  final VoidCallback onPressed;
  final double diameter;

  @override
  Widget build(BuildContext context) => _SongButton(
    icon: AlistenIcons.magnifyingGlass,
    label: '搜歌',
    style: IconCircleButtonStyle.brand,
    diameter: diameter,
    onPressed: onPressed,
  );
}

class PickFromPlaylistsButton extends StatelessWidget {
  const PickFromPlaylistsButton({
    required this.onPressed,
    this.diameter = AlistenSizes.iconButton,
    super.key,
  });

  final VoidCallback onPressed;
  final double diameter;

  @override
  Widget build(BuildContext context) => _SongButton(
    icon: AlistenIcons.plusBold,
    label: '从歌单点歌',
    style: IconCircleButtonStyle.glass,
    diameter: diameter,
    onPressed: onPressed,
  );
}

class _SongButton extends StatelessWidget {
  const _SongButton({
    required this.icon,
    required this.label,
    required this.style,
    required this.diameter,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final IconCircleButtonStyle style;
  final double diameter;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(AlistenRadii.sm),
        border: Border.all(color: colors.glassStroke),
      ),
      textStyle: AlistenTypography.secondary.copyWith(color: colors.onGlass),
      child: IconCircleButton(
        icon: icon,
        semanticLabel: label,
        style: style,
        diameter: diameter,
        onPressed: onPressed,
      ),
    );
  }
}
