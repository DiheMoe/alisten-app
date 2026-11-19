import 'package:alisten/features/playlists/presentation/playlist_cover.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/arrival_fade.dart';
import 'package:alisten/shared/ui/cover_backdrop.dart';
import 'package:alisten/shared/ui/shared_text.dart';
import 'package:flutter/material.dart';

/// 顶栏浮在页头之上，所以内容从顶栏下方开始。
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    required this.coverUrl,
    required this.favorites,
    required this.name,
    this.facts,
    this.children = const [],
    this.heroTags,
    super.key,
  });

  final String? coverUrl;

  /// 列表里的封面、名字和说明飞到这里时用的标签。
  final PlaylistHeroTags? heroTags;
  final bool favorites;
  final String name;
  final String? facts;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    final facts = this.facts;
    final top =
        MediaQuery.paddingOf(context).top +
        AlistenSizes.minTouchTarget +
        AlistenSpacing.xs;
    return Stack(
      children: [
        // 封面飞到位、页面停稳后才铺上模糊的封面背景。
        Positioned.fill(
          child: ArrivalFade(child: CoverBackdrop(url: coverUrl)),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.5, 1],
                colors: [surface.withValues(alpha: 0), surface],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AlistenSpacing.xxl,
            top,
            AlistenSpacing.xxl,
            AlistenSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: PlaylistCover(
                  url: coverUrl,
                  favorites: favorites,
                  size: AlistenSizes.pageCover,
                  radius: AlistenRadii.lg,
                  shadow: true,
                  heroTag: heroTags?.cover,
                ),
              ),
              const SizedBox(height: AlistenSpacing.lg),
              Semantics(
                header: true,
                child: Center(
                  child: _shared(
                    heroTags?.name,
                    PlaylistName(
                      name: name,
                      favorites: favorites,
                      maxLines: 2,
                      center: true,
                      style: AlistenTypography.weighted(
                        AlistenTypography.title,
                        FontWeight.w700,
                      ).copyWith(color: colors.onGlass),
                    ),
                  ),
                ),
              ),
              if (facts != null) ...[
                const SizedBox(height: AlistenSpacing.xs),
                Center(
                  child: _shared(
                    heroTags?.facts,
                    Text(
                      facts,
                      textAlign: TextAlign.center,
                      style: AlistenTypography.secondary.copyWith(
                        color: colors.onGlassMuted,
                      ),
                    ),
                  ),
                ),
              ],
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}

Widget _shared(Object? tag, Widget child) =>
    tag == null ? child : SharedText(tag: tag, child: child);
